FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# AWS Lambda Web Adapter: allows the uvicorn app to run on AWS Lambda; inert everywhere else.
ADD https://github.com/aws/aws-lambda-web-adapter/releases/download/v0.8.4/lambda-adapter-x86_64 /opt/extensions/lambda-adapter
RUN chmod +x /opt/extensions/lambda-adapter 2>/dev/null || true

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project

COPY . .
RUN chmod +x /app/entrypoint.sh

EXPOSE 8000
CMD ["/app/entrypoint.sh"]
