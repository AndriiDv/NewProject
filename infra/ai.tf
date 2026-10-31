# ------------------------------------------------------------- Agenda Parser Role
resource "aws_iam_role" "agenda_parser_role" {
  name = "${var.project_name}-agenda-parser-role"

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
}

resource "aws_iam_role_policy" "agenda_parser_bedrock" {
  name = "BedrockAccess"
  role = aws_iam_role.agenda_parser_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      }
    ]
  })
}

# --------------------------------------------------------- Agenda Parser Function
resource "aws_lambda_function" "agenda_parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Parses raw unstructured meeting text into structured JSON agenda schema via AWS Bedrock"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.agenda_parser_role.arn
  timeout       = 60
  memory_size   = 512

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  environment {
    variables = {
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.client.id
      BEDROCK_REGION       = var.bedrock_region
      PARSER_MODEL         = var.parser_model
      DISABLE_LWA          = "true"
      AGENDA_PARSER        = "true"
    }
  }

  lifecycle {
    ignore_changes = [image_uri, publish]
  }
}

# --------------------------------------------------------- Public Function URL
resource "aws_lambda_function_url" "agenda_parser" {
  function_name      = aws_lambda_function.agenda_parser.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

resource "aws_lambda_permission" "agenda_parser_url" {
  statement_id           = "new-project-ai-AgendaParserUrlPermission-3MK0gEjKrHG8"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.agenda_parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
