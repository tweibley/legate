# Authentication Web UI Integration

## Overview

The Legate Ruby library provides integration between the authentication system and the Web UI, enabling interactive authentication flows directly from the web interface. This guide explains how to integrate authentication with the Web UI and implement visual flows for authentication schemes like OAuth2 and OpenID Connect.

## Key Features

- Authentication status indicators in the Web UI
- Interactive login flows for OAuth2 and OIDC
- Token management interface for viewing and revoking tokens
- Secure credential storage in the browser
- Authentication debugging panels

## Web UI Authentication Components

### Authentication Status Indicator

The Legate Web UI includes an authentication status indicator that shows the current authentication state for tools requiring authentication:

```html
<!-- Authentication status indicator component -->
<div class="auth-status">
  <span class="auth-status-icon authenticated"></span>
  <span class="auth-status-text">Authenticated</span>
</div>
```

### Login Interface

The Web UI provides a login interface for initiating authentication flows:

```html
<!-- Login button for OAuth2 authentication -->
<button class="login-button" data-auth-scheme="oauth2">
  Log in with OAuth2
</button>
```

### Token Information Display

The Web UI includes a token information display for viewing active tokens:

```html
<!-- Token information display -->
<div class="token-info">
  <div class="token-status">
    <span class="label">Status:</span>
    <span class="value">Valid</span>
  </div>
  <div class="token-expiry">
    <span class="label">Expires:</span>
    <span class="value">2023-12-31 23:59:59 UTC</span>
  </div>
  <div class="token-scopes">
    <span class="label">Scopes:</span>
    <span class="value">read write</span>
  </div>
</div>
```

## Interactive Authentication Flows

### OAuth2 Authentication Flow

The Web UI implements the OAuth2 authorization code flow with the following steps:

1. User clicks the login button for a tool requiring OAuth2 authentication
2. The Web UI displays a login popup or redirects to the OAuth2 provider
3. User completes authentication on the provider's site
4. The provider redirects back to the Legate callback URL
5. The Web UI captures the authorization code and exchanges it for tokens
6. The Web UI resumes the tool execution with the obtained tokens

```javascript
// JavaScript for handling OAuth2 authentication flow
function initiateOAuth2Flow(authConfig) {
  // Generate and store state parameter to prevent CSRF attacks
  const state = generateSecureRandomString();
  sessionStorage.setItem('oauth2_state', state);
  
  // Construct the authorization URL
  const authUrl = new URL(authConfig.authorizationUrl);
  authUrl.searchParams.append('client_id', authConfig.clientId);
  authUrl.searchParams.append('redirect_uri', authConfig.redirectUri);
  authUrl.searchParams.append('response_type', 'code');
  authUrl.searchParams.append('state', state);
  if (authConfig.scopes) {
    authUrl.searchParams.append('scope', authConfig.scopes.join(' '));
  }
  
  // Open the authorization URL in a popup window
  window.open(authUrl.toString(), 'oauth2_popup', 'width=600,height=700');
}
```

### OAuth2 Callback Handling

The Web UI includes a callback endpoint for handling OAuth2 redirects:

```ruby
# Ruby route for handling OAuth2 callbacks
get '/auth/callback' do
  # Verify state parameter to prevent CSRF attacks
  client_state = request.params['state']
  server_state = session[:oauth2_state]
  halt 403, 'Invalid state parameter' unless client_state && client_state == server_state
  
  # Get the authorization code from the callback
  code = request.params['code']
  halt 400, 'Missing authorization code' unless code
  
  # Store the authorization code in the session
  session[:auth_code] = code
  session[:auth_response_uri] = request.url
  
  # Close the popup window and notify the parent window
  <<-HTML
    <script>
      window.opener.postMessage({ type: 'auth_callback', code: '#{code}' }, window.location.origin);
      window.close();
    </script>
  HTML
end
```

## Token Management

### Token Management Interface

The Web UI provides a token management interface for viewing and managing active tokens:

