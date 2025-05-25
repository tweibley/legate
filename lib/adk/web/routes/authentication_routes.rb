# File: lib/adk/web/routes/authentication_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AuthenticationRoutes
      def self.registered(app)
        # Add helper methods to the app
        app.helpers do
          # Helper method to get a description for a scheme
          def get_scheme_description(scheme)
            case scheme.scheme_type
            when :api_key
              "Simple API key authentication for services that use API keys in headers or query parameters"
            when :http_bearer
              "HTTP Bearer token authentication and basic auth support"
            when :oauth2
              "OAuth2 authorization code flow for secure third-party authentication"
            when :oidc, :openid_connect
              "OpenID Connect authentication extending OAuth2 with identity information"
            when :service_account
              "Service account authentication with automatic token exchange"
            when :google_service_account
              "Google Cloud service account authentication with JSON key files"
            else
              "Authentication scheme of type: #{scheme.scheme_type}"
            end
          end

          # Helper method to get a description for a credential
          def get_credential_description(credential)
            case credential.auth_type
            when :api_key
              "API key credential for service authentication"
            when :oauth2, :oidc
              "OAuth2/OIDC client credentials for authorization flows"
            when :service_account, :google_service_account
              "Service account credentials for automated authentication"
            when :http_bearer
              "Bearer token or basic auth credentials"
            else
              "Credential of type: #{credential.auth_type}"
            end
          end

          # Helper method to get masked credential information for display
          def get_masked_credential_info(credential)
            info_parts = []
            
            # Check for common credential fields and mask them appropriately
            if credential[:api_key, resolve_env: false]
              masked_key = mask_sensitive_value(credential[:api_key, resolve_env: false])
              info_parts << "API Key: #{masked_key}"
            end
            
            if credential[:client_id, resolve_env: false]
              info_parts << "Client ID: #{credential[:client_id, resolve_env: false]}"
            end
            
            if credential[:client_secret, resolve_env: false]
              masked_secret = mask_sensitive_value(credential[:client_secret, resolve_env: false])
              info_parts << "Client Secret: #{masked_secret}"
            end
            
            if credential[:bearer_token, resolve_env: false]
              masked_token = mask_sensitive_value(credential[:bearer_token, resolve_env: false])
              info_parts << "Bearer Token: #{masked_token}"
            end
            
            if credential[:username, resolve_env: false]
              info_parts << "Username: #{credential[:username, resolve_env: false]}"
            end
            
            if credential[:password, resolve_env: false]
              info_parts << "Password: #{mask_sensitive_value(credential[:password, resolve_env: false])}"
            end
            
            info_parts.empty? ? "No displayable information" : info_parts.join(", ")
          end

          # Helper method to mask sensitive values for display
          def mask_sensitive_value(value)
            return "[Not Set]" if value.nil? || value.empty?
            
            value_str = value.to_s
            return "[Too Short]" if value_str.length < 4
            
            # Show first 3 and last 3 characters with asterisks in between
            "#{value_str[0..2]}***#{value_str[-3..-1]}"
          end

          # Helper method to get scheme configuration fields
          def get_scheme_config_fields(scheme_type)
            case scheme_type.to_sym
            when :api_key
              []  # API Key scheme has no configuration
            when :http_bearer
              []  # HTTP Bearer scheme has no configuration
            when :oauth2
              [
                { name: 'authorization_url', type: 'url', required: true, label: 'Authorization URL' },
                { name: 'token_url', type: 'url', required: true, label: 'Token URL' },
                { name: 'scopes', type: 'text', required: false, label: 'Scopes (space-separated)' },
                { name: 'use_pkce', type: 'checkbox', required: false, label: 'Use PKCE' },
                { name: 'revocation_url', type: 'url', required: false, label: 'Revocation URL' }
              ]
            when :oidc, :openid_connect
              [
                { name: 'authorization_url', type: 'url', required: true, label: 'Authorization URL' },
                { name: 'token_url', type: 'url', required: true, label: 'Token URL' },
                { name: 'userinfo_url', type: 'url', required: false, label: 'UserInfo URL' },
                { name: 'scopes', type: 'text', required: false, label: 'Scopes (space-separated)' },
                { name: 'use_pkce', type: 'checkbox', required: false, label: 'Use PKCE' }
              ]
            when :service_account
              [
                { name: 'token_url', type: 'url', required: true, label: 'Token URL' },
                { name: 'scopes', type: 'text', required: false, label: 'Scopes (space-separated)' }
              ]
            when :google_service_account
              [
                { name: 'scopes', type: 'text', required: false, label: 'Scopes (space-separated)' }
              ]
            else
              []
            end
          end

          # Helper method to get current scheme configuration
          def get_scheme_current_config(scheme)
            config = {}
            case scheme.scheme_type
            when :oauth2, :oidc, :openid_connect
              config['authorization_url'] = scheme.authorization_url if scheme.respond_to?(:authorization_url)
              config['token_url'] = scheme.token_url if scheme.respond_to?(:token_url)
              config['scopes'] = scheme.scopes.join(' ') if scheme.respond_to?(:scopes) && scheme.scopes
              config['use_pkce'] = scheme.use_pkce if scheme.respond_to?(:use_pkce)
              config['revocation_url'] = scheme.revocation_url if scheme.respond_to?(:revocation_url)
              if scheme.respond_to?(:userinfo_url)
                config['userinfo_url'] = scheme.userinfo_url
              end
            when :service_account, :google_service_account
              config['token_url'] = scheme.token_url if scheme.respond_to?(:token_url)
              config['scopes'] = scheme.scopes.join(' ') if scheme.respond_to?(:scopes) && scheme.scopes
            end
            config
          end

          # Helper method to get compatible credential types for a scheme
          def get_compatible_credential_types(scheme_type)
            case scheme_type.to_sym
            when :api_key
              ['api_key']
            when :http_bearer
              ['http_bearer', 'bearer_token']
            when :oauth2, :oidc, :openid_connect
              ['oauth2', 'oidc']
            when :service_account, :google_service_account
              ['service_account', 'google_service_account']
            else
              []
            end
          end

          # Helper method to get credential configuration fields
          def get_credential_config_fields(auth_type)
            case auth_type.to_sym
            when :api_key
              [
                { name: 'api_key', type: 'password', required: true, label: 'API Key', placeholder: 'Enter your API key' },
                { name: 'location', type: 'select', required: false, label: 'Location', options: ['header', 'query', 'cookie'], default: 'header' },
                { name: 'name', type: 'text', required: false, label: 'Parameter Name', placeholder: 'X-API-Key' }
              ]
            when :http_bearer
              [
                { name: 'bearer_token', type: 'password', required: true, label: 'Bearer Token', placeholder: 'Enter bearer token' }
              ]
            when :oauth2, :oidc
              [
                { name: 'client_id', type: 'text', required: true, label: 'Client ID', placeholder: 'Enter client ID' },
                { name: 'client_secret', type: 'password', required: true, label: 'Client Secret', placeholder: 'Enter client secret' },
                { name: 'redirect_uri', type: 'url', required: false, label: 'Redirect URI', placeholder: 'https://your-app.com/callback' },
                { name: 'scopes', type: 'text', required: false, label: 'Scopes (space-separated)', placeholder: 'read write' }
              ]
            when :service_account
              [
                { name: 'client_email', type: 'email', required: true, label: 'Client Email', placeholder: 'service-account@project.iam.gserviceaccount.com' },
                { name: 'private_key', type: 'textarea', required: true, label: 'Private Key', placeholder: '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----' },
                { name: 'project_id', type: 'text', required: false, label: 'Project ID', placeholder: 'your-project-id' }
              ]
            when :google_service_account
              [
                { name: 'service_account_key', type: 'textarea', required: true, label: 'Service Account Key (JSON)', placeholder: '{"type": "service_account", "project_id": "..."}' }
              ]
            when :basic
              [
                { name: 'username', type: 'text', required: true, label: 'Username', placeholder: 'Enter username' },
                { name: 'password', type: 'password', required: true, label: 'Password', placeholder: 'Enter password' }
              ]
            else
              []
            end
          end

          # Helper method to get current credential configuration (masked)
          def get_credential_current_config(credential)
            config = {}
            
            # Get all attributes but mask sensitive ones
            credential.to_h(resolve_env: false).each do |key, value|
              next if key == :auth_type
              
              if sensitive_credential_field?(key)
                config[key.to_s] = mask_sensitive_value(value)
              else
                config[key.to_s] = value
              end
            end
            
            config
          end

          # Helper method to check if a credential field is sensitive
          def sensitive_credential_field?(field_name)
            sensitive_fields = %i[api_key client_secret bearer_token password private_key service_account_key token]
            sensitive_fields.include?(field_name.to_sym)
          end

          # Helper method to get compatible schemes for a credential type
          def get_compatible_schemes_for_credential(auth_type)
            auth_manager = ADK::Auth::Manager.instance
            schemes = auth_manager.instance_variable_get(:@schemes) || {}
            
            compatible_schemes = schemes.select do |scheme_name, scheme|
              case auth_type.to_sym
              when :api_key
                scheme.scheme_type == :api_key
              when :http_bearer
                scheme.scheme_type == :http_bearer
              when :oauth2, :oidc
                [:oauth2, :oidc, :openid_connect].include?(scheme.scheme_type)
              when :service_account, :google_service_account
                [:service_account, :google_service_account].include?(scheme.scheme_type)
              when :basic
                scheme.scheme_type == :http_bearer
              else
                false
              end
            end
            
            compatible_schemes.keys
          end

          # Helper method to get mapping configuration fields
          def get_mapping_config_fields
            [
              { name: 'pattern', type: 'text', required: true, label: 'URL Pattern', placeholder: 'e.g. https://api.example.com/v1/* or ^https://.*\\.example\\.com/.*$' },
              { name: 'pattern_type', type: 'select', required: true, label: 'Pattern Type', options: ['string', 'regex'], default: 'string' },
              { name: 'scheme_name', type: 'select', required: true, label: 'Authentication Scheme' },
              { name: 'credential_name', type: 'select', required: true, label: 'Credential' },
              { name: 'priority', type: 'number', required: false, label: 'Priority', placeholder: '1' },
              { name: 'active', type: 'checkbox', required: false, label: 'Active', default: true }
            ]
          end

          # Helper to validate a mapping pattern
          def valid_mapping_pattern?(pattern, pattern_type)
            return false if pattern.nil? || pattern.strip.empty?
            if pattern_type == 'regex'
              begin
                Regexp.new(pattern)
                true
              rescue RegexpError
                false
              end
            else
              true
            end
          end

          # Helper to check scheme/credential compatibility
          def mapping_scheme_credential_compatible?(scheme, credential)
            return false unless scheme && credential
            compatible_types = get_compatible_credential_types(scheme.scheme_type)
            compatible_types.include?(credential.auth_type.to_s) || compatible_types.include?(credential.auth_type)
          end
        end

        # GET /auth - Main authentication management dashboard
        app.get '/auth' do
          logger.info('GET /auth route handler entered (from AuthenticationRoutes)')
          
          # Access the authentication manager
          auth_manager = ADK::Auth::Manager.instance
          
          # Get basic counts for dashboard
          schemes_count = auth_manager.instance_variable_get(:@schemes)&.size || 0
          credentials_count = auth_manager.instance_variable_get(:@credentials)&.size || 0  
          mappings_count = auth_manager.instance_variable_get(:@url_mappings)&.size || 0
          
          # Set instance variables for the view
          self.instance_variable_set(:@auth_manager_available, true)
          self.instance_variable_set(:@schemes_count, schemes_count)
          self.instance_variable_set(:@credentials_count, credentials_count)
          self.instance_variable_set(:@mappings_count, mappings_count)
          
          slim :auth
        rescue => e
          logger.error("Error in /auth route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          self.instance_variable_set(:@auth_manager_available, false)
          self.instance_variable_set(:@error_message, e.message)
          slim :auth
        end

        # GET /auth/schemes - List all available authentication schemes
        app.get '/auth/schemes' do
          logger.info('GET /auth/schemes route handler entered (from AuthenticationRoutes)')
          content_type :html
          
          auth_manager = ADK::Auth::Manager.instance
          schemes = auth_manager.instance_variable_get(:@schemes) || {}
          credentials = auth_manager.instance_variable_get(:@credentials) || {}
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          
          # Convert schemes to a more view-friendly format with usage information
          schemes_data = schemes.map do |name, scheme|
            # Find compatible credentials
            compatible_credentials = credentials.select do |cred_name, credential|
              auth_manager.send(:credential_compatible_with_scheme?, credential, scheme)
            end
            
            # Find URL mappings using this scheme
            scheme_mappings = url_mappings.select { |mapping| mapping[:scheme_name] == name }
            
            {
              name: name,
              scheme_type: scheme.scheme_type,
              class_name: scheme.class.name.split('::').last,
              description: get_scheme_description(scheme),
              compatible_credentials_count: compatible_credentials.size,
              url_mappings_count: scheme_mappings.size,
              config_fields: get_scheme_config_fields(scheme.scheme_type),
              has_config: !get_scheme_config_fields(scheme.scheme_type).empty?
            }
          end
          
          self.instance_variable_set(:@schemes, schemes_data)
          slim :auth_schemes
        rescue => e
          logger.error("Error in /auth/schemes route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading authentication schemes: #{e.message}"
        end

        # GET /auth/schemes/:name - Individual scheme details and configuration
        app.get '/auth/schemes/:name' do
          logger.info("GET /auth/schemes/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :html
          
          scheme_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          scheme = auth_manager.get_scheme(scheme_name)
          
          halt 404, "Scheme not found: #{params[:name]}" unless scheme
          
          credentials = auth_manager.instance_variable_get(:@credentials) || {}
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          
          # Find compatible credentials
          compatible_credentials = credentials.select do |cred_name, credential|
            auth_manager.send(:credential_compatible_with_scheme?, credential, scheme)
          end.map do |cred_name, credential|
            {
              name: cred_name,
              auth_type: credential.auth_type,
              description: get_credential_description(credential),
              masked_info: get_masked_credential_info(credential)
            }
          end
          
          # Find URL mappings using this scheme
          scheme_mappings = url_mappings.select { |mapping| mapping[:scheme_name] == scheme_name }
          .map.with_index do |mapping, index|
            {
              id: index,
              pattern: mapping[:pattern].is_a?(Regexp) ? mapping[:pattern].source : mapping[:pattern].to_s,
              pattern_type: mapping[:pattern].is_a?(Regexp) ? 'regex' : 'string',
              credential_name: mapping[:credential_name]
            }
          end
          
          scheme_data = {
            name: scheme_name,
            scheme_type: scheme.scheme_type,
            class_name: scheme.class.name.split('::').last,
            description: get_scheme_description(scheme),
            config_fields: get_scheme_config_fields(scheme.scheme_type),
            current_config: get_scheme_current_config(scheme),
            compatible_credential_types: get_compatible_credential_types(scheme.scheme_type),
            compatible_credentials: compatible_credentials,
            url_mappings: scheme_mappings
          }
          
          self.instance_variable_set(:@scheme, scheme_data)
          slim :auth_scheme_detail
        rescue => e
          logger.error("Error in /auth/schemes/#{params[:name]} route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading scheme details: #{e.message}"
        end

        # POST /auth/schemes - Register new scheme instance
        app.post '/auth/schemes' do
          logger.info('POST /auth/schemes route handler entered (from AuthenticationRoutes)')
          content_type :json
          
          scheme_type = params[:scheme_type]&.to_sym
          scheme_name = params[:scheme_name]&.to_sym
          
          halt 400, { error: 'Scheme type is required' }.to_json unless scheme_type
          halt 400, { error: 'Scheme name is required' }.to_json unless scheme_name
          
          auth_manager = ADK::Auth::Manager.instance
          
          # Check if scheme name already exists
          if auth_manager.get_scheme(scheme_name)
            halt 400, { error: "Scheme with name '#{scheme_name}' already exists" }.to_json
          end
          
          begin
            # Create new scheme instance based on type
            scheme = case scheme_type
            when :api_key
              ADK::Auth::Schemes::ApiKey.new
            when :http_bearer
              ADK::Auth::Schemes::HTTPBearer.new
            when :oauth2
              ADK::Auth::Schemes::OAuth2.new(
                authorization_url: params[:authorization_url],
                token_url: params[:token_url],
                scopes: params[:scopes]&.split(/\s+/),
                use_pkce: params[:use_pkce] == 'true',
                revocation_url: params[:revocation_url]
              )
            when :oidc, :openid_connect
              ADK::Auth::Schemes::OpenIDConnect.new(
                authorization_url: params[:authorization_url],
                token_url: params[:token_url],
                userinfo_url: params[:userinfo_url],
                scopes: params[:scopes]&.split(/\s+/),
                use_pkce: params[:use_pkce] == 'true'
              )
            when :service_account
              ADK::Auth::Schemes::ServiceAccount.new(
                token_url: params[:token_url],
                scopes: params[:scopes]&.split(/\s+/)
              )
            when :google_service_account
              ADK::Auth::Schemes::GoogleServiceAccount.new(
                scopes: params[:scopes]&.split(/\s+/)
              )
            else
              halt 400, { error: "Unsupported scheme type: #{scheme_type}" }.to_json
            end
            
            # Register the new scheme
            auth_manager.register_scheme(scheme, scheme_name)
            
            logger.info("Successfully registered new scheme '#{scheme_name}' of type '#{scheme_type}'")
            { success: true, message: "Scheme '#{scheme_name}' registered successfully" }.to_json
          rescue => e
            logger.error("Error registering scheme '#{scheme_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to register scheme: #{e.message}" }.to_json
          end
        end

        # PUT /auth/schemes/:name - Update scheme configuration
        app.put '/auth/schemes/:name' do
          logger.info("PUT /auth/schemes/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :json
          
          scheme_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          existing_scheme = auth_manager.get_scheme(scheme_name)
          
          halt 404, { error: "Scheme not found: #{params[:name]}" }.to_json unless existing_scheme
          
          begin
            # Create updated scheme instance with new configuration
            scheme_type = existing_scheme.scheme_type
            updated_scheme = case scheme_type
            when :oauth2
              ADK::Auth::Schemes::OAuth2.new(
                authorization_url: params[:authorization_url],
                token_url: params[:token_url],
                scopes: params[:scopes]&.split(/\s+/),
                use_pkce: params[:use_pkce] == 'true',
                revocation_url: params[:revocation_url]
              )
            when :oidc, :openid_connect
              ADK::Auth::Schemes::OpenIDConnect.new(
                authorization_url: params[:authorization_url],
                token_url: params[:token_url],
                userinfo_url: params[:userinfo_url],
                scopes: params[:scopes]&.split(/\s+/),
                use_pkce: params[:use_pkce] == 'true'
              )
            when :service_account
              ADK::Auth::Schemes::ServiceAccount.new(
                token_url: params[:token_url],
                scopes: params[:scopes]&.split(/\s+/)
              )
            when :google_service_account
              ADK::Auth::Schemes::GoogleServiceAccount.new(
                scopes: params[:scopes]&.split(/\s+/)
              )
            else
              halt 400, { error: "Scheme type '#{scheme_type}' does not support configuration updates" }.to_json
            end
            
            # Replace the existing scheme
            auth_manager.register_scheme(updated_scheme, scheme_name)
            
            logger.info("Successfully updated scheme '#{scheme_name}' configuration")
            { success: true, message: "Scheme '#{scheme_name}' updated successfully" }.to_json
          rescue => e
            logger.error("Error updating scheme '#{scheme_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to update scheme: #{e.message}" }.to_json
          end
        end

        # DELETE /auth/schemes/:name - Remove scheme instance
        app.delete '/auth/schemes/:name' do
          logger.info("DELETE /auth/schemes/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :json
          
          scheme_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          scheme = auth_manager.get_scheme(scheme_name)
          
          halt 404, { error: "Scheme not found: #{params[:name]}" }.to_json unless scheme
          
          # Check if scheme is used in URL mappings
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          dependent_mappings = url_mappings.select { |mapping| mapping[:scheme_name] == scheme_name }
          
          if dependent_mappings.any?
            mapping_patterns = dependent_mappings.map { |m| m[:pattern] }.join(', ')
            halt 400, { 
              error: "Cannot delete scheme '#{scheme_name}' - it is used by URL mappings: #{mapping_patterns}" 
            }.to_json
          end
          
          begin
            # Remove the scheme from the manager
            schemes = auth_manager.instance_variable_get(:@schemes)
            schemes.delete(scheme_name)
            
            logger.info("Successfully deleted scheme '#{scheme_name}'")
            { success: true, message: "Scheme '#{scheme_name}' deleted successfully" }.to_json
          rescue => e
            logger.error("Error deleting scheme '#{scheme_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to delete scheme: #{e.message}" }.to_json
          end
        end

        # GET /auth/credentials - List all configured credentials
        app.get '/auth/credentials' do
          logger.info('GET /auth/credentials route handler entered (from AuthenticationRoutes)')
          content_type :html
          
          auth_manager = ADK::Auth::Manager.instance
          credentials = auth_manager.instance_variable_get(:@credentials) || {}
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          
          # Convert credentials to a view-friendly format with usage information
          credentials_data = credentials.map do |name, credential|
            # Find URL mappings using this credential
            credential_mappings = url_mappings.select { |mapping| mapping[:credential_name] == name }
            
            # Find compatible schemes
            compatible_schemes = get_compatible_schemes_for_credential(credential.auth_type)
            
            {
              name: name,
              auth_type: credential.auth_type,
              description: get_credential_description(credential),
              masked_info: get_masked_credential_info(credential),
              url_mappings_count: credential_mappings.size,
              compatible_schemes_count: compatible_schemes.size,
              config_fields: get_credential_config_fields(credential.auth_type)
            }
          end
          
          self.instance_variable_set(:@credentials, credentials_data)
          slim :auth_credentials
        rescue => e
          logger.error("Error in /auth/credentials route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading authentication credentials: #{e.message}"
        end

        # GET /auth/credentials/:name - Individual credential details and configuration
        app.get '/auth/credentials/:name' do
          logger.info("GET /auth/credentials/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :html
          
          credential_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          credential = auth_manager.get_credential(credential_name)
          
          halt 404, "Credential not found: #{params[:name]}" unless credential
          
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          
          # Find URL mappings using this credential
          credential_mappings = url_mappings.select { |mapping| mapping[:credential_name] == credential_name }
          .map.with_index do |mapping, index|
            {
              id: index,
              pattern: mapping[:pattern].is_a?(Regexp) ? mapping[:pattern].source : mapping[:pattern].to_s,
              pattern_type: mapping[:pattern].is_a?(Regexp) ? 'regex' : 'string',
              scheme_name: mapping[:scheme_name]
            }
          end
          
          # Find compatible schemes
          compatible_schemes = get_compatible_schemes_for_credential(credential.auth_type)
          
          credential_data = {
            name: credential_name,
            auth_type: credential.auth_type,
            description: get_credential_description(credential),
            config_fields: get_credential_config_fields(credential.auth_type),
            current_config: get_credential_current_config(credential),
            compatible_schemes: compatible_schemes,
            url_mappings: credential_mappings
          }
          
          self.instance_variable_set(:@credential, credential_data)
          slim :auth_credential_detail
        rescue => e
          logger.error("Error in /auth/credentials/#{params[:name]} route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading credential details: #{e.message}"
        end

        # POST /auth/credentials - Create new credential
        app.post '/auth/credentials' do
          logger.info('POST /auth/credentials route handler entered (from AuthenticationRoutes)')
          content_type :json
          
          auth_type = params[:auth_type]&.to_sym
          credential_name = params[:credential_name]&.to_sym
          
          halt 400, { error: 'Credential type is required' }.to_json unless auth_type
          halt 400, { error: 'Credential name is required' }.to_json unless credential_name
          
          auth_manager = ADK::Auth::Manager.instance
          
          # Check if credential name already exists
          if auth_manager.get_credential(credential_name)
            halt 400, { error: "Credential with name '#{credential_name}' already exists" }.to_json
          end
          
          begin
            # Build credential attributes based on type
            credential_attrs = { auth_type: auth_type }
            
            case auth_type
            when :api_key
              credential_attrs[:api_key] = params[:api_key]
              credential_attrs[:location] = params[:location] if params[:location] && !params[:location].empty?
              credential_attrs[:name] = params[:name] if params[:name] && !params[:name].empty?
            when :http_bearer
              credential_attrs[:bearer_token] = params[:bearer_token]
            when :oauth2, :oidc
              credential_attrs[:client_id] = params[:client_id]
              credential_attrs[:client_secret] = params[:client_secret]
              credential_attrs[:redirect_uri] = params[:redirect_uri] if params[:redirect_uri] && !params[:redirect_uri].empty?
              credential_attrs[:scopes] = params[:scopes] if params[:scopes] && !params[:scopes].empty?
            when :service_account
              credential_attrs[:client_email] = params[:client_email]
              credential_attrs[:private_key] = params[:private_key]
              credential_attrs[:project_id] = params[:project_id] if params[:project_id] && !params[:project_id].empty?
            when :google_service_account
              credential_attrs[:service_account_key] = params[:service_account_key]
            when :basic
              credential_attrs[:username] = params[:username]
              credential_attrs[:password] = params[:password]
            else
              halt 400, { error: "Unsupported credential type: #{auth_type}" }.to_json
            end
            
            # Create new credential
            credential = ADK::Auth::Credential.new(**credential_attrs)
            
            # Register the new credential
            auth_manager.register_credential(credential, credential_name)
            
            logger.info("Successfully registered new credential '#{credential_name}' of type '#{auth_type}'")
            { success: true, message: "Credential '#{credential_name}' created successfully" }.to_json
          rescue ADK::Auth::CredentialError => e
            logger.error("Credential validation error for '#{credential_name}': #{e.message}")
            halt 400, { error: "Invalid credential: #{e.message}" }.to_json
          rescue => e
            logger.error("Error creating credential '#{credential_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to create credential: #{e.message}" }.to_json
          end
        end

        # PUT /auth/credentials/:name - Update existing credential
        app.put '/auth/credentials/:name' do
          logger.info("PUT /auth/credentials/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :json
          
          credential_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          existing_credential = auth_manager.get_credential(credential_name)
          
          halt 404, { error: "Credential not found: #{params[:name]}" }.to_json unless existing_credential
          
          begin
            # Build updated credential attributes
            auth_type = existing_credential.auth_type
            credential_attrs = { auth_type: auth_type }
            
            case auth_type
            when :api_key
              credential_attrs[:api_key] = params[:api_key]
              credential_attrs[:location] = params[:location] if params[:location] && !params[:location].empty?
              credential_attrs[:name] = params[:name] if params[:name] && !params[:name].empty?
            when :http_bearer
              credential_attrs[:bearer_token] = params[:bearer_token]
            when :oauth2, :oidc
              credential_attrs[:client_id] = params[:client_id]
              credential_attrs[:client_secret] = params[:client_secret]
              credential_attrs[:redirect_uri] = params[:redirect_uri] if params[:redirect_uri] && !params[:redirect_uri].empty?
              credential_attrs[:scopes] = params[:scopes] if params[:scopes] && !params[:scopes].empty?
            when :service_account
              credential_attrs[:client_email] = params[:client_email]
              credential_attrs[:private_key] = params[:private_key]
              credential_attrs[:project_id] = params[:project_id] if params[:project_id] && !params[:project_id].empty?
            when :google_service_account
              credential_attrs[:service_account_key] = params[:service_account_key]
            when :basic
              credential_attrs[:username] = params[:username]
              credential_attrs[:password] = params[:password]
            else
              halt 400, { error: "Credential type '#{auth_type}' does not support updates" }.to_json
            end
            
            # Create updated credential
            updated_credential = ADK::Auth::Credential.new(**credential_attrs)
            
            # Replace the existing credential
            auth_manager.register_credential(updated_credential, credential_name)
            
            logger.info("Successfully updated credential '#{credential_name}'")
            { success: true, message: "Credential '#{credential_name}' updated successfully" }.to_json
          rescue ADK::Auth::CredentialError => e
            logger.error("Credential validation error for '#{credential_name}': #{e.message}")
            halt 400, { error: "Invalid credential: #{e.message}" }.to_json
          rescue => e
            logger.error("Error updating credential '#{credential_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to update credential: #{e.message}" }.to_json
          end
        end

        # DELETE /auth/credentials/:name - Remove credential
        app.delete '/auth/credentials/:name' do
          logger.info("DELETE /auth/credentials/#{params[:name]} route handler entered (from AuthenticationRoutes)")
          content_type :json
          
          credential_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          credential = auth_manager.get_credential(credential_name)
          
          halt 404, { error: "Credential not found: #{params[:name]}" }.to_json unless credential
          
          # Check if credential is used in URL mappings
          url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          dependent_mappings = url_mappings.select { |mapping| mapping[:credential_name] == credential_name }
          
          if dependent_mappings.any?
            mapping_patterns = dependent_mappings.map { |m| m[:pattern] }.join(', ')
            halt 400, { 
              error: "Cannot delete credential '#{credential_name}' - it is used by URL mappings: #{mapping_patterns}" 
            }.to_json
          end
          
          begin
            # Remove the credential from the manager
            credentials = auth_manager.instance_variable_get(:@credentials)
            credentials.delete(credential_name)
            
            logger.info("Successfully deleted credential '#{credential_name}'")
            { success: true, message: "Credential '#{credential_name}' deleted successfully" }.to_json
          rescue => e
            logger.error("Error deleting credential '#{credential_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to delete credential: #{e.message}" }.to_json
          end
        end

        # POST /auth/credentials/:name/test - Test credential validity
        app.post '/auth/credentials/:name/test' do
          logger.info("POST /auth/credentials/#{params[:name]}/test route handler entered (from AuthenticationRoutes)")
          content_type :json
          
          credential_name = params[:name].to_sym
          auth_manager = ADK::Auth::Manager.instance
          credential = auth_manager.get_credential(credential_name)
          
          halt 404, { error: "Credential not found: #{params[:name]}" }.to_json unless credential
          
          begin
            # Basic validation - check if credential can resolve environment variables
            test_result = { success: true, tests: [] }
            
            # Test 1: Environment variable resolution
            begin
              credential.to_h(resolve_env: true)
              test_result[:tests] << {
                name: 'Environment Variable Resolution',
                status: 'passed',
                message: 'All environment variables resolved successfully'
              }
            rescue ADK::Auth::EnvironmentVariableNotFoundError => e
              test_result[:success] = false
              test_result[:tests] << {
                name: 'Environment Variable Resolution',
                status: 'failed',
                message: "Environment variable not found: #{e.message}"
              }
            end
            
            # Test 2: Required fields validation
            begin
              # Create a new credential with the same attributes to validate
              ADK::Auth::Credential.new(**credential.to_h(resolve_env: false))
              test_result[:tests] << {
                name: 'Required Fields Validation',
                status: 'passed',
                message: 'All required fields are present'
              }
            rescue ADK::Auth::CredentialError => e
              test_result[:success] = false
              test_result[:tests] << {
                name: 'Required Fields Validation',
                status: 'failed',
                message: e.message
              }
            end
            
            # Test 3: Format validation for specific types
            case credential.auth_type
            when :google_service_account
              begin
                key_data = credential[:service_account_key]
                if key_data
                  JSON.parse(key_data)
                  test_result[:tests] << {
                    name: 'Service Account Key Format',
                    status: 'passed',
                    message: 'Service account key is valid JSON'
                  }
                end
              rescue JSON::ParserError
                test_result[:success] = false
                test_result[:tests] << {
                  name: 'Service Account Key Format',
                  status: 'failed',
                  message: 'Service account key is not valid JSON'
                }
              end
            when :service_account
              begin
                private_key = credential[:private_key]
                if private_key && !private_key.include?('BEGIN PRIVATE KEY')
                  test_result[:success] = false
                  test_result[:tests] << {
                    name: 'Private Key Format',
                    status: 'failed',
                    message: 'Private key does not appear to be in PEM format'
                  }
                else
                  test_result[:tests] << {
                    name: 'Private Key Format',
                    status: 'passed',
                    message: 'Private key appears to be in correct PEM format'
                  }
                end
              rescue => e
                test_result[:success] = false
                test_result[:tests] << {
                  name: 'Private Key Format',
                  status: 'failed',
                  message: "Private key validation error: #{e.message}"
                }
              end
            end
            
            logger.info("Credential test completed for '#{credential_name}': #{test_result[:success] ? 'PASSED' : 'FAILED'}")
            test_result.to_json
          rescue => e
            logger.error("Error testing credential '#{credential_name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to test credential: #{e.message}" }.to_json
          end
        end

        # GET /auth/mappings - List all URL mappings
        app.get '/auth/mappings' do
          logger.info('GET /auth/mappings route handler entered (from AuthenticationRoutes)')
          content_type :html
          
          auth_manager = ADK::Auth::Manager.instance
          mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          
          # Convert mappings to a view-friendly format
          mappings_data = mappings.map.with_index do |mapping, index|
            {
              id: index,
              pattern: mapping[:pattern].is_a?(Regexp) ? mapping[:pattern].source : mapping[:pattern].to_s,
              pattern_type: mapping[:pattern].is_a?(Regexp) ? 'regex' : 'string',
              scheme_name: mapping[:scheme_name],
              credential_name: mapping[:credential_name]
            }
          end
          
          self.instance_variable_set(:@mappings, mappings_data)
          slim :auth_mappings
        rescue => e
          logger.error("Error in /auth/mappings route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading URL mappings: #{e.message}"
        end

        # GET /auth/debug - Debug information about authentication state
        app.get '/auth/debug' do
          logger.info('GET /auth/debug route handler entered (from AuthenticationRoutes)')
          content_type :html
          
          auth_manager = ADK::Auth::Manager.instance
          
          # Gather debug information
          debug_info = {
            manager_class: auth_manager.class.name,
            schemes_registered: auth_manager.instance_variable_get(:@schemes)&.keys || [],
            credentials_registered: auth_manager.instance_variable_get(:@credentials)&.keys || [],
            url_mappings_count: auth_manager.instance_variable_get(:@url_mappings)&.size || 0,
            manager_instance_id: auth_manager.object_id
          }
          
          self.instance_variable_set(:@debug_info, debug_info)
          slim :auth_debug
        rescue => e
          logger.error("Error in /auth/debug route (from AuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error gathering debug information: #{e.message}"
        end

        # GET /auth/mappings/new - Form for creating new mapping
        app.get '/auth/mappings/new' do
          auth_manager = ADK::Auth::Manager.instance
          schemes = auth_manager.instance_variable_get(:@schemes) || {}
          credentials = auth_manager.instance_variable_get(:@credentials) || {}
          mapping_fields = get_mapping_config_fields
          self.instance_variable_set(:@schemes, schemes)
          self.instance_variable_set(:@credentials, credentials)
          self.instance_variable_set(:@mapping_fields, mapping_fields)
          slim :auth_mapping_new
        end

        # GET /auth/mappings/:id - Mapping detail/edit
        app.get '/auth/mappings/:id' do
          auth_manager = ADK::Auth::Manager.instance
          mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          id = params[:id].to_i
          mapping = mappings[id] or halt 404, "Mapping not found"
          schemes = auth_manager.instance_variable_get(:@schemes) || {}
          credentials = auth_manager.instance_variable_get(:@credentials) || {}
          mapping_fields = get_mapping_config_fields
          self.instance_variable_set(:@mapping, mapping)
          self.instance_variable_set(:@schemes, schemes)
          self.instance_variable_set(:@credentials, credentials)
          self.instance_variable_set(:@mapping_fields, mapping_fields)
          slim :auth_mapping_detail
        end

        # POST /auth/mappings - Create new mapping
        app.post '/auth/mappings' do
          content_type :json
          auth_manager = ADK::Auth::Manager.instance
          mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          pattern = params[:pattern]
          pattern_type = params[:pattern_type]
          scheme_name = params[:scheme_name]&.to_sym
          credential_name = params[:credential_name]&.to_sym
          priority = params[:priority]&.to_i || 1
          active = params[:active] == 'on' || params[:active] == 'true'
          # Validate pattern
          unless valid_mapping_pattern?(pattern, pattern_type)
            halt 400, { error: 'Invalid pattern' }.to_json
          end
          # Validate scheme/credential
          scheme = auth_manager.get_scheme(scheme_name)
          credential = auth_manager.get_credential(credential_name)
          unless mapping_scheme_credential_compatible?(scheme, credential)
            halt 400, { error: 'Scheme and credential are not compatible' }.to_json
          end
          # Build mapping
          mapping = {
            pattern: pattern_type == 'regex' ? Regexp.new(pattern) : pattern,
            pattern_type: pattern_type,
            scheme_name: scheme_name,
            credential_name: credential_name,
            priority: priority,
            active: active
          }
          mappings << mapping
          auth_manager.instance_variable_set(:@url_mappings, mappings)
          { success: true, message: 'Mapping created', id: mappings.size - 1 }.to_json
        end

        # PUT /auth/mappings/:id - Update mapping
        app.put '/auth/mappings/:id' do
          content_type :json
          auth_manager = ADK::Auth::Manager.instance
          mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          id = params[:id].to_i
          mapping = mappings[id] or halt 404, { error: 'Mapping not found' }.to_json
          pattern = params[:pattern]
          pattern_type = params[:pattern_type]
          scheme_name = params[:scheme_name]&.to_sym
          credential_name = params[:credential_name]&.to_sym
          priority = params[:priority]&.to_i || 1
          active = params[:active] == 'on' || params[:active] == 'true'
          unless valid_mapping_pattern?(pattern, pattern_type)
            halt 400, { error: 'Invalid pattern' }.to_json
          end
          scheme = auth_manager.get_scheme(scheme_name)
          credential = auth_manager.get_credential(credential_name)
          unless mapping_scheme_credential_compatible?(scheme, credential)
            halt 400, { error: 'Scheme and credential are not compatible' }.to_json
          end
          mapping[:pattern] = pattern_type == 'regex' ? Regexp.new(pattern) : pattern
          mapping[:pattern_type] = pattern_type
          mapping[:scheme_name] = scheme_name
          mapping[:credential_name] = credential_name
          mapping[:priority] = priority
          mapping[:active] = active
          { success: true, message: 'Mapping updated' }.to_json
        end

        # DELETE /auth/mappings/:id - Remove mapping
        app.delete '/auth/mappings/:id' do
          content_type :json
          auth_manager = ADK::Auth::Manager.instance
          mappings = auth_manager.instance_variable_get(:@url_mappings) || []
          id = params[:id].to_i
          mapping = mappings[id] or halt 404, { error: 'Mapping not found' }.to_json
          mappings.delete_at(id)
          { success: true, message: 'Mapping deleted' }.to_json
        end

        # POST /auth/mappings/test - Test pattern matching
        app.post '/auth/mappings/test' do
          content_type :json
          pattern = params[:pattern]
          pattern_type = params[:pattern_type]
          url = params[:url]
          unless valid_mapping_pattern?(pattern, pattern_type)
            halt 400, { error: 'Invalid pattern' }.to_json
          end
          begin
            matched =
              if pattern_type == 'regex'
                !!(url =~ Regexp.new(pattern))
              else
                if pattern.include?('*')
                  regex = Regexp.new('^' + Regexp.escape(pattern).gsub('\\*', '.*') + '$')
                  !!(url =~ regex)
                else
                  url == pattern
                end
              end
            { success: true, matched: matched }.to_json
          rescue => e
            halt 400, { error: "Pattern test error: #{e.message}" }.to_json
          end
        end
      end
    end
  end
end 