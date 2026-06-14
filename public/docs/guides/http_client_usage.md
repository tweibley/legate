# Using the Legate HttpClient Module

The `Legate::Tools::Base::HttpClient` module provides a standardized and robust way for custom Legate tools to make HTTP(S) requests. It's built on the `excon` gem, offering features like persistent connections, configurable timeouts, and middleware support (though used minimally by default).

This guide explains how to integrate and use the `HttpClient` in your tools.

## 1. Including and Setting Up the HttpClient

To use the `HttpClient`, include the module in your tool class and call `setup_http_client` within your tool's `initialize` method.

```ruby
require 'legate/tool'
require 'legate/tools/base/http_client' # Include the HttpClient module

class MyCustomHttpTool < Legate::Tool
  include Legate::Tools::Base::HttpClient # Include the module

  tool_description 'A tool that makes HTTP calls.'

  def initialize(**options)
    super(**options)

    # Setup the HTTP client
    setup_http_client(
      base_url: 'https://api.example.com/v1/',
      headers: { 'X-Custom-Default-Header' => 'MyValue' },
      options: {
        persistent: true,
        connect_timeout: 5, # seconds
        read_timeout: 10,   # seconds
        write_timeout: 10   # seconds
      }
    )
  end

  # ... tool methods ...
end
```

### `setup_http_client(base_url:, headers: {}, options: {})`

This method initializes and configures the underlying `Excon::Connection`.

*   **`base_url:`** (String, required): The base URL for the API your tool will interact with (e.g., `https://api.example.com/v1/`). It must be a valid HTTP or HTTPS URL.
*   **`headers:`** (Hash, optional): Default HTTP headers to be sent with every request made by this client instance. These can be overridden on a per-request basis.
    *   A default `User-Agent` header (e.g., `Legate-Ruby/0.1.0 Excon/0.104.0`) is automatically added unless you provide your own.
*   **`options:`** (Hash, optional): Options passed directly to `Excon.new` for configuring the connection. Common options include:
    *   `persistent:` (Boolean): Whether to use persistent connections (default: `true`).
    *   `connect_timeout:`, `read_timeout:`, `write_timeout:` (Numeric): Connection, read, and write timeouts in seconds (defaults: `5`, `15`, `15` respectively).
    *   `ssl_verify_peer:` (Boolean): Whether to verify the SSL certificate (default: `true`).
    *   `proxy:` (String): Proxy server URL.
    *   `instrumentor:` Allows specifying a custom Excon instrumentor. By default, it uses an internal `QuietInstrumentor` (a subclass of `Excon::StandardInstrumentor`) that logs only errors, keeping normal request/response traffic out of the logs.

## 2. Making HTTP Requests

Once set up, you can use the provided helper methods to make HTTP requests:

*   `http_get(path, query: {}, headers: {}, options: {})`
*   `http_head(path, query: {}, headers: {}, options: {})` - Returns headers only, no body (efficient for status checks)
*   `http_post(path, body: nil, query: {}, headers: {}, options: {})`
*   `http_put(path, body: nil, query: {}, headers: {}, options: {})`
*   `http_delete(path, query: {}, headers: {}, options: {})`

### Common Parameters

*   **`path`** (String): The path for the request.
    *   If it's a relative path (e.g., `users`, `/users`), it will be joined with the `base_url` provided during setup.
    *   If it's an absolute URL (e.g., `https://another.api.com/data`), that URL will be used directly for the request, and a temporary Excon client will be used with the same connection options defined in `setup_http_client`.
*   **`query:`** (Hash, optional): A hash of query parameters to be appended to the URL (e.g., `{ sort: 'name', limit: 10 }`).
*   **`headers:`** (Hash, optional): Headers specific to this request. These will be merged with (and can override) the default headers set in `setup_http_client`.
*   **`options:`** (Hash, optional): Excon request options specific to this request (e.g., to override timeouts for a single long-running request).
*   **`body:`** (Object, optional, for `http_post`, `http_put`): The request body.
    *   If `body` is a `Hash`, it will typically be automatically encoded as a JSON string, and the `Content-Type` header will be set to `application/json; charset=utf-8` unless a `Content-Type` is explicitly provided in the `headers:` parameter for the request.
    *   If `body` is already a `String`, it will be sent as-is. You should ensure it's correctly encoded and set the appropriate `Content-Type` header if needed.

