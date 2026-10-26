#!/usr/bin/env bash
# Deploys the serverless backend (AWS Lambda behind API Gateway + Aurora Serverless v2) to AWS.
# Run via `make deploy-backend`, which loads AWS credentials and settings from .env.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  require_auth_stack
  LAMBDA_MEMORY="${LAMBDA_MEMORY:-512}"
  PASSWORD_PARAM="/$PROJECT_NAME/db-password"

  # Git SHA for immutable container tagging
  TAG="$(git rev-parse --short HEAD)"
  if [ -n "$(git status --porcelain -- backend)" ]; then
    TAG="$TAG-dirty-$(date +%Y%m%d%H%M%S)"
  fi

  account="$(aws sts get-caller-identity --query Account --output text)"
  echo "==> Deploying '$PROJECT_NAME' serverless backend $TAG to account $account in $AWS_REGION"

  echo "==> [1/5] Database password ($PASSWORD_PARAM)"
  if aws ssm get-parameter --name "$PASSWORD_PARAM" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "    exists, keeping it"
  else
    # Hex only, so it can go into DATABASE_URL without escaping.
    aws ssm put-parameter --name "$PASSWORD_PARAM" --type SecureString \
      --value "$(openssl rand -hex 24)" --region "$AWS_REGION" >/dev/null
    echo "    created"
  fi
  aws ssm add-tags-to-resource --resource-type Parameter --resource-id "$PASSWORD_PARAM" \
    --tags "Key=$TAG_KEY,Value=$PROJECT_NAME" --region "$AWS_REGION" 2>/dev/null || true
  db_password="$(aws ssm get-parameter --name "$PASSWORD_PARAM" --with-decryption \
    --query Parameter.Value --output text --region "$AWS_REGION")"

  echo "==> [2/5] Container registry ($ECR_STACK)"
  aws cloudformation deploy \
    --stack-name "$ECR_STACK" \
    --template-file infra/ecr.yaml \
    --parameter-overrides "ProjectName=$PROJECT_NAME" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset
  repository="$(output "$ECR_STACK" RepositoryUri)"
  image="$repository:$TAG"

  echo "==> [3/5] Build and push $image"
  if aws ecr describe-images --repository-name "$PROJECT_NAME-backend" --image-ids "imageTag=$TAG" >/dev/null 2>&1; then
    echo "    already in ECR, skipping build"
  else
    docker build --platform linux/amd64 -t "$image" backend
    aws ecr get-login-password | docker login --username AWS --password-stdin "${repository%%/*}"
    docker push "$image"
  fi

  echo "==> [4/5] Lambda + API Gateway + Aurora Serverless ($BACKEND_STACK)"
  pool_id="$(output "$AUTH_STACK" UserPoolId)"
  client_id="$(output "$AUTH_STACK" UserPoolClientId)"
  issuer="$(output "$AUTH_STACK" Issuer)"
  jwks=""
  if [ -n "$issuer" ]; then
    jwks="$(curl -fsS "$issuer/.well-known/jwks.json" 2>/dev/null \
      | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin), separators=(",", ":")))' 2>/dev/null || true)"
  fi
  cors="$(cors_origins)"
  echo "    Cognito: $pool_id (client $client_id)"
  echo "    CORS origins: $cors"
  echo "    First deployment creates Aurora Serverless v2 PostgreSQL (takes ~10-15 min)"

  db_endpoint="${DATABASE_ENDPOINT:-}"
  if [ -z "$db_endpoint" ]; then
    db_endpoint="$(aws rds describe-db-clusters --db-cluster-identifier "$PROJECT_NAME-db" \
      --query "DBClusters[0].Endpoint" --output text 2>/dev/null || echo "")"
  fi

  aws cloudformation deploy \
    --stack-name "$BACKEND_STACK" \
    --template-file infra/backend.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "ImageUri=$image" \
      "DatabaseEndpoint=${db_endpoint:-$PROJECT_NAME-db.cluster-cxuqe02cwqxo.eu-north-1.rds.amazonaws.com}" \
      "DBPassword=$db_password" \
      "MemorySize=$LAMBDA_MEMORY" \
      "CorsOrigins=$cors" \
      "CognitoUserPoolId=$pool_id" \
      "CognitoClientId=$client_id" \
      "CognitoJwks=$jwks" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  api_url="$(output "$BACKEND_STACK" ApiUrl)"
  docs_url="$(output "$BACKEND_STACK" DocsUrl)"

  echo "==> [5/5] Wait for $api_url/health"
  for _ in $(seq 30); do
    if curl -fsS --max-time 15 "$api_url/health" >/dev/null 2>&1; then
      echo
      echo "API:     $api_url"
      echo "Docs:    $docs_url"
      exit 0
    fi
    sleep 10
  done

  echo "Backend did not become healthy in time. Checking CloudWatch logs:" >&2
  aws logs tail "/$PROJECT_NAME/backend" --max-items 30 || true
  exit 1
}

main "$@"
