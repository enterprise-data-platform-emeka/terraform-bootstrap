# Terraform Bootstrap — Complete Beginner-to-Enterprise Guide

This document explains, step by step, how to build and understand the **Terraform Bootstrap** repository for a multi-account AWS enterprise environment.

The goal of this bootstrap repository is simple:

> Create secure, isolated, remote Terraform state infrastructure for Dev, Staging, and Prod environments.

Nothing else.

---

# 1. What Problem Are We Solving?

Terraform uses a file called:

terraform.tfstate

This file stores metadata about:

* What infrastructure exists
* Resource IDs
* Dependencies
* Current configuration state

By default, Terraform stores this file locally.

Local state is dangerous in enterprise environments because it:

* Is not shared
* Is not versioned
* Is not encrypted
* Is not locked
* Can easily be corrupted

Enterprise systems must use **remote state**.

We will use:

* Amazon S3 (Simple Storage Service) → Remote state storage
* Amazon DynamoDB (NoSQL database) → State locking

---

# 2. Why Separate Dev, Staging, and Prod?

Each AWS account is an isolation boundary.

We must isolate:

* State buckets
* Lock tables
* Access credentials

Each environment will have:

* Its own S3 bucket
* Its own DynamoDB lock table
* Its own AWS CLI profile

This prevents:

* Cross-environment corruption
* Accidental production impact
* Shared blast radius

---

# 3. Repository Structure

Create the following structure:
```
terraform-bootstrap/
│
├── versions.tf
├── .gitignore
├── README.md
│
├── modules/
│   └── state-backend/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/
├── dev/
│   ├── main.tf
│   ├── variables.tf
│   └── backend.tf
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

# 4. Root-Level Files

## 4.1 versions.tf

Purpose:

* Lock Terraform version
* Lock AWS provider version

Content:

```
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

Explanation:

* required_version prevents incompatible Terraform CLI versions.
* required_providers ensures stable provider versions.
* "~> 5.0" allows 5.x but blocks 6.x (breaking changes).

---

## 4.2 .gitignore

Purpose:

Prevent sensitive or generated files from being committed.

Content:

```
.terraform/
*.tfstate
*.tfstate.*
crash.log
.terraform.lock.hcl
.vscode/
Thumbs.db
.DS_Store
```

Never commit state files.

---

# 5. Module: state-backend

This module creates:

* S3 bucket (remote state)
* S3 versioning
* S3 encryption
* DynamoDB lock table

Modules are reusable Terraform components.

---

## 5.1 modules/state-backend/variables.tf

```
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

These variables make the module reusable for all environments.

---

## 5.2 modules/state-backend/main.tf

### S3 Bucket

```
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

Explanation:

* resource declares infrastructure.
* aws_s3_bucket is AWS resource type.
* bucket uses module input variable.
* prevent_destroy protects bucket from accidental deletion.

---

### Versioning

```
resource "aws_s3_bucket_versioning" "versioning" {
bucket = aws_s3_bucket.state.id

versioning_configuration {
status = "Enabled"
}
}
```

Versioning protects historical state versions.

---

### Encryption

```
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
bucket = aws_s3_bucket.state.id

rule {
apply_server_side_encryption_by_default {
sse_algorithm = "AES256"
}
}
}
```

Ensures state is encrypted at rest.

---

### DynamoDB Lock Table

```
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

This table prevents concurrent terraform apply operations.

---

## 5.3 modules/state-backend/outputs.tf

```
output "state_bucket_name" {
value = aws_s3_bucket.state.id
}

output "lock_table_name" {
value = aws_dynamodb_table.locks.name
}
```

Outputs expose resource values after deployment.

---

# 6. Environment-Level Configuration

Each folder inside environments/ is a Terraform root module.

Terraform executes only from the current directory.

---

# 6.1 DEV

## environments/dev/variables.tf

```
variable "aws_region" {
type    = string
default = "eu-central-1"
}

variable "aws_profile" {
type    = string
default = "dev-admin"
}
```

These variables define:

* Which AWS region
* Which AWS CLI profile

---

## environments/dev/main.tf

```
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

Explanation:

* provider block tells Terraform how to authenticate.
* module block calls reusable state-backend module.

---

## environments/dev/backend.tf

Initially comment this entire file:

```

# terraform {

# backend "s3" {

# bucket         = "enterprise-data-platform-tfstate-dev"

# key            = "bootstrap/terraform.tfstate"

# region         = "eu-central-1"

# dynamodb_table = "enterprise-data-platform-tf-lock-dev"

# profile        = "dev-admin"

# encrypt        = true

# }

# }

```

Why commented?

Because Terraform cannot use a remote backend until the bucket exists.

---

# 6.2 STAGING

Copy dev folder.

Change:

* aws_profile → staging-admin
* bucket name → tfstate-staging
* lock table → tf-lock-staging
* environment → staging

---

# 6.3 PROD

Copy dev folder.

Change:

* aws_profile → prod-admin
* bucket name → tfstate-prod
* lock table → tf-lock-prod
* environment → prod

---

# 7. Deployment Procedure (Manual Bootstrap)

Perform for each environment.

---

## Step 1 — Login

```
aws sso login --profile dev-admin
```

