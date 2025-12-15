# File: lib/adk/cli/auth_commands.rb
# frozen_string_literal: true

require 'thor'
require 'cli/ui'
require_relative '../../adk'

module ADK
  module CLI
    # Helper module for auth command formatting
    module AuthCommandHelpers
      # Mask sensitive values for display
      def mask_sensitive_value(value)
        return '(not set)' if value.nil? || value.empty?
        return value if value.start_with?('ENV:') # Show env var references as-is

        if value.length <= 8
          '********'
        else
          "#{value[0, 4]}********#{value[-4..]}"
        end
      end

      # Get scheme type description
      def scheme_type_description(scheme_type)
        case scheme_type.to_sym
        when :api_key then 'API Key authentication'
        when :http_bearer then 'HTTP Bearer token'
        when :oauth2 then 'OAuth 2.0 flow'
        when :oidc, :openid_connect then 'OpenID Connect'
        when :service_account then 'Service Account'
        when :google_service_account then 'Google Service Account'
        else scheme_type.to_s
        end
      end

      # Get credential type description
      def credential_type_description(auth_type)
        case auth_type.to_sym
        when :api_key then 'API Key'
        when :http_bearer then 'Bearer Token'
        when :oauth2 then 'OAuth2 Client'
        when :oidc then 'OIDC Client'
        when :service_account then 'Service Account'
        when :google_service_account then 'Google Service Account'
        when :basic then 'Basic Auth'
        else auth_type.to_s
        end
      end

      # Sensitive field names
      def sensitive_field?(name)
        %i[api_key client_secret bearer_token password private_key service_account_key token].include?(name.to_sym)
      end

      # Print styled header
      def print_header(text)
        puts ::CLI::UI.fmt("{{bold:#{text}}}")
      end

      # Print styled table row
      def print_row(label, value, indent: 2)
        padding = ' ' * indent
        puts "#{padding}#{::CLI::UI.fmt("{{cyan:#{label}:}}")} #{value}"
      end

      # Ensure auth manager is ready
      def auth_manager
        @auth_manager ||= begin
          manager = ADK::Auth::Manager.instance
          manager.load_from_store
          manager
        end
      end
    end

    # Scheme management subcommands
    class AuthSchemeCommands < Thor
      include AuthCommandHelpers

      namespace 'auth:schemes'

      desc 'list', 'List all registered authentication schemes'
      def list
        schemes = auth_manager.instance_variable_get(:@schemes) || {}

        if schemes.empty?
          puts ::CLI::UI.fmt('{{yellow:No authentication schemes registered.}}')
          return
        end

        print_header("Authentication Schemes (#{schemes.size})")
        puts

        schemes.each do |name, scheme|
          puts ::CLI::UI.fmt("  {{bold:#{name}}} {{gray:(#{scheme.scheme_type})}}")
          puts "    #{scheme_type_description(scheme.scheme_type)}"
          puts
        end
      end

      desc 'show NAME', 'Show details for a specific scheme'
      def show(name)
        scheme = auth_manager.get_scheme(name.to_sym)

        unless scheme
          puts ::CLI::UI.fmt("{{red:Scheme not found:}} #{name}")
          exit 1
        end

        print_header("Scheme: #{name}")
        print_row('Type', scheme.scheme_type)
        print_row('Class', scheme.class.name.split('::').last)
        print_row('Description', scheme_type_description(scheme.scheme_type))

        # Show scheme-specific config
        config = scheme.to_h
        config.each do |key, value|
          next if key == :type

          print_row(key.to_s.capitalize, value) if value
        end
      end

      desc 'create NAME', 'Create a new authentication scheme'
      method_option :type, type: :string, required: true,
                           desc: 'Scheme type (api_key, http_bearer, oauth2, oidc, service_account, google_service_account)'
      method_option :authorization_url, type: :string, desc: 'OAuth2/OIDC authorization URL'
      method_option :token_url, type: :string, desc: 'OAuth2/OIDC/Service Account token URL'
      method_option :userinfo_url, type: :string, desc: 'OIDC userinfo URL'
      method_option :scopes, type: :string, desc: 'Space-separated scopes'
      method_option :use_pkce, type: :boolean, default: false, desc: 'Use PKCE for OAuth2/OIDC'
      method_option :revocation_url, type: :string, desc: 'OAuth2 revocation URL'
      def create(name)
        scheme_name = name.to_sym
        scheme_type = options[:type].to_sym

        if auth_manager.get_scheme(scheme_name)
          puts ::CLI::UI.fmt("{{red:Scheme already exists:}} #{name}")
          exit 1
        end

        scheme = case scheme_type
                 when :api_key
                   ADK::Auth::Schemes::ApiKey.new
                 when :http_bearer
                   ADK::Auth::Schemes::HTTPBearer.new
                 when :oauth2
                   ADK::Auth::Schemes::OAuth2.new(
                     authorization_url: options[:authorization_url],
                     token_url: options[:token_url],
                     scopes: options[:scopes]&.split(/\s+/),
                     use_pkce: options[:use_pkce],
                     revocation_url: options[:revocation_url]
                   )
                 when :oidc, :openid_connect
                   ADK::Auth::Schemes::OpenIDConnect.new(
                     authorization_url: options[:authorization_url],
                     token_url: options[:token_url],
                     userinfo_url: options[:userinfo_url],
                     scopes: options[:scopes]&.split(/\s+/),
                     use_pkce: options[:use_pkce]
                   )
                 when :service_account
                   ADK::Auth::Schemes::ServiceAccount.new(
                     token_url: options[:token_url],
                     scopes: options[:scopes]&.split(/\s+/)
                   )
                 when :google_service_account
                   ADK::Auth::Schemes::GoogleServiceAccount.new(
                     scopes: options[:scopes]&.split(/\s+/)
                   )
                 else
                   puts ::CLI::UI.fmt("{{red:Unsupported scheme type:}} #{scheme_type}")
                   exit 1
                 end

        auth_manager.register_scheme(scheme, scheme_name)
        puts ::CLI::UI.fmt("{{green:✓}} Scheme '#{name}' created successfully")
      end

      desc 'delete NAME', 'Delete an authentication scheme'
      method_option :force, type: :boolean, default: false, desc: 'Force delete even if in use'
      def delete(name)
        scheme_name = name.to_sym

        unless auth_manager.get_scheme(scheme_name)
          puts ::CLI::UI.fmt("{{red:Scheme not found:}} #{name}")
          exit 1
        end

        # Check for dependent mappings
        url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
        dependent = url_mappings.select { |m| m[:scheme_name] == scheme_name }

        if dependent.any? && !options[:force]
          puts ::CLI::UI.fmt("{{red:Cannot delete}} - scheme is used by #{dependent.size} URL mapping(s)")
          puts 'Use --force to delete anyway'
          exit 1
        end

        auth_manager.unregister_scheme(scheme_name)
        puts ::CLI::UI.fmt("{{green:✓}} Scheme '#{name}' deleted")
      end
    end

    # Credential management subcommands
    class AuthCredentialCommands < Thor
      include AuthCommandHelpers

      namespace 'auth:credentials'

      desc 'list', 'List all registered credentials'
      def list
        credentials = auth_manager.instance_variable_get(:@credentials) || {}

        if credentials.empty?
          puts ::CLI::UI.fmt('{{yellow:No credentials registered.}}')
          return
        end

        print_header("Credentials (#{credentials.size})")
        puts

        credentials.each do |name, cred|
          puts ::CLI::UI.fmt("  {{bold:#{name}}} {{gray:(#{cred.auth_type})}}")

          # Show masked key info
          case cred.auth_type
          when :api_key
            puts "    API Key: #{mask_sensitive_value(cred[:api_key, resolve_env: false])}"
          when :http_bearer
            puts "    Token: #{mask_sensitive_value(cred[:bearer_token, resolve_env: false])}"
          when :oauth2, :oidc
            puts "    Client ID: #{cred[:client_id, resolve_env: false]}"
          when :service_account, :google_service_account
            puts '    Service Account Key: ********'
          end
          puts
        end
      end

      desc 'show NAME', 'Show details for a specific credential'
      def show(name)
        credential = auth_manager.get_credential(name.to_sym)

        unless credential
          puts ::CLI::UI.fmt("{{red:Credential not found:}} #{name}")
          exit 1
        end

        print_header("Credential: #{name}")
        print_row('Type', credential_type_description(credential.auth_type))

        credential.to_h(resolve_env: false).each do |key, value|
          next if key == :auth_type

          display_value = sensitive_field?(key) ? mask_sensitive_value(value.to_s) : value
          print_row(key.to_s, display_value)
        end
      end

      desc 'create NAME', 'Create a new credential'
      method_option :type, type: :string, required: true,
                           desc: 'Credential type (api_key, http_bearer, oauth2, oidc, service_account, google_service_account, basic)'
      method_option :api_key, type: :string, desc: 'API key value (or ENV:VAR_NAME)'
      method_option :bearer_token, type: :string, desc: 'Bearer token (or ENV:VAR_NAME)'
      method_option :client_id, type: :string, desc: 'OAuth2/OIDC client ID'
      method_option :client_secret, type: :string, desc: 'OAuth2/OIDC client secret (or ENV:VAR_NAME)'
      method_option :redirect_uri, type: :string, desc: 'OAuth2/OIDC redirect URI'
      method_option :username, type: :string, desc: 'Basic auth username'
      method_option :password, type: :string, desc: 'Basic auth password (or ENV:VAR_NAME)'
      method_option :service_account_key, type: :string, desc: 'Service account JSON key (or ENV:VAR_NAME)'
      method_option :service_account_key_file, type: :string, desc: 'Path to service account key file'
      def create(name)
        cred_name = name.to_sym
        auth_type = options[:type].to_sym

        if auth_manager.get_credential(cred_name)
          puts ::CLI::UI.fmt("{{red:Credential already exists:}} #{name}")
          exit 1
        end

        attrs = { auth_type: auth_type }

        case auth_type
        when :api_key
          attrs[:api_key] = options[:api_key] || prompt_for('API Key')
        when :http_bearer
          attrs[:bearer_token] = options[:bearer_token] || prompt_for('Bearer Token')
        when :oauth2, :oidc
          attrs[:client_id] = options[:client_id] || prompt_for('Client ID')
          attrs[:client_secret] = options[:client_secret]
          attrs[:redirect_uri] = options[:redirect_uri] if options[:redirect_uri]
        when :service_account, :google_service_account
          attrs[:service_account_key] = if options[:service_account_key_file]
                                          File.read(options[:service_account_key_file])
                                        else
                                          options[:service_account_key] || prompt_for('Service Account Key JSON')
                                        end
        when :basic
          attrs[:username] = options[:username] || prompt_for('Username')
          attrs[:password] = options[:password] || prompt_for('Password')
        else
          puts ::CLI::UI.fmt("{{red:Unsupported credential type:}} #{auth_type}")
          exit 1
        end

        credential = ADK::Auth::Credential.new(**attrs)
        auth_manager.register_credential(credential, cred_name)
        puts ::CLI::UI.fmt("{{green:✓}} Credential '#{name}' created successfully")
      rescue ADK::Auth::CredentialError => e
        puts ::CLI::UI.fmt("{{red:Invalid credential:}} #{e.message}")
        exit 1
      end

      desc 'delete NAME', 'Delete a credential'
      method_option :force, type: :boolean, default: false, desc: 'Force delete even if in use'
      def delete(name)
        cred_name = name.to_sym

        unless auth_manager.get_credential(cred_name)
          puts ::CLI::UI.fmt("{{red:Credential not found:}} #{name}")
          exit 1
        end

        # Check for dependent mappings
        url_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
        dependent = url_mappings.select { |m| m[:credential_name] == cred_name }

        if dependent.any? && !options[:force]
          puts ::CLI::UI.fmt("{{red:Cannot delete}} - credential is used by #{dependent.size} URL mapping(s)")
          puts 'Use --force to delete anyway'
          exit 1
        end

        auth_manager.unregister_credential(cred_name)
        puts ::CLI::UI.fmt("{{green:✓}} Credential '#{name}' deleted")
      end

      desc 'test NAME', 'Test a credential'
      method_option :url, type: :string, desc: 'URL to test the credential against'
      def test(name)
        credential = auth_manager.get_credential(name.to_sym)

        unless credential
          puts ::CLI::UI.fmt("{{red:Credential not found:}} #{name}")
          exit 1
        end

        print_header("Testing credential: #{name}")
        puts

        # Basic validation
        begin
          credential.to_h(resolve_env: true)
          puts ::CLI::UI.fmt('  {{green:✓}} Basic validation passed')
        rescue ADK::Auth::EnvironmentVariableNotFoundError => e
          puts ::CLI::UI.fmt("  {{red:✗}} Environment variable not found: #{e.message}")
          exit 1
        end

        # Type-specific validation
        case credential.auth_type
        when :api_key
          api_key = credential[:api_key]
          if api_key && !api_key.empty?
            puts ::CLI::UI.fmt('  {{green:✓}} API key is present')
          else
            puts ::CLI::UI.fmt('  {{red:✗}} API key is empty')
          end
        when :oauth2, :oidc
          client_id = credential[:client_id]
          client_secret = credential[:client_secret]
          puts client_id ? ::CLI::UI.fmt('  {{green:✓}} Client ID is present') : ::CLI::UI.fmt('  {{red:✗}} Client ID missing')
          puts client_secret ? ::CLI::UI.fmt('  {{green:✓}} Client secret is present') : ::CLI::UI.fmt('  {{yellow:⚠}} Client secret not set')
        when :google_service_account
          begin
            key_data = credential[:service_account_key]
            parsed = JSON.parse(key_data)
            required = %w[type project_id private_key_id private_key client_email client_id]
            missing = required.reject { |f| parsed.key?(f) }
            if missing.empty?
              puts ::CLI::UI.fmt('  {{green:✓}} Service account key is valid JSON with all required fields')
            else
              puts ::CLI::UI.fmt("  {{red:✗}} Missing fields: #{missing.join(', ')}")
            end
          rescue JSON::ParserError
            puts ::CLI::UI.fmt('  {{red:✗}} Service account key is not valid JSON')
          end
        end

        puts
        puts ::CLI::UI.fmt('{{green:Test complete}}')
      end

      private

      def prompt_for(field)
        print "#{field}: "
        $stdin.gets.chomp
      end
    end

    # URL mapping management subcommands
    class AuthMappingCommands < Thor
      include AuthCommandHelpers

      namespace 'auth:mappings'

      desc 'list', 'List all URL-to-auth mappings'
      def list
        mappings = auth_manager.instance_variable_get(:@url_mappings) || []

        if mappings.empty?
          puts ::CLI::UI.fmt('{{yellow:No URL mappings registered.}}')
          return
        end

        print_header("URL Mappings (#{mappings.size})")
        puts

        mappings.each_with_index do |mapping, idx|
          pattern = mapping[:pattern].is_a?(Regexp) ? mapping[:pattern].source : mapping[:pattern].to_s
          pattern_type = mapping[:pattern].is_a?(Regexp) ? 'regex' : 'string'

          puts ::CLI::UI.fmt("  {{bold:[#{idx}]}} #{pattern} {{gray:(#{pattern_type})}}")
          puts "       Scheme: #{mapping[:scheme_name]}, Credential: #{mapping[:credential_name]}"
          puts
        end
      end

      desc 'create', 'Create a new URL mapping'
      method_option :pattern, type: :string, required: true, desc: 'URL pattern (string or regex)'
      method_option :scheme, type: :string, required: true, desc: 'Scheme name to use'
      method_option :credential, type: :string, required: true, desc: 'Credential name to use'
      method_option :regex, type: :boolean, default: false, desc: 'Treat pattern as regex'
      def create
        scheme_name = options[:scheme].to_sym
        cred_name = options[:credential].to_sym

        unless auth_manager.get_scheme(scheme_name)
          puts ::CLI::UI.fmt("{{red:Scheme not found:}} #{options[:scheme]}")
          exit 1
        end

        unless auth_manager.get_credential(cred_name)
          puts ::CLI::UI.fmt("{{red:Credential not found:}} #{options[:credential]}")
          exit 1
        end

        pattern = if options[:regex]
                    begin
                      Regexp.new(options[:pattern])
                    rescue RegexpError => e
                      puts ::CLI::UI.fmt("{{red:Invalid regex:}} #{e.message}")
                      exit 1
                    end
                  else
                    options[:pattern]
                  end

        auth_manager.register_url_mapping(pattern, scheme_name, cred_name)
        puts ::CLI::UI.fmt('{{green:✓}} URL mapping created successfully')
      end

      desc 'delete INDEX', 'Delete a URL mapping by index'
      def delete(index)
        idx = index.to_i
        mappings = auth_manager.instance_variable_get(:@url_mappings) || []

        if idx < 0 || idx >= mappings.size
          puts ::CLI::UI.fmt("{{red:Invalid index:}} #{index} (valid range: 0-#{mappings.size - 1})")
          exit 1
        end

        auth_manager.remove_url_mapping(idx)
        puts ::CLI::UI.fmt("{{green:✓}} URL mapping [#{index}] deleted")
      end
    end

    # Main auth commands class that registers subcommands
    class AuthCommands < Thor
      namespace :auth

      desc 'schemes SUBCOMMAND', 'Manage authentication schemes'
      subcommand 'schemes', AuthSchemeCommands

      desc 'credentials SUBCOMMAND', 'Manage authentication credentials'
      subcommand 'credentials', AuthCredentialCommands

      desc 'mappings SUBCOMMAND', 'Manage URL-to-auth mappings'
      subcommand 'mappings', AuthMappingCommands

      desc 'status', 'Show authentication system status'
      def status
        manager = ADK::Auth::Manager.instance
        manager.load_from_store

        schemes = manager.instance_variable_get(:@schemes) || {}
        credentials = manager.instance_variable_get(:@credentials) || {}
        mappings = manager.instance_variable_get(:@url_mappings) || []

        puts ::CLI::UI.fmt('{{bold:Authentication System Status}}')
        puts
        puts ::CLI::UI.fmt("  Schemes:     {{cyan:#{schemes.size}}}")
        puts ::CLI::UI.fmt("  Credentials: {{cyan:#{credentials.size}}}")
        puts ::CLI::UI.fmt("  Mappings:    {{cyan:#{mappings.size}}}")
        puts

        puts ::CLI::UI.fmt('  {{gray:Scheme types:}} ' + schemes.values.map(&:scheme_type).uniq.join(', ')) if schemes.any?

        return unless credentials.any?

        puts ::CLI::UI.fmt('  {{gray:Credential types:}} ' + credentials.values.map(&:auth_type).uniq.join(', '))
      end
    end
  end
end
