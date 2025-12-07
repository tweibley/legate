# File: lib/adk/web/routes/agent_interaction_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentInteractionRoutes
      # Helper to update the last_run_at timestamp for an agent
      def self.update_agent_last_run(definition_store, agent_name, logger)
        return unless definition_store

        begin
          definition_store.update_definition(agent_name, { 'last_run_at' => Time.now.iso8601 })
          logger.debug("Updated last_run_at for agent '#{agent_name}'")
        rescue => e
          logger.warn("Failed to update last_run_at for agent '#{agent_name}': #{e.message}")
        end
      end

      def self.registered(app)
        # GET /agents/:name/chat - Display the chat interface for an agent.
        app.get '/agents/:name/chat' do |name|
          logger.debug "GET /agents/#{name}/chat: Entry. web_user_id: #{session[:web_user_id]}, session_id: #{request.session_options[:id]}"
          # `self` is the Sinatra app instance
          definition_store = self.instance_variable_get(:@definition_store)
          session_service = self.instance_variable_get(:@session_service)
          active_agents_hash = self.instance_variable_get(:@agents)

          halt 503, 'Definition Store unavailable.' unless definition_store
          halt 503, 'Session Service unavailable.' unless session_service # Added check for session_service

          agent_definition = nil
          begin
            agent_definition = definition_store.get_definition(name)
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error fetching definition for '#{name}' chat (from AgentInteractionRoutes): #{e.message}")
            halt 500, 'Error retrieving agent definition.'
          end
          unless agent_definition
            logger.warn("Agent definition not found for '#{name}' in store (GET /chat from AgentInteractionRoutes).")
            halt 404,
                 slim(:error_404, locals: { title: 'Agent Not Found', message: "Definition for '#{name}' not found." })
          end

          agent_description_for_view = agent_definition[:description]
          is_running = active_agents_hash.key?(name)
          web_user_id = session[:web_user_id] # From the before filter

          # --- BEGIN NEW MULTI-SESSION LOGIC ---
          active_adk_session_id = nil
          active_session_object = nil
          session_load_error_occurred = false # Flag if a chosen session ID failed to load

          # Initialize Sinatra session structure for storing active sessions per agent
          session[:active_agent_sessions] ||= {}

          # 1. Check for 'desired_session_id' query parameter
          desired_id_from_param = params[:desired_session_id]
          if desired_id_from_param
            logger.debug "Attempting to use desired_session_id: #{desired_id_from_param} for agent '#{name}', user '#{web_user_id}'"
            begin
              potential_session = session_service.get_session(session_id: desired_id_from_param)
              if potential_session && potential_session.user_id == web_user_id && potential_session.app_name == name
                active_adk_session_id = desired_id_from_param
                active_session_object = potential_session
                logger.info "Successfully loaded session via desired_session_id: #{active_adk_session_id}"
              else
                logger.warn "desired_session_id '#{desired_id_from_param}' is invalid, not found, or does not belong to user '#{web_user_id}' for agent '#{name}'. Ignoring."
              end
            rescue => e
              logger.error "Error trying to load desired_session_id '#{desired_id_from_param}': #{e.message}"
              session_load_error_occurred = true
            end
          end

          # 2. If no active session yet, try the stored active ID from the Sinatra session
          unless active_adk_session_id
            stored_active_id = session[:active_agent_sessions][name]
            if stored_active_id
              logger.debug "Attempting to use stored active session ID: #{stored_active_id} for agent '#{name}', user '#{web_user_id}'"
              begin
                potential_session = session_service.get_session(session_id: stored_active_id)
                if potential_session && potential_session.user_id == web_user_id && potential_session.app_name == name
                  active_adk_session_id = stored_active_id
                  active_session_object = potential_session
                  logger.info "Successfully loaded stored active session ID: #{active_adk_session_id}"
                else
                  logger.warn "Stored active session ID '#{stored_active_id}' is stale or invalid for user '#{web_user_id}' / agent '#{name}'. Clearing it."
                  session[:active_agent_sessions].delete(name)
                  session_load_error_occurred = true
                end
              rescue => e
                logger.error "Error trying to load stored active session ID '#{stored_active_id}': #{e.message}"
                session[:active_agent_sessions].delete(name) # Clear if error
                session_load_error_occurred = true
              end
            end
          end

          # 3. If still no active session, list all sessions for the user/agent and pick the most recently updated
          unless active_adk_session_id
            logger.debug "No valid active session from params or Sinatra session. Listing sessions for agent '#{name}', user '#{web_user_id}'"
            begin
              user_agent_sessions = session_service.list_sessions(app_name: name, user_id: web_user_id)
              if user_agent_sessions && !user_agent_sessions.empty?
                latest_session = user_agent_sessions.sort_by(&:updated_at).last
                if latest_session
                  active_adk_session_id = latest_session.id
                  active_session_object = latest_session
                  logger.info "Found existing sessions. Set active to most recently updated: #{active_adk_session_id}"
                else
                  logger.warn "list_sessions for agent '#{name}', user '#{web_user_id}' returned sortable but empty/nil data."
                  session_load_error_occurred = true
                end
              else
                logger.info "No existing sessions found for agent '#{name}', user '#{web_user_id}'. Will create a new one."
              end
            rescue => e
              logger.error "Error listing sessions for agent '#{name}', user '#{web_user_id}': #{e.message}"
              halt 500, 'Error retrieving session list.'
            end
          end

          # 4. If still no active session object, create a new one.
          unless active_session_object
            logger.info "No active session determined or loaded. Creating new session for agent '#{name}', user '#{web_user_id}'."
            if session_load_error_occurred
              logger.warn 'Proceeding to create new session because a previous attempt to load a specific session failed.'
            end
            begin
              new_session = session_service.create_session(app_name: name, user_id: web_user_id, initial_state: {})
              active_adk_session_id = new_session.id
              active_session_object = new_session
              logger.info "Created new ADK session: #{active_adk_session_id}"
              session_load_error_occurred = false
            rescue => e
              logger.error "Failed to create new ADK session for agent '#{name}', user '#{web_user_id}': #{e.message}"
              halt 500, 'Failed to initialize chat session.'
            end
          end

          # 5. Ensure the determined active ADK session ID is stored in the Sinatra session
          if active_adk_session_id
            session[:active_agent_sessions][name] = active_adk_session_id
            logger.debug "Ensured active ADK session ID '#{active_adk_session_id}' is stored for agent '#{name}'."
          else
            logger.fatal "CRITICAL: Could not determine or create an active session ID for agent '#{name}', user '#{web_user_id}'. Halting."
            halt 500, 'Critical error: Unable to establish an active chat session.'
          end

          if session_load_error_occurred
            logger.warn 'A previously selected or stored session could not be loaded. A new session was started or the latest available was used.'
          end

          # 6. Load chat history for the active session
          chat_history_events_list = active_session_object&.events || []
          logger.debug "Loaded #{chat_history_events_list.count} events for active session '#{active_adk_session_id}'"

          # 7. Load all sessions for this agent/user for the sidebar list
          previous_sessions_list = []
          begin
            all_sessions_for_user_agent = session_service.list_sessions(app_name: name, user_id: web_user_id)
            if all_sessions_for_user_agent
              previous_sessions_list = all_sessions_for_user_agent.sort_by(&:updated_at).reverse
              logger.debug "Loaded #{previous_sessions_list.count} total sessions for agent '#{name}', user '#{web_user_id}' for sidebar."
            end
          rescue => e
            logger.error "Failed to load all previous sessions list for agent '#{name}', user '#{web_user_id}': #{e.message}"
          end
          # --- END NEW MULTI-SESSION LOGIC ---

          self.instance_variable_set(:@agent_data,
                                     { name: name, description: agent_description_for_view, running: is_running })
          self.instance_variable_set(:@active_session_details, active_session_object)
          self.instance_variable_set(:@previous_sessions_list, previous_sessions_list)
          self.instance_variable_set(:@chat_history_events, chat_history_events_list)
          slim :chat
        end

        # POST /agents/:name/chat - Process a user message from the chat interface.
        app.post '/agents/:name/chat' do |name|
          content_type :html
          active_agents_hash = self.instance_variable_get(:@agents)
          session_service = self.instance_variable_get(:@session_service)
          web_user_id = session[:web_user_id]

          current_agent_instance = active_agents_hash[name]
          user_message_text = params['message']&.strip

          session[:active_agent_sessions] ||= {}
          active_adk_session_id = session[:active_agent_sessions][name]

          view_locals = {
            user_message: user_message_text || '[Empty Message]',
            agent_result: nil,
            agent_name: current_agent_instance ? current_agent_instance.name : name
          }

          current_adk_session_object = nil
          if active_adk_session_id
            begin
              current_adk_session_object = session_service.get_session(session_id: active_adk_session_id)
              unless current_adk_session_object && current_adk_session_object.user_id == web_user_id && current_adk_session_object.app_name == name
                logger.error("Chat POST Error: Active session ID '#{active_adk_session_id}' is invalid. Redirecting.")
                session[:active_agent_sessions].delete(name)
                redirect "/agents/#{name}/chat"
              end
            rescue => e
              logger.error("Chat POST Error: Failed to retrieve session '#{active_adk_session_id}': #{e.message}. Redirecting.")
              session[:active_agent_sessions].delete(name)
              redirect "/agents/#{name}/chat"
            end
          else
            logger.error("Chat POST Error: No active ADK session ID found for agent '#{name}'. Redirecting.")
            redirect "/agents/#{name}/chat"
          end

          unless current_agent_instance
            view_locals[:agent_result] = { status: :error, error_message: "[Error: Agent '#{name}' is not running.]" }
            halt 400, slim(:_chat_message, layout: false, locals: view_locals)
          end
          if user_message_text.nil? || user_message_text.empty?
            view_locals[:agent_result] = { status: :error, error_message: '[Error: Message cannot be empty.]' }
            halt 400, slim(:_chat_message, layout: false, locals: view_locals)
          end

          begin
            logger.info("Agent '#{name}' processing chat in session '#{active_adk_session_id}' for user '#{web_user_id}': #{user_message_text}")
            final_event_or_error = current_agent_instance.run_task(
              session_id: active_adk_session_id,
              user_input: user_message_text,
              session_service: session_service
            )
            logger.info("Agent '#{name}' task processing complete for session '#{active_adk_session_id}'. Final result: #{final_event_or_error.inspect}")
            view_locals[:agent_result] = final_event_or_error

            # Track last run time
            AgentInteractionRoutes.update_agent_last_run(definition_store, name, logger)

            updated_session_object = nil
            if current_adk_session_object
              begin
                updated_session_object = session_service.get_session(session_id: current_adk_session_object.id)
              rescue => e
                logger.error("Chat POST: Failed to re-fetch session '#{current_adk_session_object.id}' for stats update: #{e.message}")
                updated_session_object = current_adk_session_object
              end
            end

            chat_message_html = slim(:_chat_message, layout: false, locals: view_locals)
            session_info_inner_html = slim(:_active_session_info, layout: false,
                                                                  locals: { active_session_details: updated_session_object })
            active_session_info_oob_wrapper_html = %(<div id="active-session-info" class="mt-2" hx-swap-oob="outerHTML">#{session_info_inner_html}</div>)

            status 200
            chat_message_html + active_session_info_oob_wrapper_html
          rescue => e
            logger.error("Error processing chat for agent #{name}, session '#{active_adk_session_id}': #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
            view_locals[:agent_result] =
              { status: :error, error_message: "[Internal Error executing task: #{e.message}]" }
            halt 500, slim(:_chat_message, layout: false, locals: view_locals)
          end
        end

        # POST /agents/:name/execute - Execute a task directly via JSON input.
        app.post '/agents/:name/execute' do
          name = params[:name]; content_type :html # Change to HTML for the richer response
          active_agents_hash = self.instance_variable_get(:@agents)
          session_service = self.instance_variable_get(:@session_service)
          agent_instance = active_agents_hash[name]
          final_result_content_for_diagram = nil # To store content for mermaid
          task_desc = nil # Initialize task_desc

          error_handler = lambda do |message, code = 400|
            # For HTML response, format error differently
            halt code, format_execution_result_html({ status: :error, error_message: message })
          end

          success_handler = lambda do |result_hash, original_task_description|
            mermaid_diagram_html = ''
            current_final_content = result_hash # Use the direct result_hash

            if current_final_content.is_a?(Hash) && current_final_content[:plan_details]
              mermaid_def = generate_mermaid_sequence_diagram(current_final_content, original_task_description)
              unless mermaid_def.empty?
                # Ensure unique ID for mermaid modal trigger
                mermaid_button_id = "direct-exec-mermaid-btn-#{name.gsub(/[^a-zA-Z0-9_-]/, '-')}-#{SecureRandom.hex(4)}"
                mermaid_diagram_html = <<~HTML
                  <div class="mt-3 pt-3" style="border-top: 1px dashed #ccc;">
                    <button class="button is-small is-info is-light mb-2 show-mermaid-flow-btn"
                            id="#{mermaid_button_id}"
                            data-mermaid-definition="#{Rack::Utils.escape_html(mermaid_def)}">
                      <span class="icon is-small"><i class="fas fa-project-diagram"></i></span>
                      <span>Toggle Execution Flow</span>
                    </button>
                  </div>
                HTML
              end
            end
            formatted_result_html = format_execution_result_html(result_hash)
            formatted_result_html + mermaid_diagram_html
          end

          error_handler.call("Error: Agent '#{name}' not found or not running.", 400) unless agent_instance
          task_json_string = params['task_json']
          error_handler.call("Error: Missing 'task_json' data.",
                             400) unless task_json_string && !task_json_string.empty?

          exec_params = nil; tool_to_exec = nil; parsed_data = nil
          begin
            parsed_data = JSON.parse(task_json_string)
            if parsed_data.is_a?(Hash)
              if parsed_data.key?('tool_name') && parsed_data.key?('task') && parsed_data.key?('parameters')
                tool_to_exec = parsed_data['tool_name']&.strip
                task_desc = parsed_data['task'] # Used for planner and mermaid
                exec_params = parsed_data['parameters']
                error_handler.call("Error: Missing 'tool_name' in JSON for direct execution.",
                                   400) if tool_to_exec.nil? || tool_to_exec.empty?
                error_handler.call("Error: Missing or invalid 'parameters' object in JSON for direct execution.",
                                   400) unless exec_params.is_a?(Hash)
              elsif parsed_data.key?('task')
                task_desc = parsed_data['task'] # Used for planner and mermaid
                error_handler.call(
                  "Error: Invalid JSON. Use {'task': '...'} or {'tool_name': ..., 'task': ..., 'parameters': {...}}.", 400
                ) unless (parsed_data.keys - ['task']).empty?
              else
                error_handler.call("Error: Invalid JSON structure. Missing 'task' key.", 400)
              end
            else
              error_handler.call('Error: Input must be a JSON object.', 400)
            end
          rescue JSON::ParserError => e
            logger.warn("Invalid JSON for /execute (AgentInteractionRoutes): #{e.message}. Input: #{task_json_string}")
            error_handler.call("Error: Invalid JSON format - #{e.message}", 400)
          end
          error_handler.call('Error: Missing task description.',
                             400) if tool_to_exec.nil? && (task_desc.nil? || task_desc.empty?)

          temp_adk_session = nil
          begin
            original_input_for_diagram = task_desc # Capture before potential modification if tool_to_exec
            if tool_to_exec
              logger.info("Agent '#{name}' executing DIRECT tool '#{tool_to_exec}' (AgentInteractionRoutes) with params: #{exec_params.inspect}")
              tool_instance_to_run = agent_instance.find_tool(tool_to_exec.to_sym)
              error_handler.call("Error: Tool '#{tool_to_exec}' not configured for agent '#{name}'.",
                                 400) unless tool_instance_to_run
              temp_adk_session = session_service.create_session(app_name: name,
                                                                user_id: "web_direct_#{SecureRandom.hex(4)}")
              tool_ctx = ADK::ToolContext.new(session_id: temp_adk_session.id, user_id: temp_adk_session.user_id,
                                              app_name: temp_adk_session.app_name, tool_registry: agent_instance.tool_registry)
              result = tool_instance_to_run.execute(exec_params.transform_keys(&:to_sym), tool_ctx)
              # For direct tool execution, plan_details might not exist unless the tool itself populates it (unlikely)
              # To ensure mermaid can work, we can construct a minimal plan_details for this single step.
              # This makes the success_handler's mermaid logic more robust.
              minimal_plan_details = [{ tool_name: tool_to_exec.to_sym, params: exec_params.transform_keys(&:to_sym),
                                        result: result }]
              final_result_content_for_diagram = result.merge(plan_details: minimal_plan_details)
              # Track last run time
              definition_store = self.instance_variable_get(:@definition_store)
              AgentInteractionRoutes.update_agent_last_run(definition_store, name, logger)
              success_handler.call(final_result_content_for_diagram, original_input_for_diagram)
            else
              logger.info("Agent '#{name}' executing task via PLANNER (AgentInteractionRoutes): #{task_desc}")
              temp_adk_session = session_service.create_session(app_name: name,
                                                                user_id: "web_direct_#{SecureRandom.hex(4)}")
              final_result = agent_instance.run_task(session_id: temp_adk_session.id, user_input: task_desc,
                                                     session_service: session_service)
              content_to_show = final_result.is_a?(ADK::Event) ? final_result.content : final_result
              # Track last run time
              definition_store = self.instance_variable_get(:@definition_store)
              AgentInteractionRoutes.update_agent_last_run(definition_store, name, logger)
              success_handler.call(content_to_show, original_input_for_diagram)
            end
          rescue => e
            logger.error "Error during agent execution for '#{name}' (AgentInteractionRoutes): #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
            error_handler.call("Error: Internal server error during task execution: #{e.message}", 500)
          ensure
            session_service.delete_session(session_id: temp_adk_session.id) if temp_adk_session
          end
        end

        # GET /agents/:name/generate_example_task - Generate example task JSON for an agent.
        app.get '/agents/:name/generate_example_task' do |name|
          content_type :json
          logger.info("Generating example task for agent: #{name} (from AgentInteractionRoutes)")
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, json(error: 'Definition Store unavailable.') unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, json(error: "Agent definition not found for '#{name}'") unless agent_definition

          agent_model_name = agent_definition[:model]
          configured_tool_names_str = agent_definition[:tools]
          mcp_servers_config_json = agent_definition[:mcp_servers_json]

          configured_tool_syms_list = configured_tool_names_str.map(&:to_sym)

          if configured_tool_syms_list.empty? && mcp_servers_config_json == '[]'
            return json(example: { task: "Agent '#{name}' has no tools. Cannot generate example." })
          end

          native_tools_meta = ADK::GlobalToolManager.list_all_tools.map do |tm|
            params = []
            if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
              tm[:parameters].each { |pn, d|
                params << { name: pn, type: d[:type], description: d[:description], required: d[:required] }
              }
            end
            tm.merge(parameters: params, source: :native)
          end

          mcp_configs_list = JSON.parse(mcp_servers_config_json) rescue []
          mcp_fetch_results = fetch_mcp_tools(mcp_configs_list) # Helper method from app instance

          mcp_tools_meta = []
          mcp_fetch_results.each do |res|
            if res[:status] == :success && res[:tools]
              res[:tools].each do |schema|
                params = ADK::Mcp::Util::SchemaConverter.json_to_adk(schema.dig(:inputSchema, 'properties') || {},
                                                                     schema.dig(:inputSchema, 'required') || [])
                mcp_tools_meta << { name: schema[:name].to_sym, description: schema[:description] || '',
                                    parameters: params, source: :mcp }
              end
            end
          end

          all_tools_map = (native_tools_meta + mcp_tools_meta).each_with_object({}) { |t, map| map[t[:name]] ||= t }
          final_configured_tools_meta = configured_tool_syms_list.map { |sym| all_tools_map[sym] }.compact

          if final_configured_tools_meta.empty?
            return json(example: { task: "Agent '#{name}' tools metadata incomplete. Cannot generate." })
          end

          tool_details_for_prompt = final_configured_tools_meta.map do |meta|
            params_str = meta[:parameters].empty? ? 'None' : meta[:parameters].map { |p|
              "#{p[:name]} (#{p[:type]}, #{p[:required] ? 'required' : 'optional'})"
            }.join(', ')
            "- Tool: #{meta[:name]}\n  Description: #{meta[:description]}\n  Parameters: #{params_str}"
          end.join("\n")

          gemini_prompt = <<~PROMPT
            Based on the following tools configured for an agent, generate a single, simple example JSON object representing a task that uses ONE of these tools.

            The JSON object MUST follow this exact structure:
            { "tool_name": "chosen_tool_name", "task": "A brief description of what the example task does", "parameters": { /* parameters for the chosen tool */ } }

            **Instructions for choosing a tool and generating parameters:**
            1.  ** You can pick any tool you want. Do not pick the calculator or cat fact tool every time if others are available. **
            2.  If multiple tools have required parameters, choose one that seems suitable for a simple example.
            3.  If no tools have required parameters, you may choose a tool with only optional parameters or one with no parameters.
            4.  If the chosen tool has parameters (required or optional), populate the `parameters` object in the JSON with plausible example values matching their specified types and descriptions.
            5.  **Crucially, if the chosen tool has REQUIRED parameters, the generated `parameters` object MUST include ALL of those required parameters.**
            6.  If the chosen tool has no parameters, the `parameters` object MUST be empty: {}.
            7.  The `task` description should briefly explain what the example task does.
            8.  Include the chosen tool's exact name in the `tool_name` field.

            Return ONLY the raw JSON object string. Do not include any other text, explanations, markdown formatting like ```json, or anything else.

            Available Tools:
            ---
            #{tool_details_for_prompt}
            ---
            You should generate engaging examples!
            Generate the example JSON object now:
          PROMPT
          logger.debug("Gemini Prompt (AgentInteractionRoutes):\n#{gemini_prompt}")

          begin
            google_api_key = ENV['GOOGLE_API_KEY']
            halt 503, json(error: 'GOOGLE_API_KEY not configured.') unless google_api_key && !google_api_key.empty?

            logger.info("Using model '#{agent_model_name}' for example task generation (AgentInteractionRoutes).")
            gemini_client = Gemini.new(credentials: { service: 'generative-language-api', api_key: google_api_key },
                                       options: { model: agent_model_name,
                                                  server_sent_events: false })
            response = gemini_client.generate_content({ contents: [{ role: 'user', parts: { text: gemini_prompt } }] })

            generated_json_str = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
            halt 500,
                 json(error: 'AI service returned empty response.') unless generated_json_str && !generated_json_str.strip.empty?

            logger.debug("Raw Gemini Response (AgentInteractionRoutes): #{generated_json_str}")
            clean_json_str = generated_json_str.strip.delete_prefix('```json').delete_suffix('```').strip.delete_prefix('```').delete_suffix('```').strip

            parsed_json_output = JSON.parse(clean_json_str)
            unless parsed_json_output.is_a?(Hash) && parsed_json_output.key?('tool_name') && parsed_json_output.key?('task') && parsed_json_output.key?('parameters')
              raise JSON::ParserError, 'Generated JSON structure incorrect.'
            end

            JSON.pretty_generate(parsed_json_output)
          rescue JSON::ParserError => e
            logger.error("Gemini invalid JSON (AgentInteractionRoutes): #{e.message}. Cleaned: #{clean_json_str}")
            halt 500, json(error: "Failed to generate valid JSON example: #{e.message}")
          rescue StandardError => e
            logger.error("Gemini API error (AgentInteractionRoutes): #{e.class} - #{e.message}")
            halt 503, json(error: 'AI service communication error.')
          end
        end

        # --- NEW ROUTE: Create a new chat session ---
        app.post '/agents/:name/chat/session/new' do |name|
          session_service = self.instance_variable_get(:@session_service)
          web_user_id = session[:web_user_id]

          halt 503, 'Session Service unavailable.' unless session_service

          begin
            logger.info "User '#{web_user_id}' requesting new chat session for agent '#{name}'"
            new_adk_session = session_service.create_session(app_name: name, user_id: web_user_id, initial_state: {})
            logger.info "Created new ADK session '#{new_adk_session.id}' for user '#{web_user_id}', agent '#{name}'"

            session[:active_agent_sessions] ||= {}
            session[:active_agent_sessions][name] = new_adk_session.id
            logger.debug "Set active session to new session '#{new_adk_session.id}' for agent '#{name}'"

            if request.env['HTTP_HX_REQUEST'] == 'true'
              definition_store = self.instance_variable_get(:@definition_store)
              active_agents_hash = self.instance_variable_get(:@agents)
              agent_definition = definition_store.get_definition(name)
              self.instance_variable_set(:@agent_data,
                                         { name: name, description: agent_definition[:description],
                                           running: active_agents_hash.key?(name) })
              self.instance_variable_set(:@active_session_details, new_adk_session)
              self.instance_variable_set(:@chat_history_events, new_adk_session.events || [])
              all_sessions_for_user_agent = session_service.list_sessions(app_name: name, user_id: web_user_id)
              previous_sessions_list = all_sessions_for_user_agent.sort_by(&:updated_at).reverse
              self.instance_variable_set(:@previous_sessions_list, previous_sessions_list)
              slim :chat, layout: false
            else
              redirect "/agents/#{name}/chat"
            end
          rescue => e
            logger.error "Error creating new session for agent '#{name}', user '#{web_user_id}': #{e.message}\n#{e.backtrace.join("\n")}"
            halt 500, 'Failed to create new chat session.'
          end
        end
        # --- END NEW ROUTE ---

        # --- NEW ROUTE: Switch active chat session ---
        app.post '/agents/:name/chat/session/switch' do |name|
          session_service = self.instance_variable_get(:@session_service)
          web_user_id = session[:web_user_id]
          adk_session_to_switch_to = params[:adk_session_to_switch_to]

          halt 503, 'Session Service unavailable.' unless session_service
          halt 400, 'Missing adk_session_to_switch_to parameter.' unless adk_session_to_switch_to

          logger.info "User '#{web_user_id}' requesting to switch to session '#{adk_session_to_switch_to}' for agent '#{name}'"

          begin
            potential_session = session_service.get_session(session_id: adk_session_to_switch_to)
            if potential_session && potential_session.user_id == web_user_id && potential_session.app_name == name
              session[:active_agent_sessions] ||= {}
              session[:active_agent_sessions][name] = potential_session.id
              logger.info "Successfully switched active session to '#{potential_session.id}' for user '#{web_user_id}', agent '#{name}'"
              if request.env['HTTP_HX_REQUEST'] == 'true'
                definition_store = self.instance_variable_get(:@definition_store)
                active_agents_hash = self.instance_variable_get(:@agents)
                agent_definition = definition_store.get_definition(name)
                self.instance_variable_set(:@agent_data,
                                           { name: name, description: agent_definition[:description],
                                             running: active_agents_hash.key?(name) })
                self.instance_variable_set(:@active_session_details, potential_session)
                self.instance_variable_set(:@chat_history_events, potential_session.events || [])
                all_sessions_for_user_agent = session_service.list_sessions(app_name: name, user_id: web_user_id)
                previous_sessions_list = all_sessions_for_user_agent.sort_by(&:updated_at).reverse
                self.instance_variable_set(:@previous_sessions_list, previous_sessions_list)
                slim :chat, layout: false
              else
                redirect "/agents/#{name}/chat"
              end
            else
              logger.warn "Failed switch attempt: Session '#{adk_session_to_switch_to}' not found, or does not belong to user '#{web_user_id}' for agent '#{name}'."
              if request.env['HTTP_HX_REQUEST'] == 'true'
                response.headers['HX-Location'] =
                  JSON.dump({ path: "/agents/#{name}/chat", target: '#chat_interface_wrapper' })
                halt 200
              else
                redirect "/agents/#{name}/chat"
              end
            end
          rescue => e
            logger.error "Error switching session for agent '#{name}', user '#{web_user_id}' to '#{adk_session_to_switch_to}': #{e.message}\n#{e.backtrace.join("\n")}"
            halt 500, 'Failed to switch chat session.'
          end
        end
        # --- END NEW ROUTE ---

        # --- NEW ROUTE: Delete a specific chat session ---
        app.delete '/agents/:name/chat/session/:adk_session_id_to_delete' do |name, adk_session_id_to_delete|
          session_service = self.instance_variable_get(:@session_service)
          web_user_id = session[:web_user_id]

          halt 503, 'Session Service unavailable.' unless session_service
          logger.info "User '#{web_user_id}' requesting deletion of session '#{adk_session_id_to_delete}' for agent '#{name}'"

          session_to_delete = nil
          begin
            session_to_delete = session_service.get_session(session_id: adk_session_id_to_delete)
            unless session_to_delete && session_to_delete.user_id == web_user_id && session_to_delete.app_name == name
              logger.warn "Attempt to delete invalid/unowned session '#{adk_session_id_to_delete}' by user '#{web_user_id}' for agent '#{name}'."
              if request.env['HTTP_HX_REQUEST'] == 'true'
                response.headers['HX-Retarget'] = '#session-operation-error'
                response.headers['HX-Reswap'] = 'outerHTML'
                halt 403,
                     slim(:_session_error, layout: false,
                                           locals: { error_message: 'Forbidden: Cannot delete this session.' })
              else
                redirect "/agents/#{name}/chat", 403
              end
            end
          rescue => e
            logger.error "Error fetching session '#{adk_session_id_to_delete}' for deletion: #{e.message}"
            if request.env['HTTP_HX_REQUEST'] == 'true'
              response.headers['HX-Retarget'] = '#session-operation-error'
              response.headers['HX-Reswap'] = 'outerHTML'
              halt 500,
                   slim(:_session_error, layout: false,
                                         locals: { error_message: 'Error verifying session for deletion.' })
            else
              redirect "/agents/#{name}/chat", 500
            end
          end

          begin
            session_service.delete_session(session_id: adk_session_id_to_delete)
            logger.info "Successfully deleted session '#{adk_session_id_to_delete}' for user '#{web_user_id}', agent '#{name}'."
          rescue => e
            logger.error "Error deleting session '#{adk_session_id_to_delete}': #{e.message}"
            if request.env['HTTP_HX_REQUEST'] == 'true'
              response.headers['HX-Retarget'] = '#session-operation-error'
              response.headers['HX-Reswap'] = 'outerHTML'
              halt 500, slim(:_session_error, layout: false, locals: { error_message: 'Failed to delete session.' })
            else
              redirect "/agents/#{name}/chat", 500
            end
          end

          session[:active_agent_sessions] ||= {}
          if session[:active_agent_sessions][name] == adk_session_id_to_delete
            logger.info "Deleted session '#{adk_session_id_to_delete}' was the active one for agent '#{name}'. Finding new active session."
            session[:active_agent_sessions].delete(name)
            remaining_sessions = session_service.list_sessions(app_name: name, user_id: web_user_id)
            if remaining_sessions && !remaining_sessions.empty?
              next_active_session = remaining_sessions.sort_by(&:updated_at).last
              session[:active_agent_sessions][name] = next_active_session.id
              logger.info "Set next active session for agent '#{name}' to '#{next_active_session.id}'."
            else
              logger.info "No remaining sessions found for agent '#{name}', user '#{web_user_id}'. Active session cleared."
            end
          end

          if request.env['HTTP_HX_REQUEST'] == 'true'
            logger.debug 'HTMX request detected for delete session, re-rendering chat interface.'
            definition_store = self.instance_variable_get(:@definition_store)
            active_agents_hash = self.instance_variable_get(:@agents)
            agent_definition = definition_store.get_definition(name)
            new_active_session_id = session[:active_agent_sessions][name]
            new_active_session_details = new_active_session_id ? session_service.get_session(session_id: new_active_session_id) : nil
            new_chat_history = new_active_session_details&.events || []
            new_previous_sessions_list = session_service.list_sessions(app_name: name,
                                                                       user_id: web_user_id).sort_by(&:updated_at).reverse
            self.instance_variable_set(:@agent_data,
                                       { name: name, description: agent_definition[:description],
                                         running: active_agents_hash.key?(name) })
            self.instance_variable_set(:@active_session_details, new_active_session_details)
            self.instance_variable_set(:@chat_history_events, new_chat_history)
            self.instance_variable_set(:@previous_sessions_list, new_previous_sessions_list)
            slim :chat, layout: false
          else
            redirect "/agents/#{name}/chat"
          end
        end
        # --- END DELETE ROUTE ---
      end # self.registered
    end
  end
end
