# Terraform Bootstrap

This is the first repository I run before anything else in the Enterprise Data Platform. Its only job is to create the remote storage that Terraform uses to track what infrastructure it has already created.

Nothing else in this project can be built until this exists.

---

## Why this has to come first

Terraform (an infrastructure-as-code tool) keeps a record of every resource it creates in a file called `terraform.tfstate`. Think of this file like a receipt. Every time Terraform creates an S3 (Simple Storage Service) bucket or a DMS (Database Migration Service) replication instance, it writes that down. Next time I run Terraform, it reads that receipt and compares it against what I want, so it only creates or changes what is different.

By default, Terraform stores this receipt file on my local machine. That is a problem for a few reasons:

- If my laptop breaks or gets reformatted, the state file is gone and Terraform has no idea what it already created
- If I switch computers, the state file is not there
- If someone else ever works on this project, they have no state file and Terraform thinks nothing exists

The solution is to store the state file remotely in an S3 bucket. That way it is always accessible, versioned, encrypted, and safe.

I also use DynamoDB (Amazon's NoSQL key-value database) as a lock. If two Terraform commands ever run at the same time against the same environment (which could corrupt the state file), DynamoDB prevents the second one from starting until the first finishes.

This bootstrap repository creates that S3 bucket and that DynamoDB table. Once they exist, all other Terraform in this project stores its state there.

---

## Why dev, staging, and prod are separate

I run this bootstrap process once per AWS account. I have three accounts: dev, staging, and prod. Each one gets its own state bucket and its own lock table.

The reason for separation is isolation. If something goes wrong in dev (a bug, an experimental change, a cost spike), it cannot affect staging or prod in any way. Each account is an independent boundary. Dev state cannot overwrite prod state because they live in completely different S3 buckets in completely different AWS accounts.

---

## Repository structure

```
terraform-bootstrap/
│
├── versions.tf                      Locks Terraform and AWS provider versions
├── .gitignore                       Prevents sensitive files from being committed
├── README.md                        This file
│
├── modules/
│   └── state-backend/
│       ├── main.tf                  Creates the S3 bucket and DynamoDB table
│       ├── variables.tf             Input variables for the module
│       └── outputs.tf               Exports the bucket and table names
│
└── environments/
    ├── dev/
    │   ├── main.tf                  Calls the module with dev-specific values
    │   ├── variables.tf             Dev-specific variables (region, profile)
    │   └── backend.tf               Remote backend config (starts commented out)
    │
    ├── staging/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── backend.tf
    │
    └── prod/
        ├── main.tf
        ├── variables.tf
        └── backend.tf
```

---

## Root-level files

### versions.tf

This file locks the versions of Terraform and the AWS provider so the code behaves the same way every time it runs, on any machine.

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

The `required_version` line means Terraform 1.6.0 or higher must be installed. The `~> 5.0` for the AWS provider means any version in the 5.x range is fine, but version 6 would not be allowed. This protects against breaking changes in future provider releases.

### .gitignore

This file tells Git which files to never commit to the repository.

```
.terraform/
*.tfstate
*.tfstate.*
crash.log
.terraform.lock.hcl
.vscode/
.DS_Store
```

The most important entries are `*.tfstate` and `*.tfstate.*`. State files contain resource IDs, configuration details, and sometimes sensitive data. They must never be committed to version control.

---

## The state-backend module

This module is reusable. I call it from each environment (dev, staging, prod) with different input values. The module itself creates the same two resources every time: an S3 bucket and a DynamoDB table.

### variables.tf

```hcl
variable "bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
}

variable "environment" {
  description = "Environment identifier"
  type        = string
}
```

These three variables are what make the module reusable. I pass different values when calling the module from dev vs staging vs prod.

### main.tf

**The S3 state bucket:**

```hcl
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "EnterpriseDataPlatform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

The `prevent_destroy = true` setting in the lifecycle block is critical. It means Terraform will refuse to delete this bucket even if I run `terraform destroy`. This is intentional - the state bucket is the foundation of everything. If I accidentally delete it, Terraform loses track of all infrastructure. I have to manually remove this protection if I ever genuinely want to destroy the bucket.

**Versioning:**

```hcl
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

With versioning enabled, S3 keeps every previous version of the state file. If a bad Terraform apply corrupts the state file, I can restore an earlier version of it.

**Encryption:**

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

AES256 (Advanced Encryption Standard with 256-bit keys) encrypts every file stored in this bucket. The state file can contain resource IDs and configuration details, so encrypting it at rest is a basic security requirement.

**The DynamoDB lock table:**

```hcl
resource "aws_dynamodb_table" "locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

When Terraform runs, it writes a lock record to this DynamoDB table before making any changes. If another Terraform process tries to run at the same time, it sees the lock and waits (or errors out). This prevents two applies from running simultaneously and corrupting the state file. `PAY_PER_REQUEST` means I only pay when the table is actually used, which for a lock table is almost nothing.

### outputs.tf

```hcl
output "state_bucket_name" {
  value = aws_s3_bucket.state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.locks.name
}
```

These outputs surface the bucket name and table name after deployment. I can reference these when configuring other Terraform projects to use this backend.

---

## Environment configuration

Each folder inside `environments/` is a standalone Terraform configuration. Terraform only reads files in the current directory, so I have to navigate into the right environment folder before running any commands.

### environments/dev/variables.tf

```hcl
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type    = string
  default = "dev-admin"
}
```

These tell Terraform which AWS region to use and which CLI (Command Line Interface) profile to authenticate with. The `dev-admin` profile corresponds to the SSO (Single Sign-On) profile I configured for the dev AWS account.

### environments/dev/main.tf

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

module "state_backend" {
  source = "../../modules/state-backend"

  bucket_name         = "enterprise-data-platform-tfstate-dev"
  dynamodb_table_name = "enterprise-data-platform-tf-lock-dev"
  environment         = "dev"
}
```

