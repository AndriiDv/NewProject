import asyncio
import json
import logging
import os
import sys
from typing import Any

import boto3

from app.reports.weekly import build_weekly_report, get_previous_iso_week


class ExtraFormatter(logging.Formatter):
    EXCLUDE = {
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
        "taskName",
        "extra_fields",
        "asctime",
    }

    def format(self, record: logging.LogRecord) -> str:
        base = super().format(record)
        extras = {k: v for k, v in record.__dict__.items() if k not in self.EXCLUDE}
        if extras:
            return f"{base} " + " ".join(f"{k}={v}" for k, v in extras.items())
        return base


logger = logging.getLogger("report-builder")
logger.setLevel(logging.INFO)
logger.propagate = False
_log_handler = logging.StreamHandler(sys.stdout)
_log_handler.setFormatter(ExtraFormatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))
logger.addHandler(_log_handler)


def detect_trigger(event: dict[str, Any]) -> str:
    """Determine event trigger source (schedule, manual, sqs, or direct)."""
    if "Records" in event and event["Records"]:
        rec = event["Records"][0]
        body_raw = rec.get("body", "")
        if isinstance(body_raw, str) and body_raw.strip().startswith("{"):
            try:
                body = json.loads(body_raw)
                if isinstance(body, dict) and body.get("source"):
                    return str(body["source"])
            except Exception:
                pass
        return "sqs"

    if event.get("source"):
        return str(event["source"])

    return "direct"


def extract_week(event: dict[str, Any]) -> str:
    """Extract week from event or fall back to previous ISO week if null/omitted."""
    raw_week = None

    if "Records" in event and event["Records"]:
        rec = event["Records"][0]
        body_raw = rec.get("body", "")
        if isinstance(body_raw, str) and body_raw.strip().startswith("{"):
            try:
                body = json.loads(body_raw)
                if isinstance(body, dict):
                    raw_week = body.get("week")
            except Exception:
                pass
        elif isinstance(body_raw, dict):
            raw_week = body_raw.get("week")
    else:
        raw_week = event.get("week")

    if not raw_week or str(raw_week).strip().lower() in ("", "none", "null"):
        return get_previous_iso_week()

    return str(raw_week).strip()


def handler(event: dict[str, Any], context: Any = None) -> dict[str, Any]:
    """Lambda handler for report builder.

    Runs inside VPC, queries Aurora DB, generates CSV, and uploads to S3.
    """
    trigger = detect_trigger(event)
    week = extract_week(event)

    # Required structured log
    logger.info("report-builder triggered", extra={"trigger": trigger, "week": week})

    # Generate CSV
    csv_bytes = asyncio.run(build_weekly_report(week))

    # S3 target details
    bucket = os.environ.get("REPORTS_BUCKET")
    if not bucket:
        project = os.environ.get("PROJECT_NAME", "new-project")
        account = boto3.client("sts").get_caller_identity()["Account"]
        bucket = f"{project}-reports-{account}"

    key = f"reports/{week}.csv"

    # Idempotent upload: overwrites existing key for this week
    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=csv_bytes,
        ContentType="text/csv",
    )

    logger.info("Uploaded report to s3://%s/%s (%d bytes)", bucket, key, len(csv_bytes))

    return {
        "statusCode": 200,
        "week": week,
        "bucket": bucket,
        "key": key,
        "size": len(csv_bytes),
    }


if __name__ == "__main__":
    import sys

    arg_week = sys.argv[1] if len(sys.argv) > 1 else None
    res = handler({"source": "manual", "week": arg_week})
    print("Execution complete:", res)