### Example: Making a GET Request

```ruby
def fetch_user_data(user_id)
  response = http_get("users/#{user_id}", query: { include_details: true })
  # Process the response (see "Handling Responses" below)
  JSON.parse(response.body)
rescue Legate::ToolHttpError => e
  Legate.logger.error "HTTP error fetching user #{user_id}: #{e.message}, Status: #{e.response&.status}"
  # Handle specific statuses, e.g., e.response.status == 404
  nil
rescue Legate::ToolError => e
  Legate.logger.error "Tool error fetching user #{user_id}: #{e.message}"
  nil
end
```

### Example: Making a HEAD Request

HEAD requests are useful for checking if a resource exists or getting metadata without downloading the full response body. This is efficient for status checks or verifying URLs.

```ruby
def check_url_status(url)
  # HEAD requests work with absolute URLs too
  response = http_head(url)
  {
    status_code: response.status,
    content_type: response.headers['Content-Type'],
    content_length: response.headers['Content-Length'],
    reachable: (200..399).cover?(response.status)
  }
rescue Legate::ToolHttpError => e
  # For a status checker, non-2xx responses may be valid results
  # You can extract the response from the error
  if e.response
    { status_code: e.response.status, reachable: false }
  else
    { status_code: nil, reachable: false, error: e.message }
  end
rescue Legate::ToolNetworkError, Legate::ToolTimeoutError => e
  { status_code: nil, reachable: false, error: e.message }
end
```

## 3. Handling Responses

The request helper methods (`http_get`, `http_head`, etc.) return an `Excon::Response` object upon a successful request (typically HTTP 2xx status codes).

You can access various parts of the response:

*   `response.status` (Integer): The HTTP status code.
*   `response.body` (String): The response body. You may need to parse it (e.g., `JSON.parse(response.body)`).
*   `response.headers` (Hash): A hash of response headers.

```ruby
response = http_get('status')
if response.status == 200
  Legate.logger.info "API Status: #{response.body}"
  content_type = response.headers['Content-Type']
  Legate.logger.info "Content-Type: #{content_type}"
else
  Legate.logger.warn "Unexpected status: #{response.status}"
end
```
If an HTTP error status (4xx or 5xx) is returned by the server, an `Legate::ToolHttpError` will be raised (see Error Handling).

## 4. Error Handling

The `HttpClient` module wraps common `Excon::Error` exceptions into more specific `Legate::ToolError` subclasses. This provides a consistent error handling experience for tools.

Always include `begin...rescue` blocks when making HTTP calls.

*   **`Legate::ToolTimeoutError`**: Raised for request timeouts (corresponds to `Excon::Error::Timeout`).
*   **`Legate::ToolNetworkError`**: Raised for socket or underlying network issues (corresponds to `Excon::Error::Socket`).
*   **`Legate::ToolCertificateError`**: Raised for SSL certificate errors (corresponds to `Excon::Error::CertificateError`).
*   **`Legate::ToolHttpError`**: Raised for HTTP status codes in the 4xx and 5xx ranges (corresponds to `Excon::Error::HTTPStatusError`).
    *   You can access the `Excon::Response` object via `e.response` on this error (e.g., `e.response.status`, `e.response.body`).
*   **`Legate::ToolError`**: A general error class used for other Excon errors or issues within the HttpClient module itself (e.g., failed JSON encoding, invalid base URL).

When an `Legate::ToolError` is raised due to an underlying `Excon::Error`, the original Excon error is preserved in the `cause` attribute of the Legate error. This is useful for debugging.

