# Legate Built-in Tools

This document serves as a reference guide for the common tools included with the Legate. These tools are available for agents to use once registered.

## General Usage Notes

*   **Tool Naming**: When adding tools to an agent definition, you typically use their inferred snake_case name (e.g., `:calculator`, `:echo_tool`) unless an `explicit_tool_name` is specified in the tool's class.
*   **Parameters**: Each tool defines its expected parameters, including their type and whether they are required.
*   **Return Value**: Successful tool executions generally return a hash with `status: :success` and a `result` field. Errors usually result in an `Legate::ToolError` or return a hash with `status: :error` and an `error_message`.

---

## Calculator

*   **Tool Name**: `:calculator` (inferred)
*   **Purpose**: Calculates the result of an arithmetic operation.
*   **Parameters**:
    *   `operand1` (numeric, required): The first number for the calculation.
    *   `operand2` (numeric, required): The second number for the calculation.
    *   `operation` (string, required): The operation to perform (e.g., "add", "subtract", "multiply", "divide", or symbols `+`, `-`, `*`, `/`).
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "calculator",
      "parameters": {
        "operand1": 10,
        "operand2": 5,
        "operation": "multiply"
      }
    }
    ```
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": 50
    }
    ```

---

## Echo

*   **Tool Name**: `:echo` (inferred from class `Echo` -> `Legate::Tools::Echo`)
*   **Purpose**: Echoes back the provided message.
*   **Parameters**:
    *   `message` (string, required): The message to echo.
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "echo",
      "parameters": {
        "message": "Hello, world!"
      }
    }
    ```
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": "Hello, world!"
    }
    ```

---

## CatFacts

*   **Tool Name**: `:cat_facts` (inferred)
*   **Purpose**: Fetches a random cat fact from an online API (`https://catfact.ninja`).
*   **Parameters**: None.
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "cat_facts",
      "parameters": {}
    }
    ```
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": "Cats have over 20 muscles that control their ears."
    }
    ```

---

## WebhookTool

*   **Tool Name**: `:webhook_tool` (explicitly set)
*   **Purpose**: Sends an HTTP POST request with a JSON payload to a specified webhook URL. Can optionally sign the request using HMAC-SHA256.
*   **Parameters**:
    *   `url` (string, required): The target webhook URL.
    *   `payload` (hash or string, required): The data payload to send. Hash payloads are automatically JSON-encoded with `Content-Type: application/json`.
    *   `secret` (string, optional): Optional secret key for calculating HMAC-SHA256 signature (sent in `X-Hub-Signature-256` header).
    *   `headers` (hash, optional): Optional custom headers to include (e.g., `Content-Type` for string payloads).
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "webhook_tool",
      "parameters": {
        "url": "https://example.com/my-hook",
        "payload": {"data": "some_value", "event": "item_created"},
        "secret": "mysecretkey"
      }
    }
    ```
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": {
        "response_status": 200,
        "response_body": "Webhook received successfully"
      }
    }
    ```

---

## HttpRequest

*   **Tool Name**: `:http_request` (inferred)
*   **Purpose**: Makes an HTTP request to a URL and returns the status code, headers, and body. Supports `GET` (default), `POST`, `PUT`, `PATCH`, `DELETE`, and `HEAD`.
*   **Security**: SSRF-safe — requests to loopback, link-local, private, CGNAT, and `0.0.0.0/8` addresses (e.g. cloud metadata at `169.254.169.254`) are blocked, and the connection is pinned to the validated IP to prevent DNS rebinding. Set `LEGATE_ALLOW_PRIVATE_TOOL_URLS=1` to reach private hosts in development.
*   **Auth-aware**: Configured authentication (URL → scheme/credential mappings) is applied automatically for matching URLs. Pass `headers` for manual auth.
*   **Parameters**:
    *   `url` (string, required): The full URL to request (must be `http` or `https`).
    *   `method` (string, optional): HTTP method. Defaults to `GET`.
    *   `headers` (hash, optional): Request headers.
    *   `body` (hash or string, optional): Request body. A Hash is JSON-encoded with `Content-Type: application/json`.
    *   `query` (hash, optional): Query-string parameters.
*   **Notes**: A non-2xx response is returned as a normal result (with its `status_code`) so an agent can inspect it; only network/SSRF/timeout failures are errors. Bodies are capped at 1 MB (`truncated: true` when cut).
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": {
        "url": "https://api.example.com/v1/items",
        "status_code": 200,
        "headers": { "content-type": "application/json" },
        "body": "{\"items\": []}",
        "truncated": false
      }
    }
    ```

---

## ReadWebpage

*   **Tool Name**: `:read_webpage` (inferred)
*   **Purpose**: Fetches a web page and returns its title and readable text content with HTML markup removed (script/style stripped, entities decoded, whitespace collapsed). The backbone of research/RAG agents.
*   **Security**: SSRF-safe, identical guards to `http_request`.
*   **Parameters**:
    *   `url` (string, required): The URL of the page to read (`http` or `https`).
    *   `max_chars` (integer, optional): Maximum characters of text to return (default 20,000, hard cap 200,000).
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": {
        "url": "https://example.com",
        "title": "Example Domain",
        "text": "Example Domain  This domain is for use in illustrative examples...",
        "truncated": false
      }
    }
    ```

---

## CurrentTime

