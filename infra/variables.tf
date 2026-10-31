variable "project_name" {
  description = "Project name prefix used for all resources"
  type        = string
  default     = "new-project"
}

variable "region" {
  description = "Target AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "cognito_domain_prefix" {
  description = "Prefix for Cognito hosted domain"
  type        = string
  default     = "andrii-dv"
}

variable "app_urls" {
  description = "Frontend origins for OAuth redirects"
  type        = list(string)
  default     = ["http://localhost:5173", "http://localhost:3000"]
}

variable "google_client_id" {
  description = "Google OAuth client id"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "image_uri" {
  description = "ECR image URI for backend container (report builder & agenda parser)"
  type        = string
  default     = "522400670358.dkr.ecr.eu-north-1.amazonaws.com/new-project-backend:89cc379a544c41ea41e06764516a7ef64082875b"
}

variable "database_endpoint" {
  description = "Aurora PostgreSQL database cluster endpoint"
  type        = string
  default     = "new-project-db.cluster-cxuqe02cwqxo.eu-north-1.rds.amazonaws.com"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "meetings"
}

variable "db_password" {
  description = "Database password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID for S3 Gateway endpoint"
  type        = string
  default     = "vpc-05e5cb6f6f94345d7"
}

variable "route_table_ids" {
  description = "Route table IDs for S3 Gateway endpoint"
  type        = list(string)
  default     = ["rtb-085fb0bfb2bc0c18a"]
}

variable "sender_email" {
  description = "Sender email address for reports via SES"
  type        = string
  default     = "andriy.dvib@gmail.com"
}

variable "recipient_email" {
  description = "Recipient email address for reports via SES"
  type        = string
  default     = "andriy.dvib@gmail.com"
}

variable "bedrock_region" {
  description = "AWS Region where Bedrock Claude models are hosted"
  type        = string
  default     = "us-east-1"
}

variable "parser_model" {
  description = "Bedrock Claude Inference Profile or Model ID"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
