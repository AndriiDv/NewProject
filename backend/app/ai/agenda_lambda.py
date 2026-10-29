import json
import logging
import os
import sys
import time
import urllib.request
from datetime import date
from typing import Any

import jwt

from app.ai.agenda import DEFAULT_MODEL, parse_agenda

logger = logging.getLogger("agenda-lambda")
logger.setLevel(logging.INFO)

# Structured JSON log format
_stdout_handler = logging.StreamHandler(sys.stdout)
_stdout_handler.setFormatter(logging.Formatter("%(message)s"))
logger.addHandler(_stdout_handler)
logger.propagate = False

# Cached JWKS keys
_JWKS_CACHE: dict[str, Any] = {"jwks": None, "fetched_at": 0.0}
_JWKS_TTL_SECONDS = 600  # 10 minutes


class AuthError(Exception):
    def __init__(self, message: str, status_code: int = 401):
        super().__init__(message)
        self.status_code = status_code


def _get_jwks(issuer: str) -> jwt.PyJWKSet:
    now = time.monotonic()
    if _JWKS_CACHE["jwks"] is not None and (now - _JWKS_CACHE["fetched_at"] < _JWKS_TTL_SECONDS):
        return _JWKS_CACHE["jwks"]

    url = f"{issuer}/.well-known/jwks.json"
    req = urllib.request.Request(url, headers={"User-Agent": "agenda-parser-lambda"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        jwks = jwt.PyJWKSet.from_json(resp.read().decode("utf-8"))
        _JWKS_CACHE["jwks"] = jwks
        _JWKS_CACHE["fetched_at"] = now
        return jwks


def verify_cognito_token(token: str, user_pool_id: str, client_id: str) -> dict[str, Any]:
    """Verify Cognito Bearer JWT token against User Pool JWKS."""
    if not token or not token.strip():
        raise AuthError("Missing authorization token")

    clean_token = token.strip()
    if clean_token.lower().startswith("bearer "):
        clean_token = clean_token[7:].strip()

    if not user_pool_id:
        raise AuthError("Cognito User Pool ID is not configured")

    region = user_pool_id.split("_", 1)[0]
    issuer = f"https://cognito-idp.{region}.amazonaws.com/{user_pool_id}"

    try:
        header = jwt.get_unverified_header(clean_token)
        kid = header.get("kid")
        if not kid:
            raise AuthError("Missing key ID (kid) in token header")

        jwks = _get_jwks(issuer)
        key = next((k for k in jwks.keys if k.key_id == kid), None)
        if key is None:
            # Force refresh cache once in case keys rotated
            _JWKS_CACHE["jwks"] = None
            jwks = _get_jwks(issuer)
            key = next((k for k in jwks.keys if k.key_id == kid), None)
            if key is None:
                raise AuthError(f"Unknown signing key ID: {kid}")

        # Decode and verify signature, issuer, and expiration
        claims = jwt.decode(
            clean_token,
            key.key,
            algorithms=["RS256"],
            issuer=issuer,
            options={"verify_aud": False, "require": ["exp", "sub", "iss"]},
        )

        token_use = claims.get("token_use")
        if token_use == "id":
            aud = claims.get("aud")
            if aud != client_id and client_id != "*":
                raise AuthError(f"Token audience mismatch: expected {client_id}, got {aud}")
        elif token_use == "access":
            c_id = claims.get("client_id")
            if c_id != client_id and client_id != "*":
                raise AuthError(f"Token client_id mismatch: expected {client_id}, got {c_id}")

        return claims
    except jwt.ExpiredSignatureError as e:
        raise AuthError("Token has expired") from e
    except (jwt.PyJWTError, Exception) as e:
        raise AuthError(f"Invalid token: {e}") from e


def _cors_headers() -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, content-type, x-requested-with",
    }


def handler(event: dict[str, Any], context: Any = None) -> dict[str, Any]:
    """Lambda entry point for agenda parsing via Function URL or direct invocation."""
    cors = _cors_headers()

    # 1. Handle HTTP Method / Request context
    http_method = (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod")
        or "POST"
    ).upper()

    if http_method == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": cors,
            "body": "",
        }

    # 2. Extract headers and verify authentication
    headers = event.get("headers") or {}
    auth_header = None
    for k, v in headers.items():
        if k.lower() == "authorization":
            auth_header = v
            break

    user_pool_id = os.environ.get("COGNITO_USER_POOL_ID", "")
    client_id = os.environ.get("COGNITO_CLIENT_ID", "")

    if not auth_header:
        return {
            "statusCode": 401,
            "headers": cors,
            "body": json.dumps({"detail": "Authorization header is required"}),
        }

    try:
        claims = verify_cognito_token(auth_header, user_pool_id, client_id)
        user_sub = str(claims.get("sub", "unknown"))
    except AuthError as auth_err:
        return {
            "statusCode": auth_err.status_code,
            "headers": cors,
            "body": json.dumps({"detail": str(auth_err)}),
        }

    # 3. Parse Body
    body_raw = event.get("body")
    if body_raw is not None:
        if isinstance(body_raw, str):
            try:
                body = json.loads(body_raw)
            except Exception:
                return {
                    "statusCode": 400,
                    "headers": cors,
                    "body": json.dumps({"detail": "Invalid JSON body"}),
                }
        elif isinstance(body_raw, dict):
            body = body_raw
        else:
            body = {}
    else:
        # Direct invocation payload
        body = event

    text = body.get("text", "")
    if not isinstance(text, str) or not text.strip():
        return {
            "statusCode": 400,
            "headers": cors,
            "body": json.dumps({"detail": "Field 'text' is required and must not be empty"}),
        }

    # Reject text > 10000 characters with HTTP 413
    if len(text) > 10000:
        return {
            "statusCode": 413,
            "headers": cors,
            "body": json.dumps(
                {
                    "detail": (
                        f"Payload Too Large: text length ({len(text)}) "
                        "exceeds maximum limit of 10000 characters"
                    )
                }
            ),
        }

    # Timezone & date
    tz = str(body.get("tz") or "Europe/Kyiv")
    today_str = body.get("today")
    today_val = None
    if today_str:
        try:
            today_val = date.fromisoformat(str(today_str))
        except Exception:
            pass

    model = os.environ.get("PARSER_MODEL", DEFAULT_MODEL)

    try:
        parsed_agenda, metadata = parse_agenda(
            text=text,
            today=today_val,
            tz=tz,
            model_id=model,
        )

        # Required structured JSON log line:
        log_entry = {
            "event": "agenda_parsed",
            "user": user_sub,
            "model": metadata["model"],
            "prompt_version": metadata["prompt_version"],
            "input_tokens": metadata["input_tokens"],
            "output_tokens": metadata["output_tokens"],
            "latency_ms": metadata["latency_ms"],
            "cost_usd": metadata["cost_usd"],
        }
        logger.info(json.dumps(log_entry))

        res_payload = {
            "agenda": parsed_agenda.model_dump(mode="json"),
            "metadata": metadata,
        }

        return {
            "statusCode": 200,
            "headers": cors,
            "body": json.dumps(res_payload, ensure_ascii=False),
        }
    except Exception as exc:
        logger.exception("Agenda parsing failed: %s", exc)
        status_code = 429 if "Throttling" in type(exc).__name__ or "Throttling" in str(exc) else 500
        return {
            "statusCode": status_code,
            "headers": cors,
            "body": json.dumps({"detail": f"Agenda parsing error: {exc}"}),
        }


if __name__ == "__main__":
    test_event = {
        "text": (
            "Sprint planning on Monday 10:00. 1. Architecture (Andrii, 15m). "
            "Action: finalize spec by Wednesday (Andrii)"
        ),
        "tz": "Europe/Kyiv",
    }
    res = handler(test_event)
    print("Test handler execution status:", res["statusCode"])
    print("Response body:", res["body"][:200] + "...")