```html
<!-- Token management interface -->
<div class="token-management">
  <h2>Active Tokens</h2>
  <table class="token-table">
    <thead>
      <tr>
        <th>API</th>
        <th>Status</th>
        <th>Expires</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>Google Drive API</td>
        <td>Valid</td>
        <td>2023-12-31 23:59:59 UTC</td>
        <td>
          <button class="refresh-token-button">Refresh</button>
          <button class="revoke-token-button">Revoke</button>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

### Token Refresh

The Web UI allows users to manually refresh tokens:

```javascript
// JavaScript for handling token refresh
async function refreshToken(credentialId) {
  try {
    const response = await fetch('/api/auth/refresh', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ credential_id: credentialId })
    });
    
    if (!response.ok) {
      throw new Error('Failed to refresh token');
    }
    
    const result = await response.json();
    updateTokenDisplay(result.tokens);
    showNotification('Token refreshed successfully');
  } catch (error) {
    showErrorNotification('Failed to refresh token: ' + error.message);
  }
}
```

### Token Revocation

The Web UI allows users to revoke tokens:

```javascript
// JavaScript for handling token revocation
async function revokeToken(credentialId) {
  if (!confirm('Are you sure you want to revoke this token? You will need to authenticate again.')) {
    return;
  }
  
  try {
    const response = await fetch('/api/auth/revoke', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ credential_id: credentialId })
    });
    
    if (!response.ok) {
      throw new Error('Failed to revoke token');
    }
    
    updateTokenDisplay(null);
    showNotification('Token revoked successfully');
  } catch (error) {
    showErrorNotification('Failed to revoke token: ' + error.message);
  }
}
```

## Security Features

### Secure Credential Storage

The Web UI securely stores authentication credentials in the browser:

```javascript
// JavaScript for secure credential storage
class SecureStorage {
  constructor() {
    // Initialize secure storage
  }
  
  // Store sensitive data securely
  async store(key, value) {
    // Use browser's Web Crypto API to encrypt data
    const encryptedData = await this.encrypt(JSON.stringify(value));
    localStorage.setItem(key, encryptedData);
  }
  
  // Retrieve and decrypt sensitive data
  async retrieve(key) {
    const encryptedData = localStorage.getItem(key);
    if (!encryptedData) return null;
    
    try {
      const decryptedData = await this.decrypt(encryptedData);
      return JSON.parse(decryptedData);
    } catch (error) {
      console.error('Failed to decrypt data:', error);
      return null;
    }
  }
  
  // Encryption/decryption methods
  // ...
}
```

### CSRF Protection

The Web UI implements CSRF protection for authentication flows:

```javascript
// JavaScript for CSRF protection
function generateSecureRandomString(length = 32) {
  const array = new Uint8Array(length);
  window.crypto.getRandomValues(array);
  return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
}
```

## Developer Tools

### Authentication Debugging Panel

The Web UI includes an authentication debugging panel for troubleshooting:

```html
<!-- Authentication debugging panel -->
<div class="auth-debugging-panel">
  <h2>Authentication Debugging</h2>
  <div class="debug-section">
    <h3>Current Authentication State</h3>
    <pre id="auth-state-debug"></pre>
  </div>
  <div class="debug-section">
    <h3>Authentication Logs</h3>
    <pre id="auth-logs-debug"></pre>
  </div>
  <div class="debug-actions">
    <button id="clear-auth-logs">Clear Logs</button>
    <button id="copy-auth-logs">Copy Logs</button>
    <button id="clear-auth-tokens">Clear All Tokens</button>
  </div>
</div>
```

### Authentication Flow Visualization

The Web UI provides a visualization of the authentication flow:

```html
<!-- Authentication flow visualization -->
<div class="auth-flow-visualization">
  <div class="flow-step" data-step="1">
    <div class="step-number">1</div>
    <div class="step-description">Client requests protected resource</div>
  </div>
  <div class="flow-arrow">→</div>
  <div class="flow-step" data-step="2">
    <div class="step-number">2</div>
    <div class="step-description">Legate yields for authentication</div>
  </div>
  <div class="flow-arrow">→</div>
  <div class="flow-step active" data-step="3">
    <div class="step-number">3</div>
    <div class="step-description">User authenticates with provider</div>
  </div>
  <div class="flow-arrow">→</div>
  <div class="flow-step" data-step="4">
    <div class="step-number">4</div>
    <div class="step-description">Legate exchanges code for tokens</div>
  </div>
  <div class="flow-arrow">→</div>
  <div class="flow-step" data-step="5">
    <div class="step-number">5</div>
    <div class="step-description">Legate resumes with valid tokens</div>
  </div>
