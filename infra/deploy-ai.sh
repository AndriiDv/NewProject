#!/usr/bin/env bash
# Deploys the Agenda Parser AI stack (outside VPC, Function URL, Bedrock IAM) to AWS.
# Run via `make deploy-ai`.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  AI_STACK="$PROJECT_NAME-ai"

  echo "==> Deploying '$PROJECT_NAME' AI Agenda Parser to $AWS_REGION"

  # 1. Fetch Image URI
  image="${IMAGE_URI:-}"
  if [ -z "$image" ] && stack_exists "$BACKEND_STACK"; then
    func_name="$(output "$BACKEND_STACK" FunctionName)"
    if [ -n "$func_name" ] && [ "$func_name" != "None" ]; then
      image="$(aws lambda get-function --function-name "$func_name" --region "$AWS_REGION" --query "Code.ImageUri" --output text 2>/dev/null || echo "")"
    fi
  fi

  # Fallback to latest tag in ECR or current git HEAD
  if [ -z "$image" ] || [ "$image" = "None" ]; then
    repository="$(output "$ECR_STACK" RepositoryUri)"
    latest_tag="$(aws ecr describe-images --repository-name "$PROJECT_NAME-backend" --region "$AWS_REGION" \
      --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text 2>/dev/null || echo "")"
    if [ -n "$latest_tag" ] && [ "$latest_tag" != "None" ]; then
      image="$repository:$latest_tag"
    else
      tag="$(git rev-parse HEAD)"
      image="$repository:$tag"
    fi
  fi

  # 2. Fetch Cognito Pool and Client IDs
  user_pool_id="${COGNITO_USER_POOL_ID:-}"
  client_id="${COGNITO_CLIENT_ID:-}"
  if [ -z "$user_pool_id" ] && stack_exists "$AUTH_STACK"; then
    user_pool_id="$(output "$AUTH_STACK" UserPoolId)"
  fi
  if [ -z "$client_id" ] && stack_exists "$AUTH_STACK"; then
    client_id="$(output "$AUTH_STACK" AppClientId)"
  fi

  bedrock_region="${BEDROCK_REGION:-us-east-1}"
  parser_model="${PARSER_MODEL:-us.anthropic.claude-haiku-4-5-20251001-v1:0}"

  echo "    Image:        $image"
  echo "    User Pool:    $user_pool_id"
  echo "    Client ID:    $client_id"
  echo "    Bedrock Reg:  $bedrock_region"
  echo "    Model:        $parser_model"

  aws cloudformation deploy \
    --stack-name "$AI_STACK" \
    --template-file infra/ai.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "ImageUri=$image" \
      "CognitoUserPoolId=$user_pool_id" \
      "CognitoClientId=$client_id" \
      "BedrockRegion=$bedrock_region" \
      "ParserModel=$parser_model" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  func_url="$(output "$AI_STACK" FunctionUrl)"
  echo "==> Agenda Parser Function URL: $func_url"
}

main "$@"
