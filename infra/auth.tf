data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------- Pre-SignUp Trigger
data "archive_file" "pre_sign_up_zip" {
  type        = "zip"
  output_path = "${path.module}/pre_signup.zip"
  source {
    content  = <<-EOT
      def handler(event, context):
          event['response']['autoConfirmUser'] = True
          event['response']['autoVerifyEmail'] = True
          return event
    EOT
    filename = "index.py"
  }
}

resource "aws_iam_role" "pre_sign_up_role" {
  name = "${var.project_name}-cognito-pre-signup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_lambda_function" "pre_sign_up" {
  function_name    = "${var.project_name}-cognito-pre-signup"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.pre_sign_up_role.arn
  timeout          = 10
  filename         = data.archive_file.pre_sign_up_zip.output_path
  source_code_hash = data.archive_file.pre_sign_up_zip.output_base64sha256

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_permission" "pre_sign_up" {
  statement_id  = "new-project-auth-PreSignUpPermission-00EInKnlDUbl"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_sign_up.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = "arn:aws:cognito-idp:${var.region}:${data.aws_caller_identity.current.account_id}:userpool/*"
}

# -------------------------------------------------------------- Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_uppercase = false
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Meetings verification code"
    email_message        = "Your Meetings verification code is {####}"
  }

  lambda_config {
    pre_sign_up = aws_lambda_function.pre_sign_up.arn
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = false
    mutable             = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------- Hosted Auth Domain
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

# ------------------------------------------------------------ Google Identity Provider
resource "aws_cognito_identity_provider" "google" {
  count         = var.google_client_id != "" ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "sub"
  }
}

# ------------------------------------------------------------- User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  supported_identity_providers = var.google_client_id != "" ? ["COGNITO", "Google"] : ["COGNITO"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile", "aws.cognito.signin.user.admin"]

  callback_urls = [for url in var.app_urls : "${url}/login"]
  logout_urls   = [for url in var.app_urls : "${url}/login"]

  depends_on = [aws_cognito_identity_provider.google]
}
