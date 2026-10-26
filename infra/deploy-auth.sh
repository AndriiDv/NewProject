#!/usr/bin/env bash
# Deploys the Cognito user pool and app client (infra/auth.yaml), prints the values the app
# needs and writes them to .env. Run via `make deploy-auth`. Google sign-in is created only
# when GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are set in .env.
set -euo pipefail

# set_env KEY VALUE: sets KEY=VALUE in .env, replacing an existing line or appending one.
set_env() {
  local key="$1" value="$2" tmp
  touch .env
  tmp="$(mktemp)"
  if grep -q "^$key=" .env; then
    awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' .env >"$tmp"
  else
    cat .env >"$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  cat "$tmp" >.env
  rm -f "$tmp"
}

# Everything runs inside main so bash parses the whole file before starting. Otherwise
# editing the script (or a git pull) during a long deploy makes bash resume mid-file.
main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  google_id="${GOOGLE_CLIENT_ID:-}"
  google_secret="${GOOGLE_CLIENT_SECRET:-}"
  domain_prefix="${COGNITO_DOMAIN_PREFIX:-andrii-dv}"

  if [ -n "$google_id" ] && [ -z "$google_secret" ]; then
    echo "GOOGLE_CLIENT_ID is set but GOOGLE_CLIENT_SECRET is empty; set both or neither." >&2
    exit 1
  fi

  echo "==> [1/2] Cognito user pool ($AUTH_STACK in $AWS_REGION)"
  urls="$(app_urls)"
  echo "    App URLs: $urls"
  echo "    Cognito Domain Prefix: $domain_prefix"
  echo "    Google sign-in: $([ -n "$google_id" ] && echo enabled || echo disabled)"
  aws cloudformation deploy \
    --stack-name "$AUTH_STACK" \
    --template-file infra/auth.yaml \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "CognitoDomainPrefix=$domain_prefix" \
      "AppUrls=$urls" \
      "GoogleClientId=$google_id" \
      "GoogleClientSecret=$google_secret" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  pool_id="$(output "$AUTH_STACK" UserPoolId)"
  client_id="$(output "$AUTH_STACK" UserPoolClientId)"
  domain="$(output "$AUTH_STACK" Domain)"
  google="$(output "$AUTH_STACK" GoogleEnabled)"

  echo "==> [2/2] Write the Cognito settings to .env"
  set_env COGNITO_USER_POOL_ID "$pool_id"
  set_env COGNITO_CLIENT_ID "$client_id"
  set_env COGNITO_DOMAIN "$domain"
  set_env COGNITO_GOOGLE_ENABLED "$google"

  # None of these are secrets: the browser receives all of them.
  echo
  echo "Cognito is ready. These are the app's auth settings (now in .env):"
  echo
  echo "  COGNITO_USER_POOL_ID=$pool_id"
  echo "  COGNITO_CLIENT_ID=$client_id"
  echo "  COGNITO_DOMAIN=$domain"
  echo "  COGNITO_GOOGLE_ENABLED=$google"
  echo
  echo "  Region:  $AWS_REGION"
  echo "  Issuer:  $(output "$AUTH_STACK" Issuer)"
  echo "  Console: https://$AWS_REGION.console.aws.amazon.com/cognito/v2/idp/user-pools/$pool_id/users?region=$AWS_REGION"
  echo
  echo "Next: make up (local) or make deploy (AWS) to use them."
}

main "$@"
