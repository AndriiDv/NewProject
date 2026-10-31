# ------------------------------------------------------------- Cognito Auth Outputs
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "Cognito User Pool App Client ID"
  value       = aws_cognito_user_pool_client.client.id
}

output "domain" {
  description = "Cognito hosted domain for OAuth redirects"
  value       = "${aws_cognito_user_pool_domain.domain.domain}.auth.${var.region}.amazoncognito.com"
}

output "issuer" {
  description = "Cognito Token Issuer URL"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "google_enabled" {
  description = "Whether Google OAuth identity provider is enabled"
  value       = var.google_client_id != ""
}

# ------------------------------------------------------------- Reports Pipeline Outputs
output "reports_bucket" {
  description = "Name of the S3 Reports Bucket"
  value       = aws_s3_bucket.reports.id
}

output "reports_bucket_arn" {
  description = "ARN of the S3 Reports Bucket"
  value       = aws_s3_bucket.reports.arn
}

output "report_requests_queue_url" {
  description = "URL of the SQS Report Requests Queue"
  value       = aws_sqs_queue.report_requests.id
}

output "report_requests_queue_arn" {
  description = "ARN of the SQS Report Requests Queue"
  value       = aws_sqs_queue.report_requests.arn
}

output "report_requests_dlq_url" {
  description = "URL of the SQS Report Requests Dead-Letter Queue"
  value       = aws_sqs_queue.report_requests_dlq.id
}

output "report_builder_function_arn" {
  description = "ARN of the Report Builder Lambda Function"
  value       = aws_lambda_function.report_builder.arn
}

output "report_mailer_function_arn" {
  description = "ARN of the Report Mailer Lambda Function"
  value       = aws_lambda_function.report_mailer.arn
}

# ------------------------------------------------------------- AI Agenda Parser Outputs
output "agenda_parser_url" {
  description = "Public AWS Lambda Function URL for agenda parser"
  value       = aws_lambda_function_url.agenda_parser.function_url
}

output "agenda_parser_function_name" {
  description = "Name of the Agenda Parser Lambda Function"
  value       = aws_lambda_function.agenda_parser.function_name
}

output "agenda_parser_function_arn" {
  description = "ARN of the Agenda Parser Lambda Function"
  value       = aws_lambda_function.agenda_parser.arn
}
