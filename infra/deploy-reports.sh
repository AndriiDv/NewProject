#!/usr/bin/env bash
# Deploys the weekly reports pipeline stack (EventBridge + SQS + Builder + S3 + Mailer + SES) to AWS.
# Run via `make deploy-reports`.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  REPORTS_STACK="$PROJECT_NAME-reports"
  PASSWORD_PARAM="/$PROJECT_NAME/db-password"

  echo "==> Deploying '$PROJECT_NAME' reports pipeline to $AWS_REGION"

  # 1. Fetch DB Password
  db_password=""
  if aws ssm get-parameter --name "$PASSWORD_PARAM" --region "$AWS_REGION" >/dev/null 2>&1; then
    db_password="$(aws ssm get-parameter --name "$PASSWORD_PARAM" --with-decryption \
      --query Parameter.Value --output text --region "$AWS_REGION")"
  fi

  # 2. Fetch Image URI
  image="${IMAGE_URI:-}"
  if [ -z "$image" ] && stack_exists "$BACKEND_STACK"; then
    func_name="$(output "$BACKEND_STACK" FunctionName)"
    if [ -n "$func_name" ] && [ "$func_name" != "None" ]; then
      image="$(aws lambda get-function-configuration --function-name "$func_name" --region "$AWS_REGION" --query "Code.ImageUri" --output text 2>/dev/null || echo "")"
    fi
  fi

  # Fallback to current ECR image
  if [ -z "$image" ] || [ "$image" = "None" ]; then
    repository="$(output "$ECR_STACK" RepositoryUri)"
    tag="$(git rev-parse --short HEAD)"
    image="$repository:$tag"
  fi

  # 3. Database Endpoint
  db_endpoint="${DATABASE_ENDPOINT:-}"
  if [ -z "$db_endpoint" ]; then
    db_endpoint="$(output "$BACKEND_STACK" DatabaseEndpoint)"
  fi
  if [ -z "$db_endpoint" ] || [ "$db_endpoint" = "None" ]; then
    db_endpoint="$(aws rds describe-db-clusters --db-cluster-identifier "$PROJECT_NAME-db" \
      --query "DBClusters[0].Endpoint" --output text --region "$AWS_REGION" 2>/dev/null || echo "")"
  fi

  echo "    Image:    $image"
  echo "    Database: $db_endpoint"

  aws cloudformation deploy \
    --stack-name "$REPORTS_STACK" \
    --template-file infra/reports.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "ImageUri=$image" \
      "DatabaseEndpoint=${db_endpoint:-$PROJECT_NAME-db.cluster-cxuqe02cwqxo.eu-north-1.rds.amazonaws.com}" \
      "DBPassword=$db_password" \
      "SenderEmail=${SENDER_EMAIL:-andriy.dvib@gmail.com}" \
      "RecipientEmail=${RECIPIENT_EMAIL:-andriy.dvib@gmail.com}" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  bucket="$(output "$REPORTS_STACK" ReportsBucketName)"
  queue_url="$(output "$REPORTS_STACK" ReportRequestsQueueUrl)"
  echo
  echo "Reports pipeline deployed successfully!"
  echo "S3 Bucket:  s3://$bucket"
  echo "SQS Queue:  $queue_url"
}

main "$@"
