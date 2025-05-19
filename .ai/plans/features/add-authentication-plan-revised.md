# Ruby ADK Authentication Implementation Plan (Revised)

This document outlines a plan for implementing an authentication system in the Ruby ADK library, drawing inspiration from the Python ADK's approach while addressing Ruby-specific considerations.

## 1. Goal

To provide a robust and flexible mechanism for ADK tools to handle various authentication schemes (API Keys, OAuth2, OIDC, Service Accounts) required to access protected resources, mirroring the capabilities of the Python ADK while leveraging Ruby's strengths.

## 2. Core Concepts (Ruby Equivalents)

We need to define Ruby classes/modules analogous to the Python ADK's core authentication components:

*   **`Adk::Auth::Scheme` (Abstract Class):** Defines how an API expects credentials. We'll need specific classes inheriting from this for different schemes:
    *   `Adk::Auth::Schemes::APIKey`: For API key authentication (e.g., in header or query param). Corresponds to Python's `APIKey`.
    *   `Adk::Auth::Schemes::HTTPBearer`: For Bearer token authentication. Corresponds to Python's `HTTPBearer`.
    *   `Adk::Auth::Schemes::OAuth2`: Defines OAuth 2.0 flow details (authorization URL, token URL, scopes). Corresponds to Python's `OAuth2`. Needs nested classes for different flows (e.g., `Adk::Auth::Schemes::OAuth2::AuthorizationCodeFlow`).
    *   `Adk::Auth::Schemes::OpenIDConnect`: Defines OIDC details (discovery URL). Corresponds to Python's `OpenIdConnectWithConfig`.
*   **`Adk::Auth::Credential` (Class):** Holds the initial information needed to start authentication (e.g., client ID/secret, API key value, service account key).
    *   `auth_type`: A symbol indicating the type (`:api_key`, `:oauth2`, `:oidc`, `:service_account`, `:http_bearer`). Corresponds to Python's `AuthCredentialTypes`.
    *   Specific attributes based on `auth_type` (e.g., `client_id`, `client_secret`, `api_key`, `service_account_json`, `bearer_token`). Corresponds to nested objects like `OAuth2Auth` in Python.
    *   Environment variable resolution for sensitive values.
*   **`Adk::Auth::Config` (Class):** A container object used during the interactive flow to pass information between the ADK core and the client application. It bundles the `Scheme` and the credential information (which might contain intermediate state like the `auth_uri` or the final `auth_response_uri`). Corresponds to Python's `AuthConfig`.
*   **`Adk::Auth::ExchangedCredential` (Class):** Represents the state of credentials *after* potential exchange or during the interactive flow. Holds the `access_token`, `refresh_token`, `token_type`, `expires_at`, and other relevant information.

## 3. Authentication Flows

### 3.1. Interactive Flow (OAuth/OIDC - Client-Side Handling)

This flow is triggered when a tool requires user interaction for authentication (e.g., login and consent), leveraging Ruby's `Fiber` for async control flow.

1.  **Tool Configuration:** The tool (e.g., an `OpenAPIToolset` instance) is configured with an `Adk::Auth::Scheme` (e.g., `OAuth2`) and an initial `Adk::Auth::Credential` (e.g., containing `client_id`, `client_secret`).
2.  **Authentication Request & Fiber Yield:** When the tool is invoked and needs credentials:
    *   The ADK core (within the `Runner` running inside a `Fiber`) detects the missing/invalid credentials.
    *   It prepares an `Adk::Auth::Config` object containing necessary details (like the constructed `auth_uri` for the provider) and a unique `auth_request_id`.
    *   The `Runner` calls **`Fiber.yield(auth_config_with_request_id)`**. This pauses the agent's execution Fiber and returns the `auth_config_with_request_id` object to the code that started the Fiber (the client application).
3.  **Client Application Handling:**
    *   The client application receives the `auth_config_with_request_id` object yielded from the Fiber.
    *   It extracts the `auth_uri` from the `Adk::Auth::Config`.
    *   It **appends its own `redirect_uri`** (which must be registered with the provider) to the `auth_uri`.
    *   It directs the end-user to this complete URL (e.g., via browser redirect).
4.  **Callback Handling (Client):**
    *   The application has an endpoint (at the `redirect_uri`) that receives the user back from the provider.
    *   The provider appends the `authorization_code` (and potentially `state`) to this callback URL.
    *   The client application captures the *full* callback URL (`auth_response_uri`).
