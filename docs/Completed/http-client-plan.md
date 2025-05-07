# ADK::Tools::Base::HttpClient Implementation Plan using Excon

This document outlines the plan for implementing a robust and flexible HTTP client mixin (`ADK::Tools::Base::HttpClient`) for the Ruby ADK, utilizing the `excon` gem.

## 1. Goals

*   Provide a standardized, reusable HTTP client component for ADK tools.
*   Leverage the features of `excon` (performance, persistence, middleware, timeouts).
*   Integrate seamlessly with the ADK's authentication system (`docs/authentication-plan.md`).
*   Offer a developer-friendly interface for making common HTTP requests.
*   Serve as the foundation for tools like the proposed `ADK::Tools::WebhookTool` (`docs/webhooks-plan.md`).

## 2. Core Implementation (`ADK::Tools::Base::HttpClient`)

*   **Location:** Define module in `lib/adk/tools/base/http_client.rb`.
*   **Type:** Implement as a Ruby `Module` (`ADK::Tools::Base::HttpClient`) intended to be `include`d by Tool classes that need HTTP capabilities.
*   **Dependency:** Add `excon` to the `adk-ruby.gemspec`. Add `require 'json'` within the module for body handling.
*   **Wrapper:** The module will wrap an `Excon::Connection` instance.
*   **Initialization:**
    *   Provide a `setup_http_client(base_url:, headers: {}, options: {})` method within the module. Tools including this module will call this in their `initialize` method.
    *   `base_url`: The base URL for the API the tool interacts with. Should end with `/` if intended to be a directory-like base.
    *   `headers`: Default headers (e.g., `Content-Type`, `Accept`). Automatically add a default `User-Agent` header (e.g., "ADK-Ruby/#{ADK::VERSION} #{Excon::USER_AGENT}") unless overridden.
    *   `options`: A hash passed directly to `Excon.new`, allowing configuration of timeouts (`read_timeout`, `write_timeout`, `connect_timeout`), persistence (`persistent`), proxy settings (`proxy`), SSL verification (`ssl_verify_peer`, `ssl_ca_file`), etc. Sensible defaults from `Excon.defaults` will apply if not overridden. Consider ADK-specific defaults like shorter timeouts or `persistent: true` if generally beneficial.
    *   Store the configured `Excon::Connection` instance in an instance variable (e.g., `@http_client`).
    *   **Logging:** Automatically configure the `Excon::Connection` to use `Excon::LoggingInstrumentor` tied to `ADK.logger` (if `ADK.logger` is available). Allow disabling or customizing this via the `options` hash (e.g., `instrumentor: nil` or a custom instrumentor instance).
*   **Request Methods:**
    *   Define helper methods like `http_get(path, query: {}, headers: {}, options: {})`, `http_post(path, body:, query: {}, headers: {}, options: {})`, `http_put`, `http_delete`, etc.
    *   **Path Joining:** The `path` argument will be joined with the `base_url` using `URI.join` to correctly handle relative and absolute paths.
    *   These methods will construct the final request parameters by merging defaults (from `setup_http_client`) with per-request parameters.
    *   They will call the appropriate method on the `@http_client` instance (`@http_client.get`, `@http_client.post`, etc.).
    *   **Body Handling:**
        *   Automatically handle JSON encoding (using `JSON.generate`) for `Hash` bodies in POST/PUT requests, setting `Content-Type: application/json`. Allow overriding this default `Content-Type` via the `headers` parameter.
        *   If the `body` parameter is already a `String`, pass it through directly. Assume it's correctly encoded (e.g., pre-encoded JSON, form data) and respect any `Content-Type` header provided.
*   **Response Handling:**
    *   The helper methods should return the parsed `Excon::Response` object or raise an appropriate `ADK::ToolError`.
*   **Error Handling:**
    *   Rescue common `Excon::Errors` (e.g., `Excon::Error::Timeout`, `Excon::Error::Socket`, `Excon::Error::HTTPStatusError`, `Excon::Error::CertificateError`).
    *   Wrap these errors in a suitable `ADK::ToolError` (or specific subclasses like `ADK::ToolNetworkError`, `ADK::ToolTimeoutError`, `ADK::ToolHttpError`, defined in `lib/adk/tool/error.rb`) to provide a consistent error interface for tools. The original `excon` error **must** be attached via the `cause` attribute for debugging.
    *   Ensure error messages include relevant context (method, path, status code if applicable).

## 3. Configuration

