"""Pure-Python AWS Lambda Runtime Interface runner.

Allows executing standard Lambda handlers (e.g. app.reports.builder_handler.handler)
in containers on the AWS Lambda Runtime API without requiring C extensions or external daemons.
"""

import importlib
import json
import logging
import os
import sys
import time
import traceback
import urllib.request

logger = logging.getLogger("lambda_runner")


class LambdaContext:
    def __init__(
        self,
        request_id: str,
        deadline_ms: str | None,
        invoked_function_arn: str | None,
    ):
        self.aws_request_id = request_id
        self.deadline_ms = int(deadline_ms) if deadline_ms else None
        self.invoked_function_arn = invoked_function_arn
        self.function_name = os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "report-builder")
        self.memory_limit_in_mb = int(os.environ.get("AWS_LAMBDA_FUNCTION_MEMORY_SIZE", "512"))
        self.log_group_name = os.environ.get("AWS_LAMBDA_LOG_GROUP_NAME", "")
        self.log_stream_name = os.environ.get("AWS_LAMBDA_LOG_STREAM_NAME", "")

    def get_remaining_time_in_millis(self) -> int:
        if not self.deadline_ms:
            return 60000
        now_ms = int(time.time() * 1000)
        return max(0, self.deadline_ms - now_ms)


def main():
    runtime_api = os.environ.get("AWS_LAMBDA_RUNTIME_API")
    if not runtime_api:
        # Local execution / direct invocation
        from app.reports.builder_handler import handler

        res = handler({"source": "manual", "week": None}, None)
        print("Local execution result:", res)
        return

    handler_spec = (
        sys.argv[1]
        if len(sys.argv) > 1 and sys.argv[1]
        else os.environ.get("_HANDLER", "app.reports.builder_handler.handler")
    )
    mod_name, func_name = handler_spec.rsplit(".", 1)
    mod = importlib.import_module(mod_name)
    handler_func = getattr(mod, func_name)

    base_url = f"http://{runtime_api}/2018-06-01/runtime/invocation"

    while True:
        # 1. Fetch next invocation
        next_req = urllib.request.Request(f"{base_url}/next")
        with urllib.request.urlopen(next_req) as resp:
            req_id = resp.headers.get("Lambda-Runtime-Aws-Request-Id")
            deadline_ms = resp.headers.get("Lambda-Runtime-Deadline-Ms")
            invoked_arn = resp.headers.get("Lambda-Runtime-Invoked-Function-Arn")
            body_bytes = resp.read()
            event = json.loads(body_bytes.decode("utf-8")) if body_bytes else {}

        ctx = LambdaContext(req_id, deadline_ms, invoked_arn)

        # 2. Invoke handler
        try:
            result = handler_func(event, ctx)
            res_payload = json.dumps(result, default=str).encode("utf-8")
            res_req = urllib.request.Request(
                f"{base_url}/{req_id}/response",
                data=res_payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(res_req)
        except Exception as exc:
            logger.exception("Handler invocation error: %s", exc)
            err_payload = json.dumps(
                {
                    "errorMessage": str(exc),
                    "errorType": type(exc).__name__,
                    "stackTrace": traceback.format_tb(exc.__traceback__),
                }
            ).encode("utf-8")
            err_req = urllib.request.Request(
                f"{base_url}/{req_id}/error",
                data=err_payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(err_req)


if __name__ == "__main__":
    main()