```ruby
begin
  response = http_post('submit_data', body: { key: 'value' })
  # ... process response ...
rescue Legate::ToolTimeoutError => e
  Legate.logger.error "Request timed out: #{e.message}"
  # Optionally inspect e.cause if needed
rescue Legate::ToolHttpError => e
  Legate.logger.error "HTTP Error: #{e.message} (Status: #{e.response&.status})"
  if e.response&.status == 401
    Legate.logger.warn "Authentication required or token expired."
    # Potentially trigger re-authentication logic
  end
  Legate.logger.debug "Response body from error: #{e.response&.body}"
rescue Legate::ToolNetworkError => e
  Legate.logger.error "Network error: #{e.message}"
rescue Legate::ToolError => e # Catch-all for other HttpClient or generic Legate tool errors
  Legate.logger.error "A tool error occurred: #{e.message}"
  Legate.logger.debug "Original cause: #{e.cause.inspect}" if e.cause
end
```

## 5. Authentication

The `HttpClient` module itself is unopinionated about authentication mechanisms. It **does not** manage authentication state (like tokens) or complex authentication flows (like OAuth2).

Your tool is responsible for:
1.  Determining the required authentication method (e.g., API key, Bearer token).
2.  Retrieving the necessary credentials. This might come from the tool's configuration, the `ToolContext` (session state, possibly using the Legate's credential management features), or an interactive flow.
3.  Injecting the credentials into the HTTP request, typically via the `headers:` parameter of the request helper methods.

### Example: Bearer Token Authentication

```ruby
# Assume 'token' is retrieved by the tool
auth_headers = { 'Authorization' => "Bearer #{token}" }
response = http_get('/protected/resource', headers: auth_headers)
```

### Example: API Key in Header

```ruby
# Assume 'api_key' is retrieved by the tool
auth_headers = { 'X-Api-Key' => api_key }
response = http_get('/data', headers: auth_headers)
```

Refer to the Legate's authentication documentation for details on managing and retrieving credentials within tools.

## 6. Full Example

Here's a simple tool that fetches a random cat fact using the `HttpClient`.

```ruby
require 'legate/tool'
require 'legate/tools/base/http_client'
require 'json'

module Legate
  module Tools
    # Tool name :cat_fact_tool is inferred from the class name.
    class CatFactTool < Legate::Tool
      include Legate::Tools::Base::HttpClient

      tool_description 'Fetches a random cat fact.'
      # No parameters needed for this tool.

      def initialize(**options)
        super(**options)
        setup_http_client(
          base_url: 'https://catfact.ninja/',
          options: { read_timeout: 5 } # Short timeout for this API
        )
      end

      private

      # perform_execution takes two positional args (params, context) and must
      # return a status Hash: { status: :success, result: ... } or
      # { status: :error, error_message: ... }.
      def perform_execution(_params, _context)
        Legate.logger.info 'Fetching a cat fact...'
        response = http_get('fact') # Path is relative to base_url
        parsed_body = JSON.parse(response.body)
        fact = parsed_body['fact']
        Legate.logger.info "Retrieved cat fact: #{fact}"
        { status: :success, result: fact }
      rescue Legate::ToolHttpError => e
        Legate.logger.error "HTTP error fetching cat fact: #{e.message}, Status: #{e.response&.status}"
        { status: :error, error_message: "HTTP #{e.response&.status} - #{e.message}" }
      rescue Legate::ToolTimeoutError => e
        Legate.logger.error "Timeout fetching cat fact: #{e.message}"
        { status: :error, error_message: 'Request timed out.' }
      rescue Legate::ToolError => e
        Legate.logger.error "Tool error fetching cat fact: #{e.message}"
        { status: :error, error_message: e.message }
      rescue JSON::ParserError => e
        Legate.logger.error "Failed to parse cat fact response: #{e.message}"
        { status: :error, error_message: 'Could not parse response from cat fact API.' }
      end
    end
  end
end
```

> **Note:** Rather than returning the result hash, a tool may also raise a `Legate::ToolError` subclass (e.g., on a failed HTTP request) and let the Legate runtime convert it into a standard error event. The built-in `Legate::Tools::CatFacts` tool uses that approach.

This guide should help you effectively use the `Legate::Tools::Base::HttpClient` module to build powerful, network-enabled tools within the Legate framework. 