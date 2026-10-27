#!/bin/sh
# Lambda adapter wrapper: if DISABLE_LWA is true or REPORT_BUILDER is set,
# register with the Lambda Extension API for SHUTDOWN and sleep,
# allowing the runtime (app.reports.runner) to execute without web adapter interference.
if [ "$DISABLE_LWA" = "true" ] || [ -n "$REPORT_BUILDER" ]; then
    if [ -n "$AWS_LAMBDA_RUNTIME_API" ]; then
        exec /opt/venv/bin/python -c '
import os, sys, urllib.request, json
runtime_api = os.environ.get("AWS_LAMBDA_RUNTIME_API", "")
if not runtime_api:
    sys.exit(0)
req = urllib.request.Request(
    f"http://{runtime_api}/2020-01-01/extension/register",
    data=json.dumps({"events": ["SHUTDOWN"]}).encode("utf-8"),
    headers={"Lambda-Extension-Name": "lambda-adapter", "Content-Type": "application/json"}
)
with urllib.request.urlopen(req) as resp:
    ext_id = resp.headers.get("Lambda-Extension-Identifier", "")

while True:
    next_req = urllib.request.Request(
        f"http://{runtime_api}/2020-01-01/extension/event/next",
        headers={"Lambda-Extension-Identifier": ext_id}
    )
    with urllib.request.urlopen(next_req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        if data.get("eventType") == "SHUTDOWN":
            break
'
    else
        exit 0
    fi
else
    exec /opt/lambda-adapter-bin
fi
