# ---------------------------------------------------------------- SQS Queue & DLQ
resource "aws_sqs_queue" "report_requests_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "report_requests" {
  name                       = "${var.project_name}-report-requests"
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.report_requests_dlq.arn
    maxReceiveCount     = 3
  })
}

# ----------------------------------------------------------- EventBridge Schedule
resource "aws_iam_role" "scheduler_role" {
  name = "${var.project_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role_policy" "scheduler_sqs_send" {
  name = "SqsSendPolicy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.report_requests.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "weekly_report" {
  name                         = "${var.project_name}-weekly-report-schedule"
  description                  = "Triggers weekly meeting report generation every Monday at 07:00 Europe/Kyiv"
  schedule_expression          = "cron(0 7 ? * MON *)"
  schedule_expression_timezone = "Europe/Kyiv"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.report_requests.arn
    role_arn = aws_iam_role.scheduler_role.arn
    input    = jsonencode({ week = null, source = "schedule" })
  }
}

# -------------------------------------------------------- S3 Gateway VPC Endpoint
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
}

# --------------------------------------------------------- Report Builder Function
resource "aws_iam_role" "report_builder_role" {
  name = "${var.project_name}-report-builder-role"

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
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role_policy" "report_builder_s3" {
  name = "S3PutReportPolicy"
  role = aws_iam_role.report_builder_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.reports.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "report_builder_sqs" {
  name = "SqsConsumePolicy"
  role = aws_iam_role.report_builder_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.report_requests.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "report_builder_rds" {
  name = "RdsDbConnectPolicy"
  role = aws_iam_role.report_builder_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "rds-db:connect"
        Resource = "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:*/*"
      }
    ]
  })
}

resource "aws_lambda_function" "report_builder" {
  function_name = "${var.project_name}-report-builder"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.report_builder_role.arn
  timeout       = 60
  memory_size   = 512

  image_config {
    command = ["app.reports.builder_handler.handler"]
  }

  environment {
    variables = {
      DATABASE_URL   = "postgresql+asyncpg://${var.db_user}@${var.database_endpoint}:5432/postgres"
      DB_PASSWORD    = var.db_password
      REPORTS_BUCKET = aws_s3_bucket.reports.id
      PROJECT_NAME   = var.project_name
      REPORT_BUILDER = "true"
      DISABLE_LWA    = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      image_uri,
      environment[0].variables["DB_PASSWORD"]
    ]
  }
}

resource "aws_lambda_event_source_mapping" "report_requests" {
  event_source_arn = aws_sqs_queue.report_requests.arn
  function_name    = aws_lambda_function.report_builder.arn
  batch_size       = 1
  enabled          = true
}

# ---------------------------------------------------------- Report Mailer Function
resource "aws_iam_role" "report_mailer_role" {
  name = "${var.project_name}-report-mailer-role"

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

resource "aws_iam_role_policy" "report_mailer_s3" {
  name = "S3GetReportPolicy"
  role = aws_iam_role.report_mailer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.reports.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "report_mailer_ses" {
  name = "SesSendReportPolicy"
  role = aws_iam_role.report_mailer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "report_mailer_zip" {
  type        = "zip"
  output_path = "${path.module}/report_mailer.zip"
  source {
    content  = <<-EOT
      import email.message
      import logging
      import os
      import sys
      import urllib.parse
      import boto3

      class ExtraFormatter(logging.Formatter):
          EXCLUDE = {
              "name", "msg", "args", "levelname", "levelno", "pathname", "filename", "module",
              "exc_info", "exc_text", "stack_info", "lineno", "funcName", "created", "msecs",
              "relativeCreated", "thread", "threadName", "processName", "process", "message",
              "taskName", "extra_fields", "asctime"
          }
          def format(self, record):
              base = super().format(record)
              extras = {k: v for k, v in record.__dict__.items() if k not in self.EXCLUDE}
              if extras:
                  return f"{base} " + " ".join(f"{k}={v}" for k, v in extras.items())
              return base

      logger = logging.getLogger("report-mailer")
      logger.setLevel(logging.INFO)
      logger.propagate = False
      _log_handler = logging.StreamHandler(sys.stdout)
      _log_handler.setFormatter(ExtraFormatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))
      logger.addHandler(_log_handler)

      def handler(event, context):
          records = event.get("Records", [])
          if not records:
              logger.warning("No records found in S3 event: %s", event)
              return {"statusCode": 400, "message": "No records in event"}

          record = records[0]
          s3_data = record.get("s3", {})
          bucket = s3_data.get("bucket", {}).get("name")
          raw_key = s3_data.get("object", {}).get("key", "")
          key = urllib.parse.unquote_plus(raw_key)

          logger.info("report-mailer triggered", extra={"trigger": "s3", "bucket": bucket, "key": key})

          if not bucket or not key:
              raise ValueError(f"Missing bucket or key: bucket={bucket}, key={key}")

          s3 = boto3.client("s3")
          resp = s3.get_object(Bucket=bucket, Key=key)
          csv_bytes = resp["Body"].read()

          sender = os.environ.get("SENDER_EMAIL", "andriy.dvib@gmail.com")
          recipient = os.environ.get("RECIPIENT_EMAIL", "andriy.dvib@gmail.com")

          filename = os.path.basename(key)
          week_name = filename.replace(".csv", "")

          msg = email.message.EmailMessage()
          msg["Subject"] = f"Weekly Meetings Report: {week_name}"
          msg["From"] = sender
          msg["To"] = recipient

          body_text = f"Hello,\n\nPlease find attached the weekly meetings report for {week_name}.\n\nOrigin: s3://{bucket}/{key}\n\nBest regards,\nMeetings Pipeline"
          msg.set_content(body_text)

          msg.add_attachment(csv_bytes, maintype="text", subtype="csv", filename=filename)

          region = os.environ.get("AWS_REGION", "eu-north-1")
          ses = boto3.client("sesv2", region_name=region)
          ses_resp = ses.send_email(
              FromEmailAddress=sender,
              Destination={"ToAddresses": [recipient]},
              Content={"Raw": {"Data": msg.as_bytes()}}
          )

          message_id = ses_resp.get("MessageId")
          logger.info("Sent report email to %s (MessageId: %s)", recipient, message_id)

          return {"statusCode": 200, "messageId": message_id, "recipient": recipient, "bucket": bucket, "key": key}
    EOT
    filename = "index.py"
  }
}

resource "aws_lambda_function" "report_mailer" {
  function_name    = "${var.project_name}-report-mailer"
  runtime          = "python3.12"
  handler          = "index.handler"
  timeout          = 60
  memory_size      = 256
  role             = aws_iam_role.report_mailer_role.arn
  filename         = data.archive_file.report_mailer_zip.output_path
  source_code_hash = data.archive_file.report_mailer_zip.output_base64sha256

  environment {
    variables = {
      SENDER_EMAIL    = var.sender_email
      RECIPIENT_EMAIL = var.recipient_email
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_permission" "report_mailer_s3" {
  statement_id   = "new-project-reports-ReportMailerPermission-2pYfxxGEL28L"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.report_mailer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = data.aws_caller_identity.current.account_id
}

# --------------------------------------------------------------- S3 Reports Bucket
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "ExpireAfter90Days"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.report_mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.report_mailer_s3]
}