The `provider` block tells Terraform how to authenticate with AWS. The `module` block calls the reusable state-backend module with dev-specific values.

### environments/dev/backend.tf

This file starts commented out. This is intentional and important.

```hcl
# terraform {
#   backend "s3" {
#     bucket         = "enterprise-data-platform-tfstate-dev"
#     key            = "bootstrap/terraform.tfstate"
#     region         = "eu-central-1"
#     dynamodb_table = "enterprise-data-platform-tf-lock-dev"
#     profile        = "dev-admin"
#     encrypt        = true
#   }
# }
```

The reason it starts commented out: the S3 bucket and DynamoDB table do not exist yet when I first run Terraform. I cannot tell Terraform to store its state in a bucket that has not been created. So I apply with local state first (which creates the bucket), then uncomment this file and run `terraform init -reconfigure` to migrate the local state into the new S3 bucket.

### Staging and prod

The staging and prod environment folders follow the same pattern as dev. The only values that change are:

- `aws_profile` - `staging-admin` or `prod-admin`
- `bucket_name` - includes `staging` or `prod` in the name
- `dynamodb_table_name` - includes `staging` or `prod` in the name
- `environment` - `staging` or `prod`

---

## Full deployment procedure

Repeat these steps for each environment: dev first, then staging, then prod.

### Step 1 - Log in to AWS

```bash
aws sso login --profile dev-admin
```

This refreshes the temporary SSO (Single Sign-On) credentials for the dev account. SSO credentials expire after a few hours, so I always run this before any Terraform command.

### Step 2 - Navigate to the environment

```bash
cd terraform-bootstrap/environments/dev
```

### Step 3 - Initialize Terraform

```bash
terraform init
```

This downloads the AWS provider plugin and sets up the working directory. It reads the `versions.tf` file to know which provider to download.

### Step 4 - Apply

```bash
terraform apply
```

Terraform shows a plan of what it will create. I type `yes` to confirm. This creates:
- The S3 state bucket (`enterprise-data-platform-tfstate-dev`)
- The DynamoDB lock table (`enterprise-data-platform-tf-lock-dev`)

At this point, state is stored locally in a `terraform.tfstate` file in the environments/dev folder.