Ensures valid temporary credentials.

---

## Step 2 — Navigate

```
cd environments/dev
```

---

## Step 3 — Initialize

```
terraform init
```

Downloads provider plugins.

---

## Step 4 — Apply

```
terraform apply
```

Creates:

* S3 state bucket
* DynamoDB lock table

---

## Step 5 — Enable Remote Backend

Uncomment backend.tf.

Then run:

```
terraform init -reconfigure
```

Terraform migrates local state to S3.

From this point forward:

State is remote.

Repeat for staging and prod.

---

# 8. What Happens Internally

terraform init:

* Downloads provider
* Initializes working directory

terraform plan:

* Reads state
* Compares desired configuration
* Shows execution plan

terraform apply:

* Calls AWS APIs
* Creates resources
* Updates state

---

# 9. Final Result

You now have:

* Dev remote state bucket
* Staging remote state bucket
* Prod remote state bucket
* Locking enabled
* Encryption enabled
* Versioning enabled
* Environment isolation enforced

This repository becomes the root of trust for all infrastructure.

All future Terraform projects will reference these remote state backends.

---

# 10. Detailed AWS Login Setup (IAM Identity Center / SSO)

This section explains exactly how to configure and authenticate using AWS CLI with IAM Identity Center (Single Sign-On) for Dev, Staging, and Prod accounts.

We do NOT use access keys.
We use temporary credentials via SSO.

---

## 10.1 Verify AWS CLI Installation

Run:

```
aws --version
```

You must see aws-cli/2.x.x

Version 2 is required for IAM Identity Center authentication.

---

## 10.2 Clean Previous AWS Configuration (Important)

This ensures no corrupted or legacy credentials exist.

Run:

```
Remove-Item -Recurse -Force $env:USERPROFILE.aws -ErrorAction SilentlyContinue
```

This removes:

* Old config files
* Cached SSO tokens
* Old access keys

---

## 10.3 Create SSO Session

We create one reusable SSO session.

Run:

```
aws configure sso-session
```

When prompted, enter:

SSO session name:
platform-session

SSO start URL:
[https://d-906619e6cc.awsapps.com/start](https://d-906619e6cc.awsapps.com/start)

SSO region:
us-east-1

SSO registration scopes:
Press Enter (use default)

You should see:
Completed configuring SSO session: platform-session

---

## 10.4 Login to the SSO Session

Run:

```
aws sso login --sso-session platform-session
```

Your browser will open.

Authenticate and click Allow.

This creates a temporary authentication token.

---

# 10.5 Configure DEV Profile

Run:

```
aws configure sso --profile dev-admin
```

When prompted:

SSO session name:
platform-session

Select the Dev AWS account (data-platform-dev).

Select role:
AdministratorAccess

CLI default region:
eu-central-1

CLI default output format:
json

This creates the local CLI profile named dev-admin.

---

## 10.6 Login to DEV Profile

Run:

```
aws sso login --profile dev-admin
```

Then verify:

```
aws sts get-caller-identity --profile dev-admin
```

STS means Security Token Service.

You should see:

* Account ID (Dev account)
* ARN containing AdministratorAccess

If this works, DEV login is complete.

---

# 10.7 Configure STAGING Profile

Run:

```
aws configure sso --profile staging-admin
```

When prompted:

SSO session name:
platform-session

Select staging account.

Role:
AdministratorAccess

Region:
eu-central-1

Output:
json

Login:

```
aws sso login --profile staging-admin
```

Verify:

```
aws sts get-caller-identity --profile staging-admin
```

---

# 10.8 Configure PROD Profile

Run:

```
aws configure sso --profile prod-admin
```

When prompted:

SSO session name:
platform-session

Select prod account.

Role:
AdministratorAccess

Region:
eu-central-1

Output:
json

Login:

```
aws sso login --profile prod-admin
```

Verify:

```
aws sts get-caller-identity --profile prod-admin
```

---

# 10.9 Important Notes About SSO

* SSO tokens expire (usually after 1 hour).
* Before running terraform plan or apply, always refresh login:

```
aws sso login --profile dev-admin
```

Repeat for staging or prod as needed.

Terraform does NOT automatically refresh SSO tokens.

---

# 10.10 Conceptual Understanding

Profile ≠ Account.

Profile = Local CLI configuration.
Account = AWS isolation boundary.
Role = Permission set inside account.

Example:

prod-admin profile → assumes AdministratorAccess role → inside Prod AWS account.

---

You now have:

* One SSO session
* Three isolated CLI profiles
* No static access keys
* Secure temporary authentication

This completes enterprise-grade AWS login configuration for Terraform bootstrap.







terraform-bootstrap/
│
├── .gitignore
├── README.md
├── versions.tf
│
├── modules/
│   └── state-backend/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/
    ├── dev/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── backend.tf
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




I run terraform apply inside environments/dev
        ↓
Terraform reads all .tf files in dev/
        ↓
Sees provider block → prepares AWS provider
        ↓
Sees module block → loads ../../modules/state-backend
        ↓
Reads module's main.tf
        ↓
Finds aws_s3_bucket + aws_dynamodb_table
        ↓
Creates those resources in AWS
        ↓
Stores state (local or remote depending on backend.tf)