</div>
```

## Integration with Legate Core

### A Web UI Authentication Coordinator (illustrative)

Legate does not ship a `WebUIAuthenticationCoordinator` class. The pattern below
is an **illustrative coordinator you implement yourself** to bridge your web app
and the core `Legate::Auth::Config` flow. It uses the real `Config` API:
`config.auth_request_id`, `config.build_authorization_uri(redirect_uri, state)`,
`config.scheme.scheme_type`, and setting `config.response_uri` on the callback.

```ruby
# Your own coordinator class (not provided by Legate)
class WebUIAuthenticationCoordinator
  def initialize(app)
    @app = app
  end

  def handle_auth_request(auth_config)
    # Build the authorization URI (this generates and returns the state)
    state = SecureRandom.hex(16)
    auth_uri = auth_config.build_authorization_uri(@app.url('/auth/callback'), state)
    @app.session[:oauth2_state] = auth_config.state

    {
      auth_request_id: auth_config.auth_request_id,
      auth_type: auth_config.scheme.scheme_type,
      authorization_url: auth_uri,
      redirect_uri: @app.url('/auth/callback'),
      scopes: auth_config.scheme.scopes,
      state: auth_config.state
    }
  end

  def handle_auth_response(auth_config, params)
    # Set the response URI on the original request config, then exchange
    auth_config.response_uri = params[:auth_response_uri]
    auth_config
  end
end
```

## Complete Example: OAuth2 Authentication in Web UI

Here's a complete example of implementing OAuth2 authentication in the Legate Web UI:

```ruby
# Server-side route for handling authentication requests
post '/api/auth/request' do
  content_type :json
  
  # Get the authentication configuration from the request
  auth_config = session[:auth_config]
  halt 400, { error: 'No authentication request pending' }.to_json unless auth_config
  
  # Prepare client-side configuration using your own coordinator
  coordinator = WebUIAuthenticationCoordinator.new(self)
  client_config = coordinator.handle_auth_request(auth_config)
  
  client_config.to_json
end

# Server-side route for handling authentication responses
post '/api/auth/response' do
  content_type :json
  
  # Get parameters from the request
  params = JSON.parse(request.body.read, symbolize_names: true)
  
  # Validate the parameters
  halt 400, { error: 'Missing auth_request_id' }.to_json unless params[:auth_request_id]
  halt 400, { error: 'Missing auth_response_uri' }.to_json unless params[:auth_response_uri]
  
  # Handle the authentication response using your own coordinator
  coordinator = WebUIAuthenticationCoordinator.new(self)
  auth_config = session[:auth_config]
  auth_response = coordinator.handle_auth_response(auth_config, params)
  
  # Store the response in the session for the next step in your flow
  session[:auth_response] = auth_response
  
  { success: true }.to_json
end
```

With corresponding client-side JavaScript:

```javascript
// Function to handle authentication requests from the server
async function handleAuthRequest() {
  try {
    const response = await fetch('/api/auth/request', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    if (!response.ok) {
      throw new Error('Failed to get authentication configuration');
    }
    
    const authConfig = await response.json();
    
    // Open the authorization popup
    initiateOAuth2Flow(authConfig);
  } catch (error) {
    showErrorNotification('Authentication error: ' + error.message);
  }
}

// Function to handle authentication callbacks
async function handleAuthCallback(code, state) {
  // Get the stored auth config
  const authConfig = JSON.parse(sessionStorage.getItem('auth_config'));
  if (!authConfig) {
    showErrorNotification('No authentication in progress');
    return;
  }
  
  // Verify state parameter
  if (state !== authConfig.state) {
    showErrorNotification('Invalid state parameter');
    return;
  }
  
  // Send the authentication response to the server
  try {
    const response = await fetch('/api/auth/response', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        auth_request_id: authConfig.auth_request_id,
        auth_response_uri: `${authConfig.redirect_uri}?code=${code}&state=${state}`,
        redirect_uri: authConfig.redirect_uri
      })
    });
    
    if (!response.ok) {
      throw new Error('Failed to send authentication response');
    }
    
    showNotification('Authentication successful');
    
    // Clear the stored auth config
    sessionStorage.removeItem('auth_config');
    
    // Reload the tools to reflect the authenticated state
    loadTools();
  } catch (error) {
    showErrorNotification('Authentication error: ' + error.message);
  }
}

// Event listener for authentication callbacks from popup window
window.addEventListener('message', function(event) {
  if (event.origin !== window.location.origin) return;
  
  if (event.data.type === 'auth_callback' && event.data.code) {
    handleAuthCallback(event.data.code, event.data.state);
  }
});
```

## Related Topics

- [OAuth2 Authentication Guide](./oauth2)
- [OpenID Connect Guide](./oidc)
- [Token Lifecycle Management](./token_lifecycle)
- [Legate Web UI Documentation](../../web_ui/legate_web_ui)