5.  **Sending Auth Response & Fiber Resume:**
    *   The client application prepares an authentication response payload containing:
        *   The original `auth_request_id`.
        *   An updated `Adk::Auth::Config` containing the captured `auth_response_uri` and the `redirect_uri` used.
    *   The client application resumes the paused Fiber using **`fiber.resume(auth_response_payload)`**.
6.  **ADK Token Exchange & Retry:**
    *   Execution resumes within the `Runner`'s Fiber at the point after the `Fiber.yield`.
    *   The `Runner` receives the `auth_response_payload`.
    *   It extracts the `authorization_code` from the `auth_response_uri` within the payload.
    *   Using the `token_url` (from the original `Scheme`), `client_id`, `client_secret`, `redirect_uri`, and `code`, it performs the OAuth token exchange (using the `oauth2` gem).
    *   It securely stores the obtained `access_token` and `refresh_token` in the session state (encrypted, see Section 5).
    *   It automatically retries the original tool call.
7.  **Tool Execution:** The tool now finds the valid token in the session state (via `ToolContext`) and executes the API call successfully.

### 3.2. Custom Tool Flow (FunctionTool - Tool-Side Handling)

For custom tools (`FunctionTool` equivalent) that manage their own authentication logic.

1.  **Tool Context:** The tool's execution method must receive a `ToolContext` object providing access to:
    *   `context.session`: The current `ADK::Session` object, allowing access to mutable `session.state` for caching credentials.
    *   `context.get_auth_response(scheme, credential)`: A method to check if an interactive flow just completed.
    *   `context.request_credential(auth_config)`: A method to initiate the interactive `Fiber.yield` flow if credentials are required.
    *   `context.get_configured_credential(type)`: A method to retrieve the initial credential configuration.
2.  **Logic within the Tool:**
    *   **Check Cache:** Look for valid, cached credentials in `context.session.state[:auth_token_cache][cache_key]`. If valid or refreshable, use them.
    *   **Check Auth Response:** If no valid cached credentials, call `context.get_auth_response(scheme, credential)`. If credentials are returned, cache them and proceed.
    *   **Initiate Auth Request:** If still no credentials, call `context.request_credential(auth_config)`. This triggers the interactive flow via `Fiber.yield`.
    *   **Cache Credentials:** Once valid credentials are obtained, encrypt them using `rbnacl` and store them securely in `context.session.state[:auth_token_cache][cache_key]`.
    *   **Make API Call:** Use the obtained credentials with the HTTP client.
    *   **Return Result:** Return the processed result from the API call.

### 3.3. Non-Interactive Flows (API Key, HTTP Bearer)

These flows apply when the credential is provided directly during configuration and does not require user interaction.

1.  **Configuration:**
    *   The tool is configured with an appropriate `Adk::Auth::Scheme` (e.g., `Adk::Auth::Schemes::APIKey`, `Adk::Auth::Schemes::HTTPBearer`).
    *   The `Adk::Auth::Credential` is provided with the corresponding `auth_type` and credential value or environment variable name.
2.  **Execution:**
    *   The `Fiber.yield`/`resume` mechanism is **not** used for these types.
    *   For toolset tools (e.g., `OpenAPIToolset`), the framework injects the credential into API requests according to the scheme.
    *   For custom tools, they access the credential via `context.get_configured_credential(type)`.
3.  **No Exchange/Refresh via ADK:** The ADK core does not perform token exchanges or refreshes for these types.

### 3.4 Service Account Flow (Non-Interactive Exchange)

This flow applies to credentials like Google Cloud Service Account keys that can be exchanged for access tokens without direct user interaction.

1.  **Configuration:**
    *   The tool is configured with an appropriate `Adk::Auth::Scheme` and a credential with `auth_type: :service_account`.
2.  **Execution & Token Exchange:**
    *   The `Fiber.yield`/`resume` mechanism is **not** used for this type.
    *   When the tool first needs to make an authenticated call, the ADK core performs the token exchange automatically and non-interactively.
3.  **Token Caching & Refresh:**
    *   The obtained access token is securely cached in the session state.
    *   The ADK core automatically handles refreshing the token when needed.
4.  **Tool Usage:**
    *   The tool obtains the valid access token via the `ToolContext` and uses it in API calls.

### 3.5 Error Handling

For comprehensive error handling across all flows:

*   **Invalid Initial Configuration:** Raise errors immediately upon configuration for invalid credentials.
*   **OAuth Provider Interaction Errors:** Capture and propagate provider errors (e.g., `?error=access_denied`).
*   **Token Exchange Failures:** Raise specific errors (e.g., `Adk::Auth::TokenExchangeError`) for exchange failures.
*   **Token Refresh Failures:** Propagate refresh failures with clear error messages.
*   **API Call Auth Errors (401/403):** Detect these in the HTTP client and trigger refresh or raise errors as appropriate.

