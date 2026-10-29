# ADR 0006: LLM-Powered Agenda Parsing with AWS Bedrock

## Status
Accepted

## Context
Users frequently coordinate meetings using unstructured notes, emails, or chat messages written in Ukrainian or English. Manually breaking these into structured discussion topics, presenters, estimated durations, and actionable follow-ups with due dates is repetitive and prone to omissions.

To automate this workflow, we require an AI capability that parses raw pasted text into a structured JSON schema.

However, several architectural constraints shape the solution:
1. **Cost Optimization & Network Constraints**:
   - The main backend API runs inside an isolated AWS VPC to communicate with Aurora Serverless v2 PostgreSQL.
   - Under minimal-cost constraints, the VPC contains no NAT Gateway and no private VPC Endpoints for Bedrock (which cost ~$7.20/month per AZ plus data fees).
   - Calling external AI services from inside a private VPC with no NAT Gateway or Bedrock VPC Endpoint would timeout or require expensive networking infrastructure.
2. **Bedrock Model Availability**:
   - Legacy Claude model IDs (`anthropic.claude-3-5-sonnet-20241022-v2:0` and `anthropic.claude-3-haiku-20240307-v1:0`) have reached End-Of-Life (EOL) in `us-east-1`.
   - Active inference profiles (specifically `us.anthropic.claude-haiku-4-5-20251001-v1:0`) provide sub-2-second latency, excellent multilingual support for Ukrainian and English, robust tool/schema extraction, and minimal cost ($0.25 per 1M input tokens, $1.25 per 1M output tokens).
3. **Security & Prompt Injection**:
   - Raw user text from the web clipboard is untrusted input and must not manipulate the extraction schema or bypass constraints.
   - Unauthenticated access to Bedrock could lead to runaway costs; endpoints must verify authenticated Cognito identity.
   - Large payloads could overload token limits or exhaust Lambda execution budgets.

## Decision

We adopt **"The Split" Architecture**, separating AI extraction from relational database persistence:

```
[ User Browser / SPA ]
       |                                      \
       | (1) POST raw text + Bearer JWT       | (3) POST /meetings/{id}/agenda
       v                                      v
[ AgendaParserFunction ] (Outside VPC)    [ Main API Gateway + Backend ] (In VPC)
       |                                      |
       | Bedrock Converse API (IAM)          | SQL queries
       v                                      v
[ AWS Bedrock (us-east-1) ]               [ Aurora PostgreSQL (new-project-db) ]
```

### 1. The Split: Two Dedicated Functions
- **`AgendaParserFunction`**:
  - Deployed **outside the VPC** with direct internet access.
  - Interacts with AWS Bedrock in `us-east-1` via standard IAM execution role permissions (`bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`).
  - Requires no NAT Gateway and no Bedrock VPC Endpoints, saving ~$30–$40/month in idle networking costs.
  - Exposes an AWS Lambda Function URL (`AuthType: NONE`) with native CORS support.
  - Protects the endpoint at the application level by cryptographically validating Cognito ID/Access JWT tokens against User Pool JWKS (`eu-north-1`).
  - Limits input size to 10,000 characters (enforcing HTTP 413 Payload Too Large if exceeded).
- **`Main Backend API`**:
  - Remains **inside the VPC**, connected securely to Aurora Serverless v2 PostgreSQL.
  - Handles authenticated `GET /meetings/{meeting_id}/agenda` and `POST /meetings/{meeting_id}/agenda` endpoints.
  - Persists the validated items, action items, and the raw `ai_suggestion` JSONB payload for auditability.

### 2. Prompt Construction & Injection Guardrails
- Paste input is enclosed strictly in XML delimiters: `<pasted_text>...</pasted_text>`.
- System instructions explicitly define `<pasted_text>` as untrusted user input, forbidding execution of embedded commands or system directive overrides.
- Reference date (`today`) and user timezone (`tz`) are injected into the system prompt to resolve relative temporal references (e.g. "tomorrow", "this Friday", "next week") into exact ISO dates.
- Extraction is performed via the Bedrock Converse API `toolConfig` with `extract_agenda` matching the `ParsedAgenda` Pydantic model.
- If schema validation fails on the first attempt, the system automatically performs 1 conversational retry with the validation error message fed back to the model before failing.

### 3. Observability & Cost Tracking
- Every successful parse logs a structured JSON entry to CloudWatch:
  ```json
  {
    "event": "agenda_parsed",
    "user": "<cognito_sub>",
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "prompt_version": "agenda-v1",
    "input_tokens": 1694,
    "output_tokens": 111,
    "latency_ms": 1574,
    "cost_usd": 0.000562
  }
  ```

### 4. Frontend Experience
- The Meeting Details dialog features an interactive "Paste an agenda" panel with an `AbortController` cancel button.
- Parsed items are presented with `suggested` badges.
- Any user edit (changing topic, owner, duration, task, or due date) immediately dismisses the `suggested` badge for that specific item.
- Users can review, add, modify, or delete items before explicitly clicking "Save Agenda".

## Consequences

### Positive
- **Cost**: Eliminates the requirement for NAT Gateways ($32+/mo) and Bedrock VPC Endpoints ($7.20+/mo per AZ). Average invocation cost is ~$0.0005.
- **Security**: Strict isolation. The Bedrock function has zero access to database credentials or VPC internal subnets; the VPC database Lambda has zero internet exposure.
- **Robustness**: Tool use schema constraints combined with Pydantic validation and 1-attempt retry guarantee type-safe agenda outputs.
- **Observability**: Real-time token usage, cost, and latency metrics emitted on every invocation.

### Negative / Trade-offs
- **Multiple Lambdas**: The application now maintains two Lambda functions (VPC API and non-VPC AI parser). Container re-use mitigates packaging overhead by using the same ECR image with distinct entrypoints (`app.ai.agenda_lambda.handler`).
- **Cross-Region Calls**: Lambda in `eu-north-1` or public Function URL triggers Bedrock in `us-east-1` over AWS backbone, adding ~80ms network latency compared to same-region calls.
