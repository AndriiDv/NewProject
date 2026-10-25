#!/usr/bin/env bash
# Deploys the backend (ECS Fargate behind ALB) to AWS. Run via
# `make deploy-backend`, which loads AWS credentials and settings from .env.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  # Git SHA for immutable container tagging
  TAG="$(git rev-parse --short HEAD)"
  if [ -n "$(git status --porcelain -- backend)" ]; then
    TAG="$TAG-dirty-$(date +%Y%m%d%H%M%S)"
  fi

  account="$(aws sts get-caller-identity --query Account --output text)"
  echo "==> Deploying '$PROJECT_NAME' backend $TAG to account $account in $AWS_REGION"

  echo "==> [1/4] Container registry ($ECR_STACK)"
  aws cloudformation deploy \
    --stack-name "$ECR_STACK" \
    --template-file infra/ecr.yaml \
    --parameter-overrides "ProjectName=$PROJECT_NAME" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset
  repository="$(output "$ECR_STACK" RepositoryUri)"
  image="$repository:$TAG"

  echo "==> [2/4] Build and push $image"
  if aws ecr describe-images --repository-name "$PROJECT_NAME-backend" --image-ids "imageTag=$TAG" >/dev/null 2>&1; then
    echo "    already in ECR, skipping build"
  else
    docker build --platform linux/amd64 -t "$image" backend
    aws ecr get-login-password | docker login --username AWS --password-stdin "${repository%%/*}"
    docker push "$image"
  fi

  echo "==> [3/4] ECS Fargate + ALB ($BACKEND_STACK)"
  cors="$(cors_origins)"
  echo "    CORS origins: $cors"
  aws cloudformation deploy \
    --stack-name "$BACKEND_STACK" \
    --template-file infra/backend.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "ImageUri=$image" \
      "CorsOrigins=$cors" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  cluster="$(output "$BACKEND_STACK" ClusterName)"
  service="$(output "$BACKEND_STACK" ServiceName)"
  aws ecs update-service --cluster "$cluster" --service "$service" --force-new-deployment >/dev/null 2>&1 || true

  api_url="$(output "$BACKEND_STACK" ApiUrl)"
  alb_dns="$(output "$BACKEND_STACK" AlbDnsName)"

  echo "==> [4/4] Wait for $api_url/health"
  for _ in $(seq 30); do
    if curl -fsS --max-time 10 "$api_url/health" >/dev/null 2>&1; then
      echo
      echo "API:     $api_url"
      echo "ALB DNS: $alb_dns"
      echo "Docs:    $(output "$BACKEND_STACK" DocsUrl)"
      exit 0
    fi
    sleep 10
  done

  echo "Backend did not become healthy in time. Checking ALB target health:" >&2
  tg_arn="$(output "$BACKEND_STACK" TargetGroupArn)"
  aws elbv2 describe-target-health --target-group-arn "$tg_arn" || true
  exit 1
}

main "$@"