*   **Instance Level:** Configuration primarily happens via the `setup_http_client` method within the Tool's `initialize`. This promotes encapsulation, making each tool instance configure its client.
*   **Per-Request Overrides:** All request helper methods (`http_get`, `http_post`, etc.) will accept `headers:` and `options:` parameters to override the defaults for that specific request.
*   **Excon Defaults:** Leverage `Excon.defaults` for global defaults if needed, but prefer instance-level configuration via `setup_http_client`.
*   **Timeouts:** Encourage setting explicit `read_timeout`, `write_timeout`, and `connect_timeout` via the `options` hash in `setup_http_client`. Consider ADK-specific defaults if none are provided.

## 4. Authentication Integration

*   **Mechanism:** The `HttpClient` module itself will *not* directly manage authentication state or complex flows like OAuth2 interactive steps. It relies on the calling Tool to provide the necessary credentials *per request*.
*   **Credential Injection:**
    *   The calling Tool's `perform_execution` (or equivalent) method is responsible for:
        1.  Determining the required authentication (based on its configuration or context).
        2.  Retrieving the necessary credential value (e.g., API key, Bearer token) from its configuration, the `ToolContext` (session state, potentially decrypted as per `authentication-plan.md`), or via the interactive flow outlined in `authentication-plan.md`.
        3.  Passing the credential to the `HttpClient` helper method via the `headers:` parameter.
    *   **Example (Bearer Token):**
        ```ruby
        # Inside a Tool's execution method
        token = context.get_cached_credential(:access_token) # Simplified example
        response = http_get('/protected/resource', headers: { 'Authorization' => "Bearer #{token}" })
        ```
    *   **Example (API Key in Header):**
        ```ruby
        # Inside a Tool's execution method
        api_key = context.get_configured_credential.api_key # Simplified example
        response = http_get('/data', headers: { 'X-API-Key' => api_key })
        ```
*   **Middleware:** While `excon` supports middleware, avoid building complex authentication logic directly into `HttpClient` middleware for now. The authentication plan places this logic primarily in the ADK core (Runner/Fibers) and the Tool implementations, which seems more flexible for handling diverse auth types and interactive flows. The client's role is to make the HTTP call *with* the provided credentials.
*   **Token Refresh:** Automatic token refresh logic (using refresh tokens) should reside outside the `HttpClient`, likely triggered by the Tool upon receiving a 401 error, as described in the authentication plan. The `HttpClient` will simply execute the requests needed for the refresh flow when called by the Tool.

## 5. Error Handling Details

*   `Excon::Error::Timeout` -> `ADK::ToolTimeoutError`
*   `Excon::Error::Socket`, `Excon::Error::CertificateError` -> `ADK::ToolNetworkError` (or potentially `ADK::ToolCertificateError`)
*   `Excon::Error::HTTPStatusError` (4xx/5xx) -> `ADK::ToolHttpError`. The error should contain the `Excon::Response` object for inspection by the Tool (e.g., to check for 401/403 and trigger re-authentication/refresh).
*   Other `Excon::Error` -> `ADK::ToolError`
*   **Important:** When wrapping `Excon::Error`, the original error **must** be preserved using Ruby's standard exception `cause` mechanism (e.g., `raise ADK::ToolTimeoutError, 'Read timeout', cause: original_excon_error`).

## 6. Usage in Tools

*   **`FunctionTool`:** Custom tools needing HTTP access will `include ADK::Tools::Base::HttpClient`, call `setup_http_client` in `initialize`, and use methods like `http_get`, `http_post` in `perform_execution`, passing auth headers as needed.
*   **`OpenAPIToolset`:** This toolset will likely use the `HttpClient` internally to make requests based on the OpenAPI specification. It will need to integrate with the authentication plan to pass the correct credentials (API Key, Bearer Token based on `securitySchemes`) into the `HttpClient` requests.
*   **`WebhookTool`:** The proposed `WebhookTool` (from `webhooks-plan.md`) explicitly uses `HttpClient`. Its implementation will call `setup_http_client` (likely without a `base_url` as the target URL is dynamic) and use `http_post` in its `perform_execution`, passing the dynamic URL, payload, and optional secret/headers.

## 7. Developer Experience

*   Keep the interface simple: `setup_http_client` and straightforward `http_verb` methods.
*   Rely on `excon`'s robustness for underlying HTTP handling.
*   Provide clear examples in documentation for including the module, configuring it (including logging and timeouts), and making requests with authentication headers.
*   Ensure error messages are informative and include the original error `cause` where applicable.
*   Default logging integration via `ADK.logger` enhances debuggability.

## 8. Testing Strategy

