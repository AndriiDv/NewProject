#!/usr/bin/env bash
# Triggers on-demand weekly report generation via SQS.
# Usage: ./infra/report-now.sh [WEEK]
# Example: ./infra/report-now.sh 2026-W43
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  WEEK="${1:-${WEEK:-}}"
  QUEUE_NAME="$PROJECT_NAME-report-requests"

  QUEUE_URL="$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query QueueUrl --output text 2>/dev/null || echo "")"
  if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
    REPORTS_STACK="$PROJECT_NAME-reports"
    QUEUE_URL="$(output "$REPORTS_STACK" ReportRequestsQueueUrl)"
  fi

  if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
    echo "Error: SQS queue '$QUEUE_NAME' not found. Has 'make deploy-reports' been run?" >&2
    exit 1
  fi

  if [ -n "$WEEK" ] && [ "$WEEK" != "null" ]; then
    PAYLOAD=$(printf '{"week": "%s", "source": "manual"}' "$WEEK")
  else
    PAYLOAD='{"week": null, "source": "manual"}'
  fi

  echo "==> Sending report trigger message to $QUEUE_URL"
  echo "    Payload: $PAYLOAD"

  RESP="$(aws sqs send-message --queue-url "$QUEUE_URL" --message-body "$PAYLOAD" --region "$AWS_REGION" --output json)"
  MSG_ID="$(echo "$RESP" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("MessageId", ""))' 2>/dev/null || echo "$RESP")"
  echo "==> Message sent successfully! MessageId: $MSG_ID"
}

main "$@"
