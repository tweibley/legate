# File: lib/adk/web/routes/agent_definition_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentDefinitionRoutes
      def self.registered(app)
        # GET /agents - Display the main agent management page.
        app.get '/agents' do
          # `self` is the Sinatra app instance in a route block
          definition_store = self.instance_variable_get(:@definition_store)

          view_agents_list = []
          if definition_store
            begin
              agent_definitions = definition_store.list_definitions # This includes persistent_status

              view_agents_list = agent_definitions.map do |definition|
                next unless definition && definition[:name] # Ensure definition and name are present

                view_model = definition.dup # Create a mutable copy for the view
                view_model[:configured_tools] = view_model.delete(:tools) || [] # Ensure it's an array
                # Include agent_type in the view model, default to :llm if not present
                view_model[:agent_type] = view_model[:agent_type]&.to_sym || :llm
                # Display is based on persistent_status stored in Redis
                # This survives across requests since @agents doesn't persist between Sinatra instances
                view_model[:running] = (definition[:persistent_status] == 'running')
                view_model
              end.compact # Remove any nils from failed definition fetches
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error fetching agent list (from AgentDefinitionRoutes): #{e.message}")
            end
          else
            logger.error('Definition Store unavailable during GET /agents (from AgentDefinitionRoutes)')
          end

          self.instance_variable_set(:@view_agents, view_agents_list)
          self.instance_variable_set(:@available_tools, ADK::GlobalToolManager.list_all_tools)
          self.instance_variable_set(:@available_models, ADK::Web::App::AVAILABLE_MODELS) # Access constant via App class
          slim :agents
        end

        # POST /agents - Create a new agent definition.
        app.post '/agents' do
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Redis unavailable.' unless definition_store

          agent_name = params['name']&.strip
          agent_description = params['description']&.strip
          selected_tools = params['tools'] || []
          selected_model = params['model']&.strip
          selected_fallback = params['fallback_mode'] || 'error'
          mcp_servers_json = params['mcp_servers_json']&.strip
          instruction = params['instruction']&.strip
          agent_type = params['agent_type']&.strip || 'llm'

          # Get sub-agents for workflow agents
          sub_agent_names = params['sub_agent_names'] || []

          # Remove self from sub-agent selections to prevent circular references
          sub_agent_names = sub_agent_names.reject { |name| name == agent_name }

          # Validate agent_type
          unless %w[llm sequential parallel loop].include?(agent_type)
            agent_type = 'llm'
          end

          mcp_servers_json_to_save = (mcp_servers_json.nil? || mcp_servers_json.empty?) ? '[]' : mcp_servers_json
          model_to_save = selected_model && !selected_model.empty? ? selected_model : ADK::Agent::DEFAULT_MODEL

          if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
            status 400
            halt "<div class='notification is-danger'>Name and description required.</div>"
          end

          begin
            definition_params = {
              name: agent_name,
              description: agent_description,
              tools: selected_tools,
              model: model_to_save,
              fallback_mode: selected_fallback, # Store will convert to symbol
              mcp_servers_json: mcp_servers_json_to_save,
              instruction: instruction,
              agent_type: agent_type
            }

            # Add sub_agent_names for workflow agents if they were selected
            if agent_type != 'llm' && !sub_agent_names.empty?
              definition_params[:sub_agent_names] = sub_agent_names
            end

            definition_store.save_definition(**definition_params)
            logger.info("Agent '#{agent_name}' definition saved (from AgentDefinitionRoutes)")
            ADK::ActivityLog.log(:agent_created, { name: agent_name }) rescue nil
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error saving agent definition (from AgentDefinitionRoutes): #{e.message}")
            halt 500, 'Error saving agent definition.'
          end

          content_type :html
          agent_data = {
            name: agent_name, description: agent_description, running: false,
            configured_tools: selected_tools, model: model_to_save,
            fallback_mode: selected_fallback.to_sym, # Ensure symbol for partial
            instruction: instruction,
            agent_type: agent_type.to_sym, # Convert to symbol for the partial
            is_new: true
          }

          # Include sub_agent_names if this is a workflow agent
          if agent_type != 'llm' && !sub_agent_names.empty?
            agent_data[:sub_agent_names] = sub_agent_names
          end

          # available_tools needed by _agent_row partial
          current_available_tools = ADK::GlobalToolManager.list_all_tools
          agent_row_html = slim(:_agent_row, layout: false,
                                             locals: { agent_info: agent_data, available_tools: current_available_tools })
          oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"
          headers 'HX-Trigger' => 'closeCreateAgentForm'
          agent_row_html + oob_remove_message_html
        end

        # DELETE /agents/:name - Delete an agent definition.
        app.delete '/agents/:name' do |name|
          logger.info("Received request to delete agent '#{name}' (from AgentDefinitionRoutes)")
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, 'Definition Store unavailable.' unless definition_store

          if active_agents_hash.key?(name)
            logger.info("Stopping running agent '#{name}' before deletion (from AgentDefinitionRoutes)...")
            begin
              active_agents_hash[name].stop
              active_agents_hash.delete(name)
              logger.info("Agent '#{name}' stopped (from AgentDefinitionRoutes).")
            rescue => e
              logger.error("Error stopping agent (from AgentDefinitionRoutes): #{e.message}")
            end
          end
          begin
            definition_store.delete_definition(name)
            logger.info("Agent '#{name}' definition deleted from Redis (from AgentDefinitionRoutes).")
            ADK::ActivityLog.log(:agent_deleted, { name: name }) rescue nil
            status 200
            body ''
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error deleting agent '#{name}' (from AgentDefinitionRoutes): #{e.message}")
            halt 500, 'Database error during deletion.'
          end
        end

        # POST /agents/:name/duplicate - Create a copy of an agent.
        app.post '/agents/:name/duplicate' do |name|
          logger.info("Received request to duplicate agent '#{name}'")
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          original_definition = definition_store.get_definition(name)
          halt 404, 'Agent not found' unless original_definition

          # Generate unique name for the copy
          base_name = "Copy of #{name}"
          new_name = base_name
          counter = 1
          while definition_store.get_definition(new_name)
            counter += 1
            new_name = "#{base_name} (#{counter})"
          end

          # Create the duplicate definition
          new_definition = original_definition.dup
          new_definition[:name] = new_name
          new_definition[:description] = "Copy of: #{original_definition[:description]}"

          begin
            definition_store.save_definition(new_name, new_definition)
            ADK::ActivityLog.log(:agent_created, { name: new_name, source: 'duplicate' }) rescue nil
            logger.info("Agent '#{name}' duplicated as '#{new_name}'")

            # Redirect to the new agent
            if request.xhr?
              headers 'HX-Redirect' => "/agents/#{URI.encode_www_form_component(new_name)}"
              status 200
              body ''
            else
              redirect "/agents/#{URI.encode_www_form_component(new_name)}"
            end
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Error duplicating agent: #{e.message}")
            halt 500, 'Error duplicating agent.'
          end
        end

        # GET /agents/:name/export - Export agent configuration as JSON.
        app.get '/agents/:name/export' do |name|
          logger.info("Received request to export agent '#{name}'")
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, 'Agent not found' unless agent_definition

          # Prepare export data (clean up internal fields)
          export_data = {
            name: agent_definition[:name],
            description: agent_definition[:description],
            model: agent_definition[:model],
            instruction: agent_definition[:instruction],
            tools: agent_definition[:tools],
            fallback_mode: agent_definition[:fallback_mode],
            agent_type: agent_definition[:agent_type],
            sub_agent_names: agent_definition[:sub_agent_names],
            mcp_servers_json: agent_definition[:mcp_servers_json]
          }.compact

          content_type 'application/json'
          attachment "#{name}.json"
          JSON.pretty_generate(export_data)
        end

        # GET /agents/:name - Display the detail page for a specific agent.
        app.get '/agents/:name' do |name|
          logger.info("GET /agents/#{name} route handler entered (from AgentDefinitionRoutes)")
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          agent_definition = nil
          begin
            agent_definition = definition_store.get_definition(name)
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error fetching definition for '#{name}' (from AgentDefinitionRoutes): #{e.message}")
            halt 500, 'Error retrieving agent definition.'
          end

          unless agent_definition
            logger.warn("Agent definition not found for '#{name}' in store (from AgentDefinitionRoutes).")
            halt 404,
                 slim(:error_404, locals: { title: 'Agent Not Found', message: "Definition for '#{name}' not found." })
          end

          mcp_display_string = begin
            parsed = JSON.parse(agent_definition[:mcp_servers_json])
            (parsed.is_a?(Array) && parsed.empty?) ? 'No MCP Server(s) Configured.' : pretty_json(parsed)
          rescue JSON::ParserError
            agent_definition[:mcp_servers_json]
          end

          # Use persistent_status from Redis for display
          # @agents doesn't persist across Sinatra request instances, so we rely on Redis
          is_running = (agent_definition[:persistent_status] == 'running')

          # Calculate tool count for header display
          tool_count = agent_definition[:tools]&.size || 0

          self.instance_variable_set(:@view_agent_data, {
                                       name: name,
                                       description: agent_definition[:description],
                                       running: is_running,
                                       model: agent_definition[:model],
                                       fallback_mode: agent_definition[:fallback_mode],
                                       instruction: agent_definition[:instruction],
                                       mcp_servers_json: agent_definition[:mcp_servers_json],
                                       mcp_display_string: mcp_display_string,
                                       configured_tool_names: agent_definition[:tools],
                                       tool_count: tool_count,
                                       # Include agent type and sub-agent names for hierarchy display
                                       agent_type: agent_definition[:agent_type]&.to_sym || :llm,
                                       sub_agent_names: agent_definition[:sub_agent_names] || []
                                     })

          # Tool metadata fetching logic (similar to what's in app.rb for this route)
          all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tm|
            params_array = []
            if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
              tm[:parameters].each { |pn, d|
                params_array << { name: pn, type: d[:type], description: d[:description], required: d[:required] }
              }
            end
            tm.merge(parameters: params_array, source: :native, source_detail: 'Native')
          end

          mcp_configs_list = []
          begin
            mcp_json = agent_definition[:mcp_servers_json]
            mcp_configs_list = JSON.parse(mcp_json) if mcp_json && !mcp_json.empty? && mcp_json != '[]'
          rescue JSON::ParserError => e
            logger.error("Invalid MCP JSON for agent '#{name}' (GET /agents/:name from AgentDefinitionRoutes): #{e.message}")
          end
          mcp_tool_fetch_results = fetch_mcp_tools(mcp_configs_list)

          fetched_mcp_tools_metadata = []
          mcp_tool_fetch_results.each do |result|
            if result[:status] == :success && result[:tools]
              result[:tools].each do |mcp_tool_schema|
                parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(
                  mcp_tool_schema.dig(:inputSchema,
                                      'properties') || {}, mcp_tool_schema.dig(:inputSchema, 'required') || []
                )
                fetched_mcp_tools_metadata << { name: mcp_tool_schema[:name].to_sym,
                                                description: mcp_tool_schema[:description] || '', parameters: parameters, source: :mcp, source_detail: "MCP (#{result[:server]})" }
              end
            end
          end

          all_available_tools_map = (all_native_tools_metadata + fetched_mcp_tools_metadata).each_with_object({}) { |tool, map|
            map[tool[:name]] ||= tool
          }
          configured_tool_syms = agent_definition[:tools].map(&:to_sym)
          view_tools = configured_tool_syms.map { |ts| all_available_tools_map[ts] }.compact

          needs_check_job = view_tools.any? { |tm|
            tm[:async] == true || ADK::GlobalToolManager.find_class(tm[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
          }
          if needs_check_job && !view_tools.any? { |t| t[:name] == :check_job_status }
            status_tool_meta = all_available_tools_map[:check_job_status]
            if status_tool_meta
              view_tools << status_tool_meta.dup.merge(
                description: "(Implicitly added) #{status_tool_meta[:description]}", source_detail: 'Native (Implicit)'
              )
            end
          end

          slim :agent, locals: { view_configured_tools: view_tools.sort_by! { |t|
            t[:name].to_s
          }, mcp_tool_results: mcp_tool_fetch_results }
        end

        # GET /agents/:name/edit/:field - Show edit form for a specific agent field.
        app.get '/agents/:name/edit/:field' do |name, field|
          supported_fields = %w[description model tools fallback mcp instruction hierarchy type]
          halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, 'Agent definition not found.' unless agent_definition

          agent_data = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode],
            mcp_servers_json: agent_definition[:mcp_servers_json],
            instruction: agent_definition[:instruction],
            agent_type: agent_definition[:agent_type]&.to_sym || :llm
          }

          view_locals = { agent_data: agent_data }

          if field == 'model'
            view_locals[:available_models] = ADK::Web::App::AVAILABLE_MODELS
          elsif field == 'tools'
            # Ensure configured_tool_names is an array of strings for the view's .include? check
            view_locals[:configured_tool_names] = agent_definition[:tools].map(&:to_s)
            native_tools = ADK::GlobalToolManager.list_all_tools

            mcp_configs = []
            begin
              mcp_json = agent_definition[:mcp_servers_json]
              mcp_configs = JSON.parse(mcp_json) if mcp_json && !mcp_json.empty? && mcp_json != '[]'
            rescue JSON::ParserError => e
              logger.error("Invalid MCP JSON for agent '#{name}' (edit tools - AgentDefinitionRoutes): #{e.message}")
            end
            mcp_results = fetch_mcp_tools(mcp_configs)

            fetched_mcp_meta = []
            mcp_results.each do |res|
              if res[:status] == :success && res[:tools]
                res[:tools].each do |schema|
                  params = ADK::Mcp::Util::SchemaConverter.json_to_adk(schema.dig(:inputSchema, 'properties') || {},
                                                                       schema.dig(:inputSchema, 'required') || [])
                  fetched_mcp_meta << { name: schema[:name].to_sym, description: schema[:description] || '',
                                        parameters: params }
                end
              end
            end
            view_locals[:all_available_tools] = (native_tools + fetched_mcp_meta).uniq { |t|
              t[:name]
            }.sort_by { |t| t[:name].to_s }
          elsif field == 'hierarchy'
            # Get all available agent definitions for sub-agent selection
            begin
              all_agent_definitions = definition_store.list_definitions
              # Filter out the current agent from available sub-agents to prevent self-reference
              filtered_agent_definitions = all_agent_definitions.reject { |def_data| def_data[:name].to_s == name.to_s }
              logger.info("Agent '#{name}' hierarchy edit view: Filtered out self-reference from #{all_agent_definitions.size} to #{filtered_agent_definitions.size} agents.")
              view_locals[:all_agent_definitions] = filtered_agent_definitions || []
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error fetching agent list for hierarchy edit: #{e.message}")
              view_locals[:all_agent_definitions] = []
            end
          end
          slim :"_edit_agent_#{field}", layout: false, locals: view_locals
        end

        # GET /agents/:name/display/tool_table - Render the tool table display partial.
        # NOTE: This specific route must be defined BEFORE the generic /display/:field route
        app.get '/agents/:name/display/tool_table' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store
          agent_definition = definition_store.get_definition(name)
          halt 404, 'Agent not found' unless agent_definition

          agent_data = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode], mcp_servers_json: agent_definition[:mcp_servers_json],
            running: (agent_definition[:persistent_status] == 'running')
          }
          configured_tool_names = agent_definition[:tools]
          configured_tool_syms = configured_tool_names.map(&:to_sym)

          all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map { |tm|
            tm.merge(source: :native, source_detail: 'Native')
          }

          mcp_configs_list = []
          begin
            mcp_json = agent_data[:mcp_servers_json]
            mcp_configs_list = JSON.parse(mcp_json) if mcp_json && !mcp_json.empty? && mcp_json != '[]'
          rescue JSON::ParserError => e
            logger.error("Invalid MCP JSON for agent '#{name}' (display_tool_table - AgentDefinitionRoutes): #{e.message}")
          end
          mcp_tool_fetch_results = fetch_mcp_tools(mcp_configs_list)

          fetched_mcp_tools_metadata = []
          mcp_tool_fetch_results.each do |result|
            if result[:status] == :success && result[:tools]
              result[:tools].each do |mcp_tool_schema|
                parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(
                  mcp_tool_schema.dig(:inputSchema,
                                      'properties') || {}, mcp_tool_schema.dig(:inputSchema, 'required') || []
                )
                fetched_mcp_tools_metadata << { name: mcp_tool_schema[:name].to_sym,
                                                description: mcp_tool_schema[:description] || '', parameters: parameters, source: :mcp, source_detail: "MCP (#{result[:server]})" }
              end
            end
          end

          all_available_tools_map = (all_native_tools_metadata + fetched_mcp_tools_metadata).each_with_object({}) { |tool, map|
            map[tool[:name]] ||= tool
          }
          view_configured_tools_list = configured_tool_syms.map { |ts| all_available_tools_map[ts] }.compact

          if view_configured_tools_list.any? { |tm|
            ADK::GlobalToolManager.find_class(tm[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
          }
            status_tool_meta = all_available_tools_map[:check_job_status]
            if status_tool_meta && !view_configured_tools_list.any? { |t| t[:name] == :check_job_status }
              view_configured_tools_list << status_tool_meta
            end
          end

          slim :_agent_tool_table, layout: false, locals: {
            agent_data: agent_data,
            view_configured_tools: view_configured_tools_list.sort_by { |t| t[:name].to_s },
            mcp_tool_results: mcp_tool_fetch_results
          }
        end

        # GET /agents/:name/display/:field - Display an agent field (after edit cancel).
        app.get '/agents/:name/display/:field' do |name, field|
          supported_fields = %w[description model tools fallback mcp instruction hierarchy type]
          halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, 'Agent definition not found.' unless agent_definition

          response_locals = { show_edit_button: true }
          agent_data_for_display = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode],
            mcp_servers_json: agent_definition[:mcp_servers_json],
            instruction: agent_definition[:instruction],
            agent_type: agent_definition[:agent_type]&.to_sym || :llm
          }

          if field == 'mcp'
            mcp_json_val = agent_definition[:mcp_servers_json]
            agent_data_for_display[:mcp_display_string] = begin
              parsed = JSON.parse(mcp_json_val)
              (parsed.is_a?(Array) && parsed.empty?) ? 'No MCP Server(s) Configured.' : pretty_json(parsed)
            rescue JSON::ParserError
              mcp_json_val
            end
          elsif field == 'tools'
            # ... existing code ...
          elsif field == 'hierarchy'
            # Add sub_agent_names for hierarchy display
            agent_data_for_display[:sub_agent_names] = agent_definition[:sub_agent_names] || []
            agent_data_for_display[:agent_type] = agent_definition[:agent_type]&.to_sym || :llm
          elsif field == 'type'
            # Add agent_type for type display
            agent_data_for_display[:agent_type] = agent_definition[:agent_type]&.to_sym || :llm
          end
          response_locals[:agent_data] = agent_data_for_display

          # Special handling for tool table display route as it has its own logic
          if field == 'tools'
            # This is for the specific tool_table display, which is a full table, not just a field.
            # We should call the dedicated route for this instead of trying to render _display_agent_tools
            # For now, this will render _display_agent_tools.slim which might not exist or be what's intended.
            # The original app.rb has a GET /agents/:name/display/tool_table. We should use that.
            # To simplify, we'll assume _display_agent_tools shows basic tool names if it exists.
            # The plan lists GET /agents/:name/display/tool_table separately.
            configured_tool_names_str = agent_definition[:tools]
            all_native_tools = ADK::GlobalToolManager.list_all_tools
            response_locals[:configured_tools] = configured_tool_names_str.map { |tn|
              all_native_tools.find { |t| t[:name].to_s == tn }
            }.compact
          end

          slim :"_display_agent_#{field}", layout: false, locals: response_locals
        end

        # PUT /agents/:name/update/:field - Update a specific field of an agent definition.
        app.put '/agents/:name/update/:field' do |name, field|
          supported_fields = %w[description model tools fallback mcp instruction type hierarchy]
          halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, 'Definition Store unavailable.' unless definition_store

          field_to_update_in_store = case field
                                     when 'fallback' then 'fallback_mode'
                                     when 'mcp' then 'mcp_servers_json'
                                     when 'type' then 'agent_type'
                                     else field
                                     end
          new_value_for_store = nil
          agent_data_for_display_partial = { name: name }

          case field
          when 'tools'
            current_definition = definition_store.get_definition(name)
            halt 404, 'Agent not found for tool update.' unless current_definition
            mcp_json = current_definition[:mcp_servers_json]
            native_tool_names = ADK::GlobalToolManager.list_all_tools.map { |t| t[:name].to_s }
            mcp_configs = JSON.parse(mcp_json) rescue []
            mcp_results = fetch_mcp_tools(mcp_configs)
            mcp_tool_names = mcp_results.flat_map { |res|
              res[:status] == :success ? res[:tools].map { |t|
                t[:name].to_s
              } : []
            }.uniq
            all_valid_tool_names = (native_tool_names + mcp_tool_names).uniq

            submitted_tools = params['tools'] || []
            new_value_for_store = submitted_tools.select { |st| all_valid_tool_names.include?(st) }
            # For display partial:
            # Rebuild metadata for validated tools
            all_native_meta = ADK::GlobalToolManager.list_all_tools.map do |tm|
              params_array = []
              if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
                tm[:parameters].each { |pn, d|
                  params_array << { name: pn, type: d[:type], description: d[:description], required: d[:required] }
                }
              end
              tm.merge(parameters: params_array, source: :native, source_detail: 'Native')
            end
            fetched_mcp_meta = []
            mcp_results.each do |res|
              if res[:status] == :success && res[:tools]
                res[:tools].each do |schema|
                  params = ADK::Mcp::Util::SchemaConverter.json_to_adk(
                    schema.dig(:inputSchema, 'properties') || {}, schema.dig(:inputSchema, 'required') || []
                  )
                  fetched_mcp_meta << { name: schema[:name].to_sym, description: schema[:description] || '',
                                        parameters: params, source: :mcp, source_detail: "MCP (#{res[:server]})" }
                end
              end
            end
            all_available_meta_map = (all_native_meta + fetched_mcp_meta).each_with_object({}) { |tool, map|
              map[tool[:name]] ||= tool
            }
            agent_data_for_display_partial[:view_configured_tools] = new_value_for_store.map { |tn|
              all_available_meta_map[tn.to_sym]
            }.compact
            agent_data_for_display_partial[:mcp_tool_results] = mcp_results # For errors
          when 'mcp'
            submitted_json = params['value']&.strip
            new_value_for_store = (submitted_json.nil? || submitted_json.empty?) ? '[]' : submitted_json
            begin
              parsed = JSON.parse(new_value_for_store)
              raise JSON::ParserError, 'Input must be a valid JSON array.' unless parsed.is_a?(Array)
            rescue JSON::ParserError => e
              current_def = definition_store.get_definition(name)
              edit_locals = {
                agent_data: { name: name,
                              mcp_servers_json: current_def ? current_def[:mcp_servers_json] : new_value_for_store }, error_message: "Invalid JSON: #{e.message}"
              }
              halt 200, slim(:_edit_agent_mcp, layout: false, locals: edit_locals) # Return 200 for HTMX form error display
            end
            agent_data_for_display_partial[:mcp_servers_json] = new_value_for_store
            agent_data_for_display_partial[:mcp_display_string] =
              (JSON.parse(new_value_for_store).empty?) ? 'No MCP Server(s) Configured.' : pretty_json(JSON.parse(new_value_for_store))

          when 'fallback'
            submitted_value = params['value']&.strip
            unless %w[error echo].include?(submitted_value)
              current_def = definition_store.get_definition(name)
              edit_locals = {
                agent_data: { name: name,
                              fallback_mode: current_def ? current_def[:fallback_mode] : :error }, error_message: 'Invalid fallback.'
              }
              halt 400, slim(:_edit_agent_fallback, layout: false, locals: edit_locals)
            end
            new_value_for_store = submitted_value.to_sym
            agent_data_for_display_partial[:fallback_mode] = new_value_for_store
          when 'type'
            submitted_value = params['agent_type']&.strip
            unless %w[llm sequential parallel loop].include?(submitted_value)
              current_def = definition_store.get_definition(name)
              edit_locals = {
                agent_data: { name: name, agent_type: current_def ? current_def[:agent_type]&.to_sym : :llm },
                error_message: 'Invalid agent type.'
              }
              halt 400, slim(:_edit_agent_type, layout: false, locals: edit_locals)
            end

            # Check if switching to LLM type and clear sub-agent lists if so
            if submitted_value == 'llm'
              # Get current definition to check current type
              current_def = definition_store.get_definition(name)
              current_type = current_def ? current_def[:agent_type]&.to_s : nil

              # Only clear sub-agents if switching from a workflow type to LLM
              if current_type && %w[sequential parallel loop].include?(current_type)
                # Update sub-agent fields first
                begin
                  definition_store.update_definition(name, {
                                                       sub_agent_names: [],
                                                       sequential_sub_agent_names: [],
                                                       parallel_sub_agent_names: [],
                                                       loop_sub_agent_names: []
                                                     })
                  logger.info("Agent '#{name}' switched from '#{current_type}' to 'llm', cleared all sub-agent lists.")
                rescue => e
                  logger.error("Failed to clear sub-agent lists for agent '#{name}': #{e.message}")
                end
              end
            end

            new_value_for_store = submitted_value
            agent_data_for_display_partial[:agent_type] = submitted_value.to_sym
          when 'instruction', 'description', 'model'
            new_value_for_store = params['value']&.strip || (field == 'instruction' ? '' : nil)
            if new_value_for_store.nil? && field != 'instruction' # Description and model cannot be nil (empty is ok for description)
              current_def = definition_store.get_definition(name)
              edit_locals = {
                agent_data: { name: name, description: current_def[:description], model: current_def[:model],
                              instruction: current_def[:instruction] }, error_message: "#{field.capitalize} cannot be empty."
              }
              halt 400, slim(:"_edit_agent_#{field}", layout: false, locals: edit_locals)
            end
            agent_data_for_display_partial[field.to_sym] = new_value_for_store
          when 'hierarchy'
            # Get selected sub-agent names from the form
            sub_agent_names = params['sub_agent_names'] || []

            # Update the definition via a separate field
            begin
              update_success = definition_store.update_definition(name, sub_agent_names: sub_agent_names)
              halt 404, 'Agent not found for update.' unless update_success
              logger.info("Agent '#{name}' hierarchy updated with #{sub_agent_names.size} sub-agents (from AgentDefinitionRoutes)")

              # Refresh agent data for display
              updated_definition = definition_store.get_definition(name)
              agent_data = {
                name: name,
                description: updated_definition[:description],
                agent_type: updated_definition[:agent_type]&.to_sym || :llm,
                sub_agent_names: updated_definition[:sub_agent_names] || [],
                show_edit_button: true
              }

              # Return the updated display partial directly
              return slim :_display_agent_hierarchy, layout: false, locals: { agent_data: agent_data }
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error updating agent hierarchy: #{e.message}")
              halt 500, 'Error updating agent hierarchy.'
            end
          end

          begin
            update_success = definition_store.update_definition(name,
                                                                { field_to_update_in_store.to_sym => new_value_for_store })
            halt 404, 'Agent not found for update.' unless update_success
            logger.info("Agent '#{name}' field '#{field_to_update_in_store}' updated (from AgentDefinitionRoutes).")

            was_running = active_agents_hash.key?(name)
            if was_running
              logger.info("Agent '#{name}' config updated while running. Triggering auto-restart (from AgentDefinitionRoutes).")
              self.send(:_stop_agent, name)
              newly_started_agent = self.send(:_start_agent, name)
              agent_data_for_display_partial[:running] = !newly_started_agent.nil?
              headers 'HX-Trigger-After-Swap' => (agent_data_for_display_partial[:running] ? 'showRestartToast' : 'showRestartErrorToast')
            else
              agent_data_for_display_partial[:running] = false
            end

            # Re-fetch full definition for display consistency
            full_updated_def = definition_store.get_definition(name)
            agent_data_for_display_partial.merge!(
              description: full_updated_def[:description], model: full_updated_def[:model],
              fallback_mode: full_updated_def[:fallback_mode], mcp_servers_json: full_updated_def[:mcp_servers_json],
              instruction: full_updated_def[:instruction]
            )
            # Ensure mcp_display_string is set if field was 'mcp'
            if field == 'mcp'
              agent_data_for_display_partial[:mcp_display_string] ||= (JSON.parse(new_value_for_store).empty?) ? 'No MCP Server(s) Configured.' : pretty_json(JSON.parse(new_value_for_store))
            end

            response_locals_for_display = { agent_data: agent_data_for_display_partial, show_edit_button: true }

            if field == 'tools'
              # For tools, the _agent_tool_table partial is rendered
              # It expects :view_configured_tools and :mcp_tool_results
              # We already prepared agent_data_for_display_partial[:view_configured_tools]
              # and agent_data_for_display_partial[:mcp_tool_results]
              slim :_agent_tool_table, layout: false, locals: agent_data_for_display_partial # Pass the whole hash
            else
              response_html = slim :"_display_agent_#{field}", layout: false, locals: response_locals_for_display

              # Add OOB update for hierarchy section if changing to LLM type
              if field == 'type' && new_value_for_store == 'llm'
                # Add an out-of-band swap to update the hierarchy section with empty sub-agents
                empty_hierarchy_data = {
                  name: name,
                  agent_type: :llm,
                  sub_agent_names: [],
                  show_edit_button: true
                }
                response_html += "<div id=\"agent-hierarchy-display\" hx-swap-oob=\"true\">" +
                                 slim(:_display_agent_hierarchy, layout: false, locals: { agent_data: empty_hierarchy_data }) +
                                 "</div>"
              end

              response_html
            end
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error updating agent '#{name}' (from AgentDefinitionRoutes): #{e.message}")
            halt 500, 'Error updating agent definition.'
          rescue ArgumentError => e # From store validation
            halt 400, "Invalid input: #{e.message}"
          end
        end

        # PUT /agents/:name/update/hierarchy - Update agent hierarchy
        app.put '/agents/:name/update/hierarchy' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, 'Definition Store unavailable.' unless definition_store

          begin
            agent_definition = definition_store.get_definition(name)
            halt 404, 'Agent definition not found.' unless agent_definition

            # Get selected sub-agent names from the form
            sub_agent_names = params['sub_agent_names'] || []

            # Update the definition with the new sub_agent_names
            definition_store.update_definition(name, sub_agent_names: sub_agent_names)

            # Refresh agent data for display
            updated_definition = definition_store.get_definition(name)
            agent_data = {
              name: name,
              description: updated_definition[:description],
              agent_type: updated_definition[:agent_type]&.to_sym || :llm,
              sub_agent_names: updated_definition[:sub_agent_names] || []
            }

            # Return the updated display partial
            slim :_display_agent_hierarchy, layout: false, locals: { agent_data: agent_data }
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error updating agent hierarchy: #{e.message}")
            halt 500, 'Error updating agent hierarchy.'
          end
        end

        # PUT /agents/:name/update/type - Update agent type
        app.put '/agents/:name/update/type' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, 'Definition Store unavailable.' unless definition_store

          begin
            agent_definition = definition_store.get_definition(name)
            halt 404, 'Agent definition not found.' unless agent_definition

            # Get the submitted agent type value
            submitted_value = params['agent_type']&.strip

            # Validate agent type
            unless %w[llm sequential parallel loop].include?(submitted_value)
              edit_locals = {
                agent_data: {
                  name: name,
                  agent_type: agent_definition[:agent_type]&.to_sym || :llm
                },
                error_message: 'Invalid agent type.'
              }
              halt 400, slim(:_edit_agent_type, layout: false, locals: edit_locals)
            end

            # Update the definition with the new agent type
            update_params = { agent_type: submitted_value }

            # Clear sub-agent lists if switching to LLM agent
            if submitted_value == 'llm'
              update_params[:sub_agent_names] = []
              update_params[:sequential_sub_agent_names] = []
              update_params[:parallel_sub_agent_names] = []
              update_params[:loop_sub_agent_names] = []
              logger.info("Agent '#{name}' switched to LLM type, clearing all sub-agent lists.")
            end

            update_success = definition_store.update_definition(name, update_params)
            halt 404, 'Agent not found for update.' unless update_success
            logger.info("Agent '#{name}' type updated to '#{submitted_value}' (from AgentDefinitionRoutes).")

            # Handle agent restart if it was running
            was_running = active_agents_hash.key?(name)
            if was_running
              logger.info("Agent '#{name}' type updated while running. Triggering auto-restart (from AgentDefinitionRoutes).")
              self.send(:_stop_agent, name)
              newly_started_agent = self.send(:_start_agent, name)

              # Set headers to trigger toast notification
              headers 'HX-Trigger-After-Swap' => (newly_started_agent ? 'showRestartToast' : 'showRestartErrorToast')
            end

            # Refresh agent data for display
            updated_definition = definition_store.get_definition(name)
            agent_data = {
              name: name,
              agent_type: updated_definition[:agent_type]&.to_sym || :llm,
              running: active_agents_hash.key?(name),
              show_edit_button: true
            }

            # Return the updated display partial
            response_html = slim :_display_agent_type, layout: false, locals: { agent_data: agent_data }

            # Add an HTMX trigger to refresh the hierarchy section if switching to LLM
            if submitted_value == 'llm'
              # Add an out-of-band swap to update the hierarchy section with empty sub-agents
              empty_hierarchy_data = {
                name: name,
                agent_type: :llm,
                sub_agent_names: [],
                show_edit_button: true
              }
              response_html += "<div id=\"agent-hierarchy-display\" hx-swap-oob=\"true\">" +
                               slim(:_display_agent_hierarchy, layout: false, locals: { agent_data: empty_hierarchy_data }) +
                               "</div>"
            end

            response_html
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error updating agent type: #{e.message}")
            halt 500, 'Error updating agent type.'
          end
        end
      end
    end
  end
end
