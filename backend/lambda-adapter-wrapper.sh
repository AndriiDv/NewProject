#!/bin/sh
# Lambda adapter wrapper: if DISABLE_LWA is true or REPORT_BUILDER is set,
# register with the Lambda Extension API for SHUTDOWN and sleep,
# allowing the runtime (app.reports.runner) to execute without web adapter interference.
if [ "$DISABLE_LWA" = "true" ] || [ -n "$REPORT_BUILDER" ]; then
    if [ -n "$AWS_LAMBDA_RUNTIME_API" ]; then
        HEADERS="Lambda-Extension-Name: lambda-adapter"
        RESP=$(curl -s -D /tmp/ext_headers -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2020-01-01/extension/register" \
            -H "$HEADERS" \
            -d '{"events":["SHUTDOWN"]}')
        EXT_ID=$(grep -i "Lambda-Extension-Identifier" /tmp/ext_headers | tr -d '\r' | awk '{print $2}')
        while true; do
            curl -s "http://${AWS_LAMBDA_RUNTIME_API}/2020-01-01/extension/event/next" \
                -H "Lambda-Extension-Identifier: ${EXT_ID}" > /dev/null 2>&1 || sleep 1
        done
    else
        exit 0
    fi
else
    exec /opt/lambda-adapter-bin
fi