### Step 5 - Enable remote state

Now that the S3 bucket exists, I can migrate state into it.

Open `environments/dev/backend.tf` and uncomment everything inside it.

Then run:

```bash
terraform init -reconfigure
```

Terraform detects the backend configuration has changed, reads the local state file, and uploads it to S3. From this point on, state is stored remotely. The local `terraform.tfstate` file is no longer used.

---

## What happens inside Terraform

It helps to understand what each Terraform command actually does:

**`terraform init`**
- Downloads the AWS provider plugin from the Terraform Registry
- Reads the backend configuration and connects to the remote state
- Registers any module paths

**`terraform plan`**
- Calls AWS APIs to check the current real state of resources
- Compares that against what the code describes
- Shows exactly what would be created, changed, or destroyed

**`terraform apply`**
- Runs the plan
- Calls AWS APIs to create or modify resources
- Writes the results to the state file

---

## Setting up AWS CLI SSO profiles

This section covers setting up the AWS CLI (Command Line Interface) to authenticate using IAM (Identity and Access Management) Identity Center, which is AWS's SSO (Single Sign-On) service. I use this instead of static access keys because SSO credentials are temporary and automatically rotated.

### Step 1 - Verify AWS CLI version

```bash
aws --version
```

The output must show `aws-cli/2.x.x`. Version 2 is required for SSO support.

### Step 2 - Create a shared SSO session

```bash
aws configure sso-session
```

When prompted:

```
SSO session name:   platform-session
SSO start URL:      https://d-xxxxxxxxxx.awsapps.com/start
SSO region:         us-east-1
SSO registration scopes: (press Enter for default)
```

The SSO start URL comes from the AWS IAM Identity Center console in the management account. This creates a shared session that all three profiles (dev, staging, prod) will use.

### Step 3 - Log in to the SSO session

```bash
aws sso login --sso-session platform-session
```

A browser window opens. I authenticate and click Allow. This creates a temporary token that is valid for a few hours.

### Step 4 - Configure the dev profile

```bash
aws configure sso --profile dev-admin
```

When prompted:

```
SSO session name: platform-session
(Select the dev AWS account from the list)
Role: AdministratorAccess
CLI default region: eu-central-1
CLI default output format: json
```

This creates a local CLI profile named `dev-admin`. When Terraform uses this profile, it assumes the AdministratorAccess role in the dev account using temporary credentials from the SSO session.

### Step 5 - Verify the dev profile works

```bash
aws sso login --profile dev-admin
aws sts get-caller-identity --profile dev-admin
```

`STS` stands for Security Token Service. The `get-caller-identity` command returns the account ID and the ARN (Amazon Resource Name, which is the unique identifier for AWS resources) of the authenticated role. If this shows the dev account ID, the profile is working correctly.

### Step 6 - Repeat for staging and prod

```bash
aws configure sso --profile staging-admin
aws sso login --profile staging-admin
aws sts get-caller-identity --profile staging-admin

aws configure sso --profile prod-admin
aws sso login --profile prod-admin
aws sts get-caller-identity --profile prod-admin
```

Use the same SSO session name (`platform-session`) and select the correct account for each.

### Important: SSO tokens expire

SSO tokens are temporary. They expire after a few hours (the exact duration depends on the session policy set by the AWS administrator).

Before running any Terraform command, I always refresh the login:

```bash
aws sso login --profile dev-admin
```

Terraform does not automatically refresh expired SSO tokens. If the token has expired and I run `terraform plan`, it will fail with an authentication error.

---

## End result

After completing this bootstrap for all three environments, I have:

- An S3 state bucket in the dev account
- A DynamoDB lock table in the dev account
- An S3 state bucket in the staging account
- A DynamoDB lock table in the staging account
- An S3 state bucket in the prod account
- A DynamoDB lock table in the prod account
- Three SSO profiles configured: dev-admin, staging-admin, prod-admin
- No static access keys anywhere

Every other Terraform project in this platform will use these buckets to store its state. The bootstrap repository is the root of trust for all infrastructure that follows.
