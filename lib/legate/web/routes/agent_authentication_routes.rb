# File: lib/legate/web/routes/agent_authentication_routes.rb
# frozen_string_literal: true

module Legate
  module Web
    module AgentAuthenticationRoutes
      def self.registered(app)
        # Add helper methods to the app
        app.helpers do
          # Helper method to get agent authentication status
          def get_agent_auth_status(agent_name)
            definition_store = instance_variable_get(:@definition_store)
            return { status: :error, message: 'Definition store unavailable' } unless definition_store

            begin
              agent_definition = definition_store.get_definition(agent_name)
              return { status: :error, message: 'Agent not found' } unless agent_definition

              auth_manager = Legate::Auth::Manager.instance
              scheme_assignments = agent_definition[:auth_scheme_assignments] || {}
              credential_assignments = agent_definition[:auth_credential_assignments] || {}
              url_mappings = agent_definition[:auth_url_mappings] || []

              # Check if agent has any authentication configured
              has_auth = !scheme_assignments.empty? || !credential_assignments.empty? || !url_mappings.empty?

              unless has_auth
                return {
                  status: :warning,
                  message: 'No authentication configured - using global defaults',
                  details: {
                    scheme_assignments: 0,
                    credential_assignments: 0,
                    url_mappings: 0,
                    global_mappings: auth_manager.instance_variable_get(:@url_mappings)&.size || 0
                  }
                }
              end

              # Validate assigned schemes and credentials exist
              issues = []
              scheme_assignments.each do |service, scheme_name|
                issues << "Scheme '#{scheme_name}' not found for service '#{service}'" unless auth_manager.get_scheme(scheme_name.to_sym)
              end

              credential_assignments.each do |service, credential_name|
                issues << "Credential '#{credential_name}' not found for service '#{service}'" unless auth_manager.get_credential(credential_name.to_sym)
              end

              if issues.any?
                return {
                  status: :error,
                  message: 'Authentication configuration issues found',
                  details: { issues: issues }
                }
              end

              {
                status: :success,
                message: 'Authentication properly configured',
                details: {
                  scheme_assignments: scheme_assignments.size,
                  credential_assignments: credential_assignments.size,
                  url_mappings: url_mappings.size
                }
              }
            rescue StandardError => e
              { status: :error, message: "Error checking authentication status: #{e.message}" }
            end
          end

          # Helper method to get available authentication options for an agent
          def get_agent_auth_options
            auth_manager = Legate::Auth::Manager.instance
            schemes = auth_manager.instance_variable_get(:@schemes) || {}
            credentials = auth_manager.instance_variable_get(:@credentials) || {}

            {
              schemes: schemes.map { |name, scheme|
                {
                  name: name,
                  type: scheme.scheme_type,
                  description: get_scheme_description(scheme)
                }
              },
              credentials: credentials.map { |name, credential|
                {
                  name: name,
                  type: credential.auth_type,
                  description: get_credential_description(credential)
                }
              }
            }
          end

          # Helper method to test agent authentication in context
          def test_agent_authentication(agent_name, test_options = {})
            definition_store = instance_variable_get(:@definition_store)
            return { success: false, error: 'Definition store unavailable' } unless definition_store

            begin
              agent_definition = definition_store.get_definition(agent_name)
              return { success: false, error: 'Agent not found' } unless agent_definition

              auth_manager = Legate::Auth::Manager.instance
              scheme_assignments = agent_definition[:auth_scheme_assignments] || {}
              credential_assignments = agent_definition[:auth_credential_assignments] || {}
              url_mappings = agent_definition[:auth_url_mappings] || []

              test_results = {
                success: true,
                tests: [],
                agent_name: agent_name,
                has_agent_auth: !scheme_assignments.empty? || !credential_assignments.empty? || !url_mappings.empty?
              }

              # Test 1: Configuration validation
              if test_results[:has_agent_auth]
                config_issues = []

                scheme_assignments.each do |service, scheme_name|
                  scheme = auth_manager.get_scheme(scheme_name.to_sym)
                  config_issues << "Missing scheme '#{scheme_name}'" unless scheme
                end

                credential_assignments.each do |service, credential_name|
                  credential = auth_manager.get_credential(credential_name.to_sym)
                  config_issues << "Missing credential '#{credential_name}'" unless credential
                end

                if config_issues.empty?
                  test_results[:tests] << {
                    name: 'Agent Authentication Configuration',
                    status: 'passed',
                    message: 'All assigned schemes and credentials are available'
                  }
                else
                  test_results[:success] = false
                  test_results[:tests] << {
                    name: 'Agent Authentication Configuration',
                    status: 'failed',
                    message: "Configuration issues: #{config_issues.join(', ')}"
                  }
                end
              else
                test_results[:tests] << {
                  name: 'Agent Authentication Configuration',
                  status: 'warning',
                  message: 'No agent-specific authentication configured - using global defaults'
                }
              end

              # Test 2: URL mapping resolution (if test URL provided)
              if test_options[:test_url]
                url = test_options[:test_url]
                resolved_auth = resolve_agent_authentication(agent_name, url)

                test_results[:tests] << if resolved_auth[:scheme] && resolved_auth[:credential]
                                          {
                                            name: 'URL Authentication Resolution',
                                            status: 'passed',
                                            message: "URL '#{url}' resolves to scheme '#{resolved_auth[:scheme]}' with credential '#{resolved_auth[:credential]}'"
                                          }
                                        else
                                          {
                                            name: 'URL Authentication Resolution',
                                            status: 'warning',
                                            message: "No authentication resolved for URL '#{url}'"
                                          }
                                        end
              end

              test_results
            rescue StandardError => e
              { success: false, error: "Error testing agent authentication: #{e.message}" }
            end
          end

          # Helper method to resolve authentication for an agent and URL
          def resolve_agent_authentication(agent_name, url)
            definition_store = instance_variable_get(:@definition_store)
            return { scheme: nil, credential: nil, source: :error } unless definition_store

            begin
              agent_definition = definition_store.get_definition(agent_name)
              return { scheme: nil, credential: nil, source: :error } unless agent_definition

              auth_manager = Legate::Auth::Manager.instance

              # First check agent-specific URL mappings
              agent_url_mappings = agent_definition[:auth_url_mappings] || []
              agent_url_mappings.each do |mapping|
                pattern = mapping['pattern'] || mapping[:pattern]
                next unless pattern

                matched = if pattern.is_a?(Regexp)
                            !!(url =~ pattern)
                          elsif pattern.include?('*')
                            regex = Regexp.new('^' + Regexp.escape(pattern).gsub('\\*', '.*') + '$')
                            !!(url =~ regex)
                          else
                            url == pattern
                          end

                next unless matched

                scheme_name = mapping['scheme_name'] || mapping[:scheme_name]
                credential_name = mapping['credential_name'] || mapping[:credential_name]
                return {
                  scheme: scheme_name,
                  credential: credential_name,
                  source: :agent_mapping
                }
              end

              # Then check global URL mappings
              global_mappings = auth_manager.instance_variable_get(:@url_mappings) || []
              global_mappings.each do |mapping|
                pattern = mapping[:pattern]
                next unless pattern

                matched = if pattern.is_a?(Regexp)
                            !!(url =~ pattern)
                          elsif pattern.to_s.include?('*')
                            regex = Regexp.new('^' + Regexp.escape(pattern.to_s).gsub('\\*', '.*') + '$')
                            !!(url =~ regex)
                          else
                            url == pattern.to_s
                          end

                if matched
                  return {
                    scheme: mapping[:scheme_name],
                    credential: mapping[:credential_name],
                    source: :global_mapping
                  }
                end
              end

              { scheme: nil, credential: nil, source: :none }
            rescue StandardError => e
              { scheme: nil, credential: nil, source: :error }
            end
          end
        end

        # GET /agents/:name/auth - Agent-specific authentication configuration
        app.get '/agents/:name/auth' do |name|
          logger.info("GET /agents/#{name}/auth route handler entered (from AgentAuthenticationRoutes)")
          content_type :html

          definition_store = instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, 'Agent not found.' unless agent_definition

          auth_status = get_agent_auth_status(name)
          auth_options = get_agent_auth_options

          agent_auth_data = {
            name: name,
            description: agent_definition[:description],
            auth_status: auth_status,
            scheme_assignments: agent_definition[:auth_scheme_assignments] || {},
            credential_assignments: agent_definition[:auth_credential_assignments] || {},
            url_mappings: agent_definition[:auth_url_mappings] || [],
            available_schemes: auth_options[:schemes],
            available_credentials: auth_options[:credentials]
          }

          instance_variable_set(:@agent_auth_data, agent_auth_data)
          slim :agent_auth
        rescue StandardError => e
          logger.error("Error in /agents/#{name}/auth route (from AgentAuthenticationRoutes): #{e.class} - #{e.message}")
          halt 500, "Error loading agent authentication configuration: #{e.message}"
        end

        # POST /agents/:name/auth/assign - Assign authentication to agent
        app.post '/agents/:name/auth/assign' do |name|
          logger.info("POST /agents/#{name}/auth/assign route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          assignment_type = params[:assignment_type]
          service = params[:service]
          auth_name = params[:auth_name]

          halt 400, { error: 'Assignment type is required' }.to_json unless assignment_type
          halt 400, { error: 'Service is required' }.to_json unless service
          halt 400, { error: 'Authentication name is required' }.to_json unless auth_name

          begin
            case assignment_type
            when 'scheme'
              # Verify scheme exists
              auth_manager = Legate::Auth::Manager.instance
              scheme = auth_manager.get_scheme(auth_name.to_sym)
              halt 400, { error: "Scheme '#{auth_name}' not found" }.to_json unless scheme

              # Update agent's scheme assignments
              scheme_assignments = agent_definition[:auth_scheme_assignments] || {}
              scheme_assignments[service] = auth_name

              definition_store.update_definition(name, { auth_scheme_assignments: scheme_assignments })

            when 'credential'
              # Verify credential exists
              auth_manager = Legate::Auth::Manager.instance
              credential = auth_manager.get_credential(auth_name.to_sym)
              halt 400, { error: "Credential '#{auth_name}' not found" }.to_json unless credential

              # Update agent's credential assignments
              credential_assignments = agent_definition[:auth_credential_assignments] || {}
              credential_assignments[service] = auth_name

              definition_store.update_definition(name, { auth_credential_assignments: credential_assignments })

            else
              halt 400, { error: "Invalid assignment type: #{assignment_type}" }.to_json
            end

            logger.info("Successfully assigned #{assignment_type} '#{auth_name}' to service '#{service}' for agent '#{name}'")
            { success: true, message: "#{assignment_type.capitalize} '#{auth_name}' assigned to service '#{service}'" }.to_json
          rescue StandardError => e
            logger.error("Error assigning authentication to agent '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to assign authentication: #{e.message}" }.to_json
          end
        end

        # DELETE /agents/:name/auth/remove - Remove authentication from agent
        app.delete '/agents/:name/auth/remove' do |name|
          logger.info("DELETE /agents/#{name}/auth/remove route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          assignment_type = params[:assignment_type]
          service = params[:service]

          halt 400, { error: 'Assignment type is required' }.to_json unless assignment_type
          halt 400, { error: 'Service is required' }.to_json unless service

          begin
            case assignment_type
            when 'scheme'
              scheme_assignments = agent_definition[:auth_scheme_assignments] || {}
              removed_scheme = scheme_assignments.delete(service)

              if removed_scheme
                definition_store.update_definition(name, { auth_scheme_assignments: scheme_assignments })
                logger.info("Successfully removed scheme assignment for service '#{service}' from agent '#{name}'")
                { success: true, message: "Scheme assignment for service '#{service}' removed" }.to_json
              else
                { success: false, message: "No scheme assignment found for service '#{service}'" }.to_json
              end

            when 'credential'
              credential_assignments = agent_definition[:auth_credential_assignments] || {}
              removed_credential = credential_assignments.delete(service)

              if removed_credential
                definition_store.update_definition(name, { auth_credential_assignments: credential_assignments })
                logger.info("Successfully removed credential assignment for service '#{service}' from agent '#{name}'")
                { success: true, message: "Credential assignment for service '#{service}' removed" }.to_json
              else
                { success: false, message: "No credential assignment found for service '#{service}'" }.to_json
              end

            else
              halt 400, { error: "Invalid assignment type: #{assignment_type}" }.to_json
            end
          rescue StandardError => e
            logger.error("Error removing authentication from agent '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to remove authentication: #{e.message}" }.to_json
          end
        end

        # POST /agents/:name/auth/test - Test authentication in agent context
        app.post '/agents/:name/auth/test' do |name|
          logger.info("POST /agents/#{name}/auth/test route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          begin
            test_options = {}
            test_options[:test_url] = params[:test_url] if params[:test_url] && !params[:test_url].empty?

            test_results = test_agent_authentication(name, test_options)

            logger.info("Agent authentication test completed for '#{name}': #{test_results[:success] ? 'PASSED' : 'FAILED'}")
            test_results.to_json
          rescue StandardError => e
            logger.error("Error testing agent authentication for '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to test agent authentication: #{e.message}" }.to_json
          end
        end

        # GET /agents/:name/auth/status - Get authentication status for agent
        app.get '/agents/:name/auth/status' do |name|
          logger.info("GET /agents/#{name}/auth/status route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          begin
            auth_status = get_agent_auth_status(name)
            auth_status.to_json
          rescue StandardError => e
            logger.error("Error getting agent authentication status for '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to get authentication status: #{e.message}" }.to_json
          end
        end

        # POST /agents/:name/auth/url-mapping - Add URL mapping for agent
        app.post '/agents/:name/auth/url-mapping' do |name|
          logger.info("POST /agents/#{name}/auth/url-mapping route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          pattern = params[:pattern]
          pattern_type = params[:pattern_type]
          scheme_name = params[:scheme_name]
          credential_name = params[:credential_name]
          priority = params[:priority]&.to_i || 1

          halt 400, { error: 'Pattern is required' }.to_json unless pattern && !pattern.empty?
          halt 400, { error: 'Scheme name is required' }.to_json unless scheme_name && !scheme_name.empty?
          halt 400, { error: 'Credential name is required' }.to_json unless credential_name && !credential_name.empty?

          begin
            # Validate pattern
            if pattern_type == 'regex'
              begin
                Regexp.new(pattern)
              rescue RegexpError
                halt 400, { error: 'Invalid regex pattern' }.to_json
              end
            end

            # Verify scheme and credential exist
            auth_manager = Legate::Auth::Manager.instance
            scheme = auth_manager.get_scheme(scheme_name.to_sym)
            credential = auth_manager.get_credential(credential_name.to_sym)

            halt 400, { error: "Scheme '#{scheme_name}' not found" }.to_json unless scheme
            halt 400, { error: "Credential '#{credential_name}' not found" }.to_json unless credential

            # Check compatibility
            compatible_types = get_compatible_credential_types(scheme.scheme_type)
            halt 400, { error: 'Scheme and credential are not compatible' }.to_json unless compatible_types.include?(credential.auth_type.to_s) || compatible_types.include?(credential.auth_type)

            # Add URL mapping to agent
            url_mappings = agent_definition[:auth_url_mappings] || []
            new_mapping = {
              pattern: pattern_type == 'regex' ? pattern : pattern,
              pattern_type: pattern_type,
              scheme_name: scheme_name,
              credential_name: credential_name,
              priority: priority,
              active: true
            }

            url_mappings << new_mapping
            definition_store.update_definition(name, { auth_url_mappings: url_mappings })

            logger.info("Successfully added URL mapping for agent '#{name}': #{pattern} -> #{scheme_name}/#{credential_name}")
            { success: true, message: 'URL mapping added successfully', mapping_id: url_mappings.size - 1 }.to_json
          rescue StandardError => e
            logger.error("Error adding URL mapping for agent '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to add URL mapping: #{e.message}" }.to_json
          end
        end

        # DELETE /agents/:name/auth/url-mapping/:id - Remove URL mapping from agent
        app.delete '/agents/:name/auth/url-mapping/:id' do |name, mapping_id|
          logger.info("DELETE /agents/#{name}/auth/url-mapping/#{mapping_id} route handler entered (from AgentAuthenticationRoutes)")
          content_type :json

          definition_store = instance_variable_get(:@definition_store)
          halt 503, { error: 'Definition Store unavailable' }.to_json unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, { error: 'Agent not found' }.to_json unless agent_definition

          begin
            url_mappings = agent_definition[:auth_url_mappings] || []
            id = mapping_id.to_i

            if id >= 0 && id < url_mappings.size
              removed_mapping = url_mappings.delete_at(id)
              definition_store.update_definition(name, { auth_url_mappings: url_mappings })

              logger.info("Successfully removed URL mapping #{id} from agent '#{name}'")
              { success: true, message: 'URL mapping removed successfully' }.to_json
            else
              { success: false, message: 'URL mapping not found' }.to_json
            end
          rescue StandardError => e
            logger.error("Error removing URL mapping from agent '#{name}': #{e.class} - #{e.message}")
            halt 500, { error: "Failed to remove URL mapping: #{e.message}" }.to_json
          end
        end
      end
    end
  end
end
