# ADR 0007: Migration from CloudFormation to Terraform & HCP Terraform

## Status
Accepted

## Context
Our serverless application infrastructure was previously provisioned using disparate AWS CloudFormation templates:
- `infra/auth.yaml`: Cognito User Pool, Client, Hosted Domain, and Google OAuth Identity Provider.
- `infra/reports.yaml`: EventBridge Scheduler, SQS Queues (Main & DLQ), VPC S3 Endpoint, Builder/Mailer Lambdas, and S3 Reports Bucket.
- `infra/ai.yaml`: Bedrock Claude Agenda Parser Lambda, IAM Role, and Public Lambda Function URL.

While CloudFormation provided basic deployment capabilities via the AWS CLI and custom shell scripts (`infra/deploy-*.sh`), several operational challenges emerged:
1. **Multi-Stack Coordination**: Inter-stack references relied on custom CloudFormation outputs, bash scripts, and fragile SSM parameters.
2. **State Management & Visibility**: CloudFormation lacked clear, rapid local dry-run capabilities (Change Sets are heavyweight, slow to create, and difficult to inspect programmatically).
3. **Collaboration & State Locking**: Local deployments had no distributed state locking mechanism, risking race conditions and configuration drift during team-wide updates.
4. **Data Preservation Constraint**: Critical stateful resources—specifically the Cognito User Pool (`eu-north-1_wqlYhhhhK`) containing registered user accounts and the S3 Reports Bucket (`new-project-reports-522400670358`) storing generated CSV files—must **never** be deleted or recreated during infrastructure changes.

## Decision

We have decided to migrate our entire infrastructure to **Terraform (>= 1.10)** managed remotely via **HCP Terraform (formerly Terraform Cloud)** under organization `ooad-andriidv` and workspace `new-project-dev`.

```
+-------------------------------------------------------------+
|                     HCP Terraform                           |
|       Organization: ooad-andriidv | Workspace: new-project-dev|
|       - Remote State Storage                                |
|       - Distributed State Locking                           |
|       - Plan & Apply Governance                             |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|                     Terraform Module (infra/)               |
|  - versions.tf      : AWS provider ~> 5.0, HCP cloud block   |
|  - variables.tf     : Typed & sensitive variables           |
|  - auth.tf          : Cognito, Google IdP, Pre-SignUp trigger|
|  - reports.tf       : SQS, S3, EventBridge, Lambda pipeline  |
|  - ai.tf            : Bedrock Parser Lambda + Function URL  |
|  - outputs.tf       : Machine-readable outputs for app/make |
|  - imports.tf       : Declarative Terraform 1.5+ import {}  |
+-------------------------------------------------------------+
                               |
             +-----------------+-----------------+
             |                                   |
             v                                   v
+-----------------------------+     +-----------------------------+
|    Imported Data Resources  |     |   Stateless Infrastructure  |
|  - Cognito User Pool (Retain)|     |  - Lambdas, Roles, Policies |
|  - S3 Reports Bucket (Retain)|     |  - SQS Queues, EventBridge  |
+-----------------------------+     +-----------------------------+
```

### 1. Unified Modular Configuration in `infra/`
All infrastructure definitions are consolidated into declarative `.tf` configurations in `infra/`:
- **`versions.tf`**: Configures the HCP Terraform `cloud` block and pins the AWS provider (`~> 5.0`) with global `PROJECT_NAME` and `ManagedBy = "terraform"` tags.
- **`auth.tf`**: Translates `auth.yaml`, including pre-signup auto-confirmation Lambda, password policies, Google IdP integration, and client callbacks.
- **`reports.tf`**: Translates `reports.yaml`, setting up SQS redrive policies, S3 lifecycle expiration (90 days), EventBridge cron schedule, and S3 event notifications.
- **`ai.tf`**: Translates `ai.yaml`, configuring the unauthenticated Function URL with native CORS and IAM permissions for Bedrock Claude inference.
- **`outputs.tf`**: Exposes all required identifiers (`user_pool_id`, `client_id`, `reports_bucket`, `agenda_parser_url`) cleanly formatted for retrieval via `terraform output -raw <name>`.

### 2. Zero-Downtime, Zero-Data-Loss Migration via Declarative `import` Blocks
To guarantee that existing data-bearing resources are never dropped:
1. **CloudFormation Safeguard**: Prior to stack retirement, all resources in `infra/auth.yaml`, `infra/reports.yaml`, and `infra/ai.yaml` are updated with:
   ```yaml
   DeletionPolicy: Retain
   UpdateReplacePolicy: Retain
   ```
   This ensures that deleting the CloudFormation stacks detaches CloudFormation control without deleting underlying AWS resources.
2. **Terraform 1.5+ Declarative Imports**:
   `infra/imports.tf` declares explicit `import { to = ... id = ... }` blocks matching every existing AWS resource by its physical ID/ARN.
3. **Destruction Prevention**:
   Both `aws_cognito_user_pool.main` and `aws_s3_bucket.reports` include `lifecycle { prevent_destroy = true }`.

### 3. Makefile & Tooling Modernization
- Replaced CloudFormation deployment scripts with `make infra-plan` (`terraform plan`).
- Updated `report-now` and developer workflows to fetch runtime endpoints dynamically via:
  ```bash
  terraform output -raw <output_name>
  ```
- Retained compatibility with existing backend/frontend environments.

## Consequences

### Positive
- **Predictable Dry-Runs**: `terraform plan` provides clear, exact diffs showing proposed additions, modifications, or destructions before execution.
- **Collaborative Remote State**: HCP Terraform manages state encryption, historical versions, and concurrent run locking automatically.
- **Direct Resource Interoperability**: Eliminates fragile cross-stack CloudFormation exports; Terraform resources reference attributes natively (e.g., `aws_s3_bucket.reports.arn`).
- **Data Safety**: User accounts and report archives remain intact throughout the entire migration.

### Considerations & Trade-offs
- Requires HCP Terraform authentication token (`credentials.tfrc.json`) in deployment environments.
- CloudFormation stacks must be cleanly deleted with retention policies verified before full state ownership is managed exclusively by Terraform.
