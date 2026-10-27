import email.message
import logging
import os
import urllib.parse
from typing import Any

import boto3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s %(extra_fields)s",
)


class ExtraFieldsFilter(logging.Filter):
    def filter(self, record):
        extras = {
            k: v
            for k, v in record.__dict__.items()
            if k
            not in {
                "name",
                "msg",
                "args",
                "levelname",
                "levelno",
                "pathname",
                "filename",
                "module",
                "exc_info",
                "exc_text",
                "stack_info",
                "lineno",
                "funcName",
                "created",
                "msecs",
                "relativeCreated",
                "thread",
                "threadName",
                "processName",
                "process",
                "message",
                "extra_fields",
            }
        }
        record.extra_fields = " ".join(f"{k}={v}" for k, v in extras.items()) if extras else ""
        return True


logger = logging.getLogger("report-mailer")
logger.addFilter(ExtraFieldsFilter())


def handler(event: dict[str, Any], context: Any = None) -> dict[str, Any]:
    """Lambda handler for report mailer.

    Triggered by S3 s3:ObjectCreated:* notification.
    Downloads the CSV report and sends it as an attachment via Amazon SESv2.
    """
    records = event.get("Records", [])
    if not records:
        logger.warning("No S3 records found in event: %s", event)
        return {"statusCode": 400, "message": "No records in event"}

    record = records[0]
    s3_data = record.get("s3", {})
    bucket = s3_data.get("bucket", {}).get("name")
    raw_key = s3_data.get("object", {}).get("key", "")
    key = urllib.parse.unquote_plus(raw_key)

    # Required structured log
    logger.info("report-mailer triggered", extra={"trigger": "s3", "bucket": bucket, "key": key})

    if not bucket or not key:
        raise ValueError(f"Missing bucket or key in S3 event: bucket={bucket}, key={key}")

    # Download CSV from S3
    s3 = boto3.client("s3")
    resp = s3.get_object(Bucket=bucket, Key=key)
    csv_bytes = resp["Body"].read()

    # Build MIME email message
    sender = os.environ.get("SENDER_EMAIL", "andriy.dvib@gmail.com")
    recipient = os.environ.get("RECIPIENT_EMAIL", "andriy.dvib@gmail.com")

    filename = os.path.basename(key)
    week_name = filename.replace(".csv", "")

    msg = email.message.EmailMessage()
    msg["Subject"] = f"Weekly Meetings Report: {week_name}"
    msg["From"] = sender
    msg["To"] = recipient

    body_text = f"""Hello,

Please find attached the weekly meetings report for {week_name}.

S3 Origin: s3://{bucket}/{key}
File Size: {len(csv_bytes)} bytes

Best regards,
Meetings Reporting Pipeline
"""
    msg.set_content(body_text)

    msg.add_attachment(
        csv_bytes,
        maintype="text",
        subtype="csv",
        filename=filename,
    )

    # Send via Amazon SESv2
    region = os.environ.get("AWS_REGION", "eu-north-1")
    ses = boto3.client("sesv2", region_name=region)
    ses_resp = ses.send_email(
        FromEmailAddress=sender,
        Destination={"ToAddresses": [recipient]},
        Content={"Raw": {"Data": msg.as_bytes()}},
    )

    message_id = ses_resp.get("MessageId")
    logger.info("Sent report email to %s (MessageId: %s)", recipient, message_id)

    return {
        "statusCode": 200,
        "messageId": message_id,
        "recipient": recipient,
        "bucket": bucket,
        "key": key,
    }
