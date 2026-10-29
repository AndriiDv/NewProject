#!/usr/bin/env bash
# Deletes the Agenda Parser AI stack. Run via `make destroy-ai`.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  AI_STACK="$PROJECT_NAME-ai"

  echo "==> Deleting '$PROJECT_NAME' AI stack from $AWS_REGION"
  aws cloudformation delete-stack --stack-name "$AI_STACK" --region "$AWS_REGION"
  aws cloudformation wait stack-delete-complete --stack-name "$AI_STACK" --region "$AWS_REGION"
  echo "==> Deleted $AI_STACK"
}

main "$@"
