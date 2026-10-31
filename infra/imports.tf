# ==============================================================================
# Terraform 1.5+ Import Blocks for Existing AWS CloudFormation Stacks
# ==============================================================================

# ------------------------------------------------------------- 1. Auth Stack (new-project-auth)
import {
  to = aws_cognito_user_pool.main
  id = "eu-north-1_wqlYhhhhK"
}

import {
  to = aws_cognito_user_pool_domain.domain
  id = "andrii-dv"
}

import {
  to = aws_cognito_identity_provider.google[0]
  id = "eu-north-1_wqlYhhhhK:Google"
}

import {
  to = aws_cognito_user_pool_client.client
  id = "eu-north-1_wqlYhhhhK/41nlfa3aa6hmiopbtcef288vto"
}

import {
  to = aws_iam_role.pre_sign_up_role
  id = "new-project-auth-PreSignUpFunctionRole-fxhQMq70zH9s"
}

import {
  to = aws_lambda_function.pre_sign_up
  id = "new-project-cognito-pre-signup"
}

import {
  to = aws_lambda_permission.pre_sign_up
  id = "new-project-cognito-pre-signup/new-project-auth-PreSignUpPermission-00EInKnlDUbl"
}

# ---------------------------------------------------------- 2. Reports Stack (new-project-reports)
import {
  to = aws_sqs_queue.report_requests_dlq
  id = "https://sqs.eu-north-1.amazonaws.com/522400670358/new-project-report-requests-dlq"
}

import {
  to = aws_sqs_queue.report_requests
  id = "https://sqs.eu-north-1.amazonaws.com/522400670358/new-project-report-requests"
}

import {
  to = aws_iam_role.scheduler_role
  id = "new-project-reports-SchedulerRole-OUAuN6cSHPgW"
}

import {
  to = aws_iam_role_policy.scheduler_sqs_send
  id = "new-project-reports-SchedulerRole-OUAuN6cSHPgW:SqsSendPolicy"
}

import {
  to = aws_scheduler_schedule.weekly_report
  id = "default/new-project-weekly-report-schedule"
}

import {
  to = aws_vpc_endpoint.s3_gateway
  id = "vpce-039d70e39e155e523"
}

import {
  to = aws_iam_role.report_builder_role
  id = "new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI"
}

import {
  to = aws_iam_role_policy.report_builder_s3
  id = "new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:S3PutReportPolicy"
}

import {
  to = aws_iam_role_policy.report_builder_sqs
  id = "new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:SqsConsumePolicy"
}

import {
  to = aws_iam_role_policy.report_builder_rds
  id = "new-project-reports-ReportBuilderFunctionRole-i3jOrsyJNLWI:RdsDbConnectPolicy"
}

import {
  to = aws_lambda_function.report_builder
  id = "new-project-report-builder"
}

import {
  to = aws_lambda_event_source_mapping.report_requests
  id = "f6055af0-b9f5-4854-a4e8-8998470da053"
}

import {
  to = aws_iam_role.report_mailer_role
  id = "new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p"
}

import {
  to = aws_iam_role_policy.report_mailer_s3
  id = "new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p:S3GetReportPolicy"
}

import {
  to = aws_iam_role_policy.report_mailer_ses
  id = "new-project-reports-ReportMailerFunctionRole-LBf3j6SQyO6p:SesSendReportPolicy"
}

import {
  to = aws_lambda_function.report_mailer
  id = "new-project-report-mailer"
}

import {
  to = aws_lambda_permission.report_mailer_s3
  id = "new-project-report-mailer/new-project-reports-ReportMailerPermission-2pYfxxGEL28L"
}

import {
  to = aws_s3_bucket.reports
  id = "new-project-reports-522400670358"
}

import {
  to = aws_s3_bucket_public_access_block.reports
  id = "new-project-reports-522400670358"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "new-project-reports-522400670358"
}

import {
  to = aws_s3_bucket_notification.reports
  id = "new-project-reports-522400670358"
}

# ------------------------------------------------------------- 3. AI Stack (new-project-ai)
import {
  to = aws_iam_role.agenda_parser_role
  id = "new-project-agenda-parser-role"
}

import {
  to = aws_iam_role_policy.agenda_parser_bedrock
  id = "new-project-agenda-parser-role:BedrockAccess"
}

import {
  to = aws_lambda_function.agenda_parser
  id = "new-project-agenda-parser"
}

import {
  to = aws_lambda_function_url.agenda_parser
  id = "new-project-agenda-parser"
}

import {
  to = aws_lambda_permission.agenda_parser_url
  id = "new-project-agenda-parser/new-project-ai-AgendaParserUrlPermission-3MK0gEjKrHG8"
}
