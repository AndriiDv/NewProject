#!/usr/bin/env bash
# Builds the frontend against the backend's ALB DNS URL and deploys it to
# S3 + CloudFront. Run via `make deploy-frontend` after `make deploy-backend`.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  api_base_url="$(output "$BACKEND_STACK" ApiBaseUrl || true)"
  if [ -z "$api_base_url" ] || [ "$api_base_url" = "None" ]; then
    echo "Warning: Stack $BACKEND_STACK not found or ApiBaseUrl empty; proceeding with empty VITE_API_URL"
    api_base_url=""
  fi

  echo "==> [1/6] Build the frontend (API: ${api_base_url:-default})"
  user_pool_id="$(output "$AUTH_STACK" UserPoolId 2>/dev/null || true)"
  client_id="$(output "$AUTH_STACK" UserPoolClientId 2>/dev/null || true)"
  cognito_domain="$(output "$AUTH_STACK" Domain 2>/dev/null || true)"
  google_enabled="$(output "$AUTH_STACK" GoogleEnabled 2>/dev/null || true)"

  (cd frontend && npm ci && \
    VITE_API_URL="$api_base_url" \
    COGNITO_USER_POOL_ID="${user_pool_id:-}" \
    COGNITO_CLIENT_ID="${client_id:-}" \
    COGNITO_DOMAIN="${cognito_domain:-}" \
    COGNITO_GOOGLE_ENABLED="${google_enabled:-false}" \
    npm run build)

  echo "==> [2/6] S3 bucket + CloudFront ($FRONTEND_STACK)"
  echo "    The first run creates the CloudFront distribution and takes about 3-5 minutes."
  aws cloudformation deploy \
    --stack-name "$FRONTEND_STACK" \
    --template-file infra/frontend.yaml \
    --parameter-overrides "ProjectName=$PROJECT_NAME" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset
  bucket="$(output "$FRONTEND_STACK" BucketName)"
  distribution="$(output "$FRONTEND_STACK" DistributionId)"

  if stack_exists "$BACKEND_STACK"; then
    echo "==> [3/6] Allow the frontend to call the API ($BACKEND_STACK)"
    update_backend_cors
  else
    echo "==> [3/6] Skipping backend CORS update ($BACKEND_STACK does not exist yet)"
  fi

  if stack_exists "$AUTH_STACK"; then
    echo "==> [4/6] Allow Cognito to redirect back to the frontend ($AUTH_STACK)"
    update_auth_urls
  else
    echo "==> [4/6] Skipping auth URLs update ($AUTH_STACK does not exist)"
  fi

  echo "==> [5/6] Upload to s3://$bucket"
  # Hashed assets never change, so browsers may cache them forever; everything else is revalidated.
  aws s3 sync frontend/dist/assets "s3://$bucket/assets" --delete \
    --cache-control "public, max-age=31536000, immutable"
  aws s3 sync frontend/dist "s3://$bucket" --delete --exclude "assets/*" \
    --cache-control "no-cache"

  echo "==> [6/6] Invalidate the CloudFront cache"
  invalidation="$(aws cloudfront create-invalidation --distribution-id "$distribution" \
    --paths "/*" --query Invalidation.Id --output text)"
  aws cloudfront wait invalidation-completed --distribution-id "$distribution" --id "$invalidation"

  echo
  echo "App: $(output "$FRONTEND_STACK" AppUrl)"
  custom_url="$(output "$FRONTEND_STACK" CustomDomainUrl 2>/dev/null || true)"
  [ -z "$custom_url" ] || [ "$custom_url" = "None" ] || echo "     $custom_url"
  [ -z "$api_base_url" ] || echo "API: $api_base_url/api"
}

main "$@"
