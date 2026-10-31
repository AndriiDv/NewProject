# Lab 7 Submission: CloudFormation to Terraform Migration

## 1. Direct Commit Link

- **Commit URL**: [https://github.com/AndriiDv/NewProject/commit/99136db91523afef628271a734f01718ebcd9659](https://github.com/AndriiDv/NewProject/commit/99136db91523afef628271a734f01718ebcd9659)
- **Base Migration Commit**: [https://github.com/AndriiDv/NewProject/commit/1f410fe1d754b59e590ff7eec2a7e6d56e05bd69](https://github.com/AndriiDv/NewProject/commit/1f410fe1d754b59e590ff7eec2a7e6d56e05bd69)

### Implemented Components

- **`infra/versions.tf`**: HCP Terraform cloud backend (`organization = "ooad-andriidv"`, `workspace = "new-project-dev"`), AWS provider `~> 5.0` with unified tagging (`PROJECT_NAME`), and `random` provider.
- **`infra/variables.tf` & `infra/terraform.tfvars`**: Strongly-typed variables with `sensitive = true` guards for database passwords and Google OAuth client secrets, and environment defaults targeting `eu-north-1`.
- **`infra/auth.tf`**: Declarative definitions for Cognito User Pool, User Pool Domain (`andrii-dv`), Google Identity Provider, Web Client (configured for CloudFront and localhost OAuth redirects), and pre-sign-up trigger Lambda with IAM role and execution permissions.
- **`infra/reports.tf`**: S3 Reports Bucket (lifecycle transition rules and public access block), SQS queue and Dead Letter Queue with redrive policy, EventBridge Scheduler schedule (weekly report generation), VPC S3 Gateway endpoint, Report Builder container Lambda, Report Mailer Lambda with SES send permissions, and S3 event notifications.
- **`infra/ai.tf`**: Agenda Parser container Lambda with Bedrock InvokeModel IAM role, public Lambda Function URL with CORS, and invocation permissions.
- **`infra/outputs.tf`**: 15 infrastructure outputs exposing Cognito IDs, bucket names, queue URLs, and Lambda Function URLs.
- **`infra/imports.tf`**: 33 declarative Terraform 1.5+ `import` blocks mapping live AWS resources to Terraform configuration addresses without downtime or resource destruction.
- **`Makefile`**: New targets `infra-init`, `infra-fmt`, `infra-validate`, `infra-plan`, `infra-output`; deprecated CloudFormation deployment targets in favor of Terraform workflows.
- **`infra/common.sh` & `infra/report-now.sh`**: Integrated `tf_output` helper resolving stack resources dynamically via HCP Terraform state.
- **`docs/adr/0007-terraform.md`**: Architecture Decision Record detailing the migration from AWS CloudFormation to HashiCorp Terraform and HCP Terraform, covering state management, import strategies, and operational tradeoffs.
- **`README.md`**: Updated infrastructure documentation with HCP Terraform prerequisites, workspace setup, and CLI usage.

---

## 2. HCP Terraform Apply Screenshot Note

> **Note**: Screenshot of the HCP Terraform workspace `new-project-dev` (`ws-6YnLsGGZXnFEFJsE`) in organization `ooad-andriidv` showing **Apply finished** for VCS run `run-2Q3nG9EtYtoHcv71` (triggered automatically via GitHub push to `main`):
>
> - **Workspace**: `ooad-andriidv / new-project-dev`
> - **Run ID**: `run-2Q3nG9EtYtoHcv71`
> - **Apply ID**: `apply-9S45LUxFaVtqm2ii`
> - **Status**: `Apply finished` (Applied)
> - **Summary**: `Resources: 33 imported, 0 added, 0 changed, 0 destroyed.`
> - **Run URL**: [https://app.terraform.io/app/ooad-andriidv/workspaces/new-project-dev/runs/run-2Q3nG9EtYtoHcv71](https://app.terraform.io/app/ooad-andriidv/workspaces/new-project-dev/runs/run-2Q3nG9EtYtoHcv71)

*(Please find the attached screenshot file `hcp-terraform-apply-finished.png` in the submission package)*

---

## 3. Final Verification Plan (`terraform plan`)

Verbatim raw output from executing `terraform plan` in the `infra/` directory, streamed from HCP Terraform and confirming that real infrastructure matches configuration with 0 pending changes:

```text
Running plan in HCP Terraform. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the plan running remotely.

Preparing the remote plan...

The remote workspace is configured to work with configuration at
infra relative to the target repository.

Terraform will upload the contents of the following directory,
excluding files or directories as defined by a .terraformignore file
at C:\Users\andri\Downloads\NewProject/.terraformignore (if it is present),
in order to capture the filesystem context the remote workspace expects:
    C:\Users\andri\Downloads\NewProject

To view this run in a browser, visit:
https://app.terraform.io/app/ooad-andriidv/new-project-dev/runs/run-5EwLhMEz7d1g3U3F

Waiting for the plan to start...

Terraform v1.17.1
on linux_amd64

Initializing plugins and modules...
data.archive_file.report_mailer_zip: Refreshing...
data.archive_file.pre_sign_up_zip: Refreshing...
data.archive_file.pre_sign_up_zip: Refresh complete after 0s [id=b6e01ba00708a54318a145a202d115f5a0707649]
data.archive_file.report_mailer_zip: Refresh complete after 0s [id=c2c7d8dd6badf18dc2b7ebfdee073e43f10278b0]
data.aws_region.current: Refreshing...
aws_iam_role.scheduler_role: Refreshing state... [id=new-project-reports-SchedulerRole-OUAuN6cSHPgW]
aws_iam_role.pre_sign_up_role: Refreshing state... [id=new-project-auth-PreSignUpFunctionRole-fxhQMq70zH9s]
aws_sqs_queue.report_requests_dlq: Refreshing state... [id=https://sqs.eu-north-1.amazonaws.com/522400670358/new-project-report-requests-dlq]
aws_iam_role.report_builder_role: Refreshing state... [id=new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI]
aws_iam_role.report_mailer_role: Refreshing state... [id=new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p]
aws_vpc_endpoint.s3_gateway: Refreshing state... [id=vpce-039d70e39e155e523]
aws_iam_role.agenda_parser_role: Refreshing state... [id=new-project-agenda-parser-role]
data.aws_region.current: Refresh complete after 0s [id=eu-north-1]
data.aws_caller_identity.current: Refreshing...
data.aws_caller_identity.current: Refresh complete after 0s [id=522400670358]
aws_s3_bucket.reports: Refreshing state... [id=new-project-reports-522400670358]
aws_iam_role_policy.agenda_parser_bedrock: Refreshing state... [id=new-project-agenda-parser-role:BedrockAccess]
aws_lambda_function.pre_sign_up: Refreshing state... [id=new-project-cognito-pre-signup]
aws_iam_role_policy.report_builder_rds: Refreshing state... [id=new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:RdsDbConnectPolicy]
aws_iam_role_policy.report_mailer_ses: Refreshing state... [id=new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p:SesSendReportPolicy]
aws_lambda_function.report_mailer: Refreshing state... [id=new-project-report-mailer]
aws_sqs_queue.report_requests: Refreshing state... [id=https://sqs.eu-north-1.amazonaws.com/522400670358/new-project-report-requests]
aws_iam_role_policy.scheduler_sqs_send: Refreshing state... [id=new-project-reports-SchedulerRole-OUAuN6cSHPgW:SqsSendPolicy]
aws_scheduler_schedule.weekly_report: Refreshing state... [id=default/new-project-weekly-report-schedule]
aws_iam_role_policy.report_builder_sqs: Refreshing state... [id=new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:SqsConsumePolicy]
aws_lambda_permission.pre_sign_up: Refreshing state... [id=new-project-auth-PreSignUpPermission-00EInKnlDUbl]
aws_cognito_user_pool.main: Refreshing state... [id=eu-north-1_wqlYhhhhK]
aws_cognito_identity_provider.google[0]: Refreshing state... [id=eu-north-1_wqlYhhhhK:Google]
aws_cognito_user_pool_domain.domain: Refreshing state... [id=andrii-dv]
aws_cognito_user_pool_client.client: Refreshing state... [id=41nlfa3aa6hmiopbtcef288vto]
aws_lambda_function.agenda_parser: Refreshing state... [id=new-project-agenda-parser]
aws_s3_bucket_public_access_block.reports: Refreshing state... [id=new-project-reports-522400670358]
aws_iam_role_policy.report_mailer_s3: Refreshing state... [id=new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p:S3GetReportPolicy]
aws_iam_role_policy.report_builder_s3: Refreshing state... [id=new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:S3PutReportPolicy]
aws_lambda_permission.report_mailer_s3: Refreshing state... [id=new-project-reports-ReportMailerPermission-2pYfxxGEL28L]
aws_s3_bucket_lifecycle_configuration.reports: Refreshing state... [id=new-project-reports-522400670358]
aws_lambda_function.report_builder: Refreshing state... [id=new-project-report-builder]
aws_s3_bucket_notification.reports: Refreshing state... [id=new-project-reports-522400670358]
aws_lambda_permission.agenda_parser_url: Refreshing state... [id=new-project-ai-AgendaParserUrlPermission-3MK0gEjKrHG8]
aws_lambda_function_url.agenda_parser: Refreshing state... [id=new-project-agenda-parser]
aws_lambda_event_source_mapping.report_requests: Refreshing state... [id=f6055af0-b9f5-4854-a4e8-8998470da053]
aws_lambda_function.agenda_parser: Drift detected (update)
aws_lambda_function.report_builder: Drift detected (update)
╷
│ Warning: Argument is deprecated
│ 
│   with aws_iam_role.agenda_parser_role,
│   on ai.tf line 16, in resource "aws_iam_role" "agenda_parser_role":
│   16:   managed_policy_arns = [
│   17:     "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
│   18:   ]
│ 
│ managed_policy_arns is deprecated. Use the aws_iam_role_policy_attachment
│ resource instead. If Terraform should exclusively manage all managed policy
│ attachments (the current behavior of this argument), use the
│ aws_iam_role_policy_attachments_exclusive resource as well.
╵
╷
│ Warning: Argument is deprecated
│ 
│   with aws_iam_role.pre_sign_up_role,
│   on auth.tf line 33, in resource "aws_iam_role" "pre_sign_up_role":
│   33:   managed_policy_arns = [
│   34:     "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
│   35:   ]
│ 
│ managed_policy_arns is deprecated. Use the aws_iam_role_policy_attachment
│ resource instead. If Terraform should exclusively manage all managed policy
│ attachments (the current behavior of this argument), use the
│ aws_iam_role_policy_attachments_exclusive resource as well.
╵
╷
│ Warning: Argument is deprecated
│ 
│   with aws_iam_role.report_mailer_role,
│   on reports.tf line 221, in resource "aws_iam_role" "report_mailer_role":
│  221:   managed_policy_arns = [
│  222:     "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
│  223:   ]
│ 
│ managed_policy_arns is deprecated. Use the aws_iam_role_policy_attachment
│ resource instead. If Terraform should exclusively manage all managed policy
│ attachments (the current behavior of this argument), use the
│ aws_iam_role_policy_attachments_exclusive resource as well.
╵
╷
│ Warning: Argument is deprecated
│ 
│   with aws_iam_role.report_builder_role,
│   on reports.tf line 105, in resource "aws_iam_role" "report_builder_role":
│  105:   managed_policy_arns = [
│  106:     "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
│  107:     "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
│  108:   ]
│ 
│ managed_policy_arns is deprecated. Use the aws_iam_role_policy_attachment
│ resource instead. If Terraform should exclusively manage all managed policy
│ attachments (the current behavior of this argument), use the
│ aws_iam_role_policy_attachments_exclusive resource as well.
╵

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```