*   **Tool Name**: `:current_time` (inferred)
*   **Purpose**: Returns the current date and time. Language models don't know the current time, so this is a common building block for scheduling, freshness checks, and "how long ago" reasoning.
*   **Parameters**:
    *   `timezone` (string, optional): `"UTC"` (default), `"local"`, or a fixed UTC offset such as `"+05:30"` or `"-0800"`. Named IANA zones (e.g. `America/New_York`) are intentionally not supported (no timezone-database dependency).
    *   `format` (string, optional): A strftime format (e.g. `"%A, %B %-d, %Y"`). Defaults to ISO 8601.
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": {
        "iso8601": "2026-06-14T14:05:09Z",
        "formatted": "2026-06-14T14:05:09Z",
        "epoch": 1781445909,
        "timezone": "UTC"
      }
    }
    ```

---

## AgentTool (Delegate Task)

*   **Tool Name**: `:delegate_task` (explicitly set, class `AgentTool`)
*   **Purpose**: Delegates a specified task to another agent identified by its unique name. This is useful when a specific, pre-defined agent is better suited for a sub-task.
*   **Parameters**:
    *   `target_agent_name` (string, required): The unique name of the agent definition (must be findable by `Legate::GlobalDefinitionRegistry`) to delegate the task to.
    *   `task` (string, required): The specific task description to be executed by the target agent.
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "delegate_task",
      "parameters": {
        "target_agent_name": "customer_service_agent",
        "task": "The user is asking for a refund for order 12345. Please process this."
      }
    }
    ```
*   **Example Success Response** (depends on the target agent's response):
    ```json
    {
      "status": "success",
      "result": "The refund for order 12345 has been processed successfully."
    }
    ```

---

## Asynchronous Operations Tools

Legate provides a mechanism for tools to initiate long-running tasks as background threads using `Concurrent::Promises.future`. This typically involves two tools: one to start the job and one to check its status.

### BaseAsyncJobTool (Developer Note)
This is an abstract base class (`Legate::Tools::BaseAsyncJobTool`) and not directly invoked by an agent. Developers creating new asynchronous tools would inherit from it. It handles the common logic of running tasks in background threads and storing job results in an in-memory `Concurrent::Map`.

### SleepyTool (Example Async Tool)

*   **Tool Name**: `:start_sleepy_job` (explicitly set, class `SleepyTool`)
*   **Purpose**: Starts a background task that simply sleeps for a specified duration and then records a message. This tool is primarily an example of an asynchronous tool.
*   **Parameters**:
    *   `duration` (integer, required): How many seconds the task should sleep.
    *   `message` (string, required): A message to include in the final result upon task completion.
*   **Invocation Result**: When this tool is called, it starts a background thread via `Concurrent::Promises.future`.
    *   **Example Success Response (Job Enqueued)**:
        ```json
        {
          "status": "pending",
          "job_id": "abcdef1234567890"
        }
        ```
*   **Getting the Actual Result**: Use the `check_job_status` tool with the returned `job_id`.

### CheckJobStatusTool

*   **Tool Name**: `:check_job_status` (explicitly set, class `CheckJobStatusTool`)
*   **Purpose**: Checks the status and retrieves the result of a previously started background task using its `job_id`.
*   **Parameters**:
    *   `job_id` (string, required): The ID of the job to check (obtained from a tool like `start_sleepy_job`).
*   **Response Scenarios**:
    *   **Job Pending**:
        ```json
        {
          "status": "pending",
          "job_id": "abcdef1234567890",
          "message": "Job is queued or currently running."
        }
        ```
    *   **Job Succeeded** (result from in-memory store):
        ```json
        {
          "status": "success",
          "job_id": "abcdef1234567890",
          "result": "Slept for 10 seconds. Your message: Hello from async job."
        }
        ```
    *   **Job Errored** (error from in-memory store):
        ```json
        {
          "status": "error",
          "job_id": "abcdef1234567890",
          "error_message": "Something went wrong during the job.",
          "error_details": "Optional details about the error, like exception class."
        }
        ```
    *   **Job Failed**: The tool call itself might raise an `Legate::ToolError` or return a generic error status.
    *   **Job Not Found/Expired**: The tool call might raise an `Legate::ToolError` or return an error status indicating the result is unavailable.

```mermaid
graph LR
    subgraph "Async Tool Flow"
        A[Agent] -- Calls --> B(Start Async Job Tool <br> e.g., :start_sleepy_job)
        B -- Starts Thread --> C[Concurrent::Promises.future]
        B -- Returns job_id --> A
        C -- Executes --> D(Background Thread)
        D -- Writes Result/Error --> E[Concurrent::Map]
        A -- Calls with job_id --> F(Check Job Status Tool <br> :check_job_status)
        F -- Reads from --> E
        F -- Returns Status/Result --> A
    end

    style A fill:#cde,stroke:#333
    style B fill:#fdc,stroke:#333
    style C fill:#def,stroke:#333
    style D fill:#fdd,stroke:#333
    style E fill:#fcf,stroke:#333
    style F fill:#dfd,stroke:#333
```

---

## RandomNumberTool (demo tool — not registered by default)

> `random_number` ships with Legate but is **not registered as a default tool**.
> It's a demo. Opt in with `Legate::GlobalToolManager.register_tool(Legate::Tools::RandomNumberTool)`
> before an agent can `use_tool :random_number`.

*   **Tool Name**: `:random_number` (explicitly set, class `RandomNumberTool`)
*   **Purpose**: Generates a random integer between a minimum and maximum value (inclusive). Defaults to generating a number between 1 and 100 if no parameters are provided.
*   **Parameters**:
    *   `min` (integer, optional): The minimum value for the random number (inclusive). Defaults to 1.
    *   `max` (integer, optional): The maximum value for the random number (inclusive). Defaults to 100.
*   **Example Invocation (Conceptual)**:
    ```json
    {
      "tool_name": "random_number",
      "parameters": {
        "min": 10,
        "max": 20
      }
    }
    ```
*   **Example Success Response**:
    ```json
    {
      "status": "success",
      "result": 15
    }
    ```