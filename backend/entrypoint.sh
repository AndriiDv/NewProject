#!/usr/bin/env sh
set -e

if [ "$1" = "app.reports.builder_handler.handler" ] || [ -n "$REPORT_BUILDER" ]; then
    HANDLER="${1:-app.reports.builder_handler.handler}"
    exec /opt/venv/bin/python -m app.reports.runner "$HANDLER"
fi

if [ "$1" = "app.ai.agenda_lambda.handler" ] || [ -n "$AGENDA_PARSER" ]; then
    HANDLER="${1:-app.ai.agenda_lambda.handler}"
    exec /opt/venv/bin/python -m app.reports.runner "$HANDLER"
fi

if [ -n "$DATABASE_URL" ]; then
  python - <<'EOF'
import os, time, socket, urllib.parse

raw_url = os.environ.get("DATABASE_URL", "")
# Strip asyncpg dialect prefix for standard parsing if present
clean_url = raw_url.replace("+asyncpg", "")
url = urllib.parse.urlsplit(clean_url)
host = url.hostname or "127.0.0.1"
port = url.port or 5432

for _ in range(60):
    try:
        with socket.create_connection((host, port), timeout=2):
            print(f"Database reachable at {host}:{port}")
            break
    except OSError:
        print(f"Waiting for database at {host}:{port}...")
        time.sleep(1)
EOF
fi

alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000