## 4. Configuration

*   Tools requiring authentication should accept `auth_scheme` (`Adk::Auth::Scheme`) and `auth_credential` (`Adk::Auth::Credential`) during initialization.
*   The toolset should associate these configurations with the tools it generates.
*   Custom tools might define their required authentication internally or receive it during initialization.
*   Configuration should support environment variable resolution for sensitive values.

## 5. Session State & Security

*   The existing `ADK::SessionService::Redis` implementation will be enhanced to store credentials securely.
*   **Security Implementation:**
    *   Sensitive credentials in the session state **must** be encrypted using the `rbnacl` gem.
    *   Use `RbNaCl::SimpleBox` or `RbNaCl::SecretBox` for authenticated encryption.
    *   Encrypt sensitive values **before** storing in Redis.
    *   Add a dedicated authentication token cache in session state (`session.state[:auth_token_cache]`).
    *   Implement key management via environment variables or secure storage integration.
    *   Create helper methods for encryption/decryption to ensure consistent security practices.
*   **Token Lifecycle:**
    *   Store only short-lived access tokens where possible.
    *   Implement automatic refresh using securely stored refresh tokens.
    *   Add token expiration checking and proactive refreshing logic.

## 6. Key Classes/Modules to Implement

*   **Core Authentication Structures:**
    *   `Adk::Auth` (Namespace module)
    *   `Adk::Auth::Scheme` (Abstract base class)
    *   `Adk::Auth::Schemes::APIKey`, `HTTPBearer`, `OAuth2`, `OpenIDConnect` (Concrete scheme classes)
    *   `Adk::Auth::Credential` (Credential container class)
    *   `Adk::Auth::Config` (Authentication flow configuration)
    *   `Adk::Auth::ExchangedCredential` (Token container class)
*   **Error Handling:**
    *   `Adk::Auth::Error` (Base error class)
    *   `Adk::Auth::ConfigurationError` (For invalid initial configuration)
    *   `Adk::Auth::TokenExchangeError` (For exchange failures)
    *   `Adk::Auth::TokenRefreshError` (For refresh failures)
    *   `Adk::Auth::ProviderError` (For provider-specific errors)
*   **Integration Points:**
    *   `Adk::ToolContext` (Enhanced with auth methods)
    *   `Adk::Runner` (Fiber management)
    *   `Adk::SessionService::Redis` (Enhanced with encryption)
    *   `Adk::Auth::Middleware` (Excon middleware for auth header injection)
*   **Security Utilities:**
    *   `Adk::Auth::Encryption` (Helper module for encryption/decryption)
    *   `Adk::Auth::TokenStore` (Secure token storage manager)

## 7. Implementation Priorities & Dependencies

1.  **Base Infrastructure:**
    *   Core authentication classes and interfaces
    *   Encryption utilities for secure storage
    *   Session state enhancements
2.  **Non-Interactive Flows:**
    *   API Key and HTTP Bearer authentication
    *   Integration with Excon and toolsets
3.  **Interactive Flows:**
    *   Fiber-based OAuth/OIDC flow
    *   Token exchange and refresh logic
4.  **Advanced Features:**
    *   Service account support
    *   Token expiration management
    *   Error handling refinements

## 8. Testing Strategy

*   **Unit Tests:**
    *   Test each authentication scheme class
    *   Test credential management and resolution
    *   Test encryption/decryption utilities
*   **Integration Tests:**
    *   Test token exchange with mock providers
    *   Test Fiber yields and resumes
    *   Test full authentication flows
*   **Security Tests:**
    *   Verify encryption of sensitive data
    *   Test key rotation and secure erasure
*   **Mock Services:**
    *   Create mock OAuth provider for testing without real credentials

## 9. Dependencies

*   **Required Gems:**
    *   `excon` - HTTP client for API requests
    *   `oauth2` - OAuth 2.0 client library
    *   `jwt` - JSON Web Token support for OIDC/Service Accounts
    *   `rbnacl` - Encryption library for secure credential storage
    *   `redis` - Redis client for session storage

## 10. Future Enhancements

*   **Secret Manager Integration:** Support integration with cloud secret managers
*   **Per-Operation Auth:** Allow authentication to be configured per-operation within a toolset
*   **Custom Auth Schemes:** Support for user-defined authentication schemes
*   **Async Flow Improvements:** Better integration with Ruby's async ecosystem 