*   **Run Existing Specs:** Before starting, ensure all current project specs pass.
*   **New Specs:** Create new RSpec tests specifically for the `ADK::Tools::Base::HttpClient` module itself (e.g., in `spec/adk/tools/base/http_client_spec.rb`). These specs should test its core logic, such as default merging, request parameter construction (path joining, query string generation, JSON body encoding), and the wrapping of `Excon::Errors` into `ADK::ToolError` subclasses.
*   Use `Excon.stub` for unit testing Tools that include `HttpClient`, mocking responses and verifying request parameters (headers, body, path, query).
*   Integration tests can use tools like `rackup` (as used in `excon`'s own tests) to test against live, local HTTP/S servers for basic connectivity and error handling.
*   **Coverage:** Aim for good test coverage of the new `HttpClient` module and its error handling paths.

## 9. Future Considerations

*   **Advanced Proxy:** While basic proxying is handled by `excon` options, more complex scenarios might require investigation.
*   **Custom Middleware:** Document how users could potentially add custom `excon` middleware if needed, although discourage overriding core ADK functionality this way.
*   **Streaming:** While `excon` supports streaming requests/responses, expose this only if a clear use case emerges in ADK tools, to keep the initial interface simple.

## 10. Relation to Other Plans

*   **Authentication:** This plan relies on the auth system described in `docs/authentication-plan.md` to *provide* credentials, which are then simply injected into headers by the calling tool when using `HttpClient`.
*   **Webhooks:** This client directly enables the implementation of the `WebhookTool` proposed in `docs/webhooks-plan.md`.

**Implementation Note:** As you proceed through the checklist, make frequent, small `git commit`s after each step or logical unit of work. This makes it easier to track progress and roll back if necessary.

## 11. Implementation Checklist

1.  [x] **Add Dependency:** Add `excon` gem to `adk-ruby.gemspec`.
2.  [x] **Define Errors:** Create new error classes (`ADK::ToolError`, `ADK::ToolNetworkError`, `ADK::ToolTimeoutError`, `ADK::ToolHttpError`, `ADK::ToolCertificateError`) in `lib/adk/tool/error.rb`, ensuring they can store a `cause`.
3.  [x] **Create Module:** Create the `ADK::Tools::Base::HttpClient` module file at `lib/adk/tools/base/http_client.rb`.
4.  [x] **Require Dependencies:** Add `require 'excon'` and `require 'json'` etc. within the module file.
5.  [x] **Implement `setup_http_client`:**
    *   [x] Method definition accepting `base_url`, `headers`, `options`.
    *   [x] Store `@http_client = Excon::Connection.new(...)`.
    *   [x] Merge default headers, including custom `User-Agent`.
    *   [x] Implement default logging configuration using `ADK.logger` and `Excon::LoggingInstrumentor` (with override).
    *   [x] Consider/implement ADK-specific default options (timeouts, persistence).
6.  [x] **Implement Request Helpers (`http_get`, `http_post`, etc.):**
    *   [x] Method definitions accepting `path`, `query`, `headers`, `options`, `body` (as applicable).
    *   [x] Merge default parameters with per-request parameters (in `make_request`).
    *   [x] Implement path joining using `URI.join` and handle absolute URLs (in `make_request`).
    *   [x] Implement query string generation (handled by Excon via `:query` key in `make_request`).
    *   [x] Implement automatic JSON encoding for Hash bodies (in `make_request`).
    *   [x] Call the corresponding `@http_client` method (e.g., `@http_client.request(...)` in `make_request`).
7.  [x] **Implement Error Wrapping:**
    *   [x] Add `begin...rescue` blocks around `@http_client` calls (in `make_request`).
    *   [x] Rescue specific `Excon::Error` subclasses.
    *   [x] Raise corresponding `ADK::ToolError` subclasses, preserving the original error via `cause` (where feasible).
8.  [🟡] **Write Specs (`spec/adk/tools/base/http_client_spec.rb`):** (Partially complete - stub verification issues remain for some request helper tests)
    *   [x] Test `setup_http_client` configuration (defaults, overrides, logging).
    *   [x] Test request helper parameter merging (implicitly via tests).
    *   [x] Test path joining logic.
    *   [x] Test query string generation (via stubs).
    *   [x] Test automatic JSON body encoding.
    *   [x] Test error wrapping for each category (Timeout, Socket, HTTPStatus, Certificate, other).
    *   [x] Verify the `cause` is correctly set on wrapped errors (where feasible).
9.  [x] **Refactor Existing Tools (if applicable):** Refactored `CatFacts` tool.
10. [x] **Implement `WebhookTool`:** Use the new `HttpClient` to implement the `WebhookTool` as per `docs/webhooks-plan.md`.
11. [x] **Documentation:** Update ADK documentation with examples of how to use the `HttpClient` module in custom tools. 