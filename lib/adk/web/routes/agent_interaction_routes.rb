# File: lib/adk/web/routes/agent_interaction_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentInteractionRoutes
      def self.registered(app)
        # GET /agents/:name/chat - Display the chat interface for an agent.
        app.get '/agents/:name/chat' do |name|
          # `self` is the Sinatra app instance
          definition_store = self.instance_variable_get(:@definition_store)
          session_service = self.instance_variable_get(:@session_service)
          active_agents_hash = self.instance_variable_get(:@agents)

          halt 503, "Definition Store unavailable." unless definition_store

          agent_definition = nil
          begin
            agent_definition = definition_store.get_definition(name)
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error fetching definition for '#{name}' chat (from AgentInteractionRoutes): #{e.message}")
            halt 500, "Error retrieving agent definition."
          end
          unless agent_definition
            logger.warn("Agent definition not found for '#{name}' in store (GET /chat from AgentInteractionRoutes).")
            halt 404, slim(:error_404, locals: { title: "Agent Not Found", message: "Definition for '#{name}' not found." })
          end
          
          agent_description_for_view = agent_definition[:description]
          is_running = active_agents_hash.key?(name)

          session[:adk_sessions] ||= {}
          current_session_id = session[:adk_sessions][name]

          unless current_session_id && session_service.get_session(session_id: current_session_id)
            begin
              new_adk_session = session_service.create_session(app_name: name, user_id: "web_user_#{SecureRandom.hex(4)}")
              current_session_id = new_adk_session.id
              session[:adk_sessions][name] = current_session_id
              logger.info("Created new ADK session for agent '#{name}': #{current_session_id} (from AgentInteractionRoutes)")
            rescue => e
              logger.error("Failed to create ADK session for agent '#{name}' (from AgentInteractionRoutes): #{e.message}")
              halt 500, "Failed to initialize chat session."
            end
          end
          logger.debug("Using ADK session ID: #{current_session_id} for agent '#{name}' chat (from AgentInteractionRoutes)")

          chat_history_events_list = []
          begin
            adk_session_obj = session_service.get_session(session_id: current_session_id)
            chat_history_events_list = adk_session_obj&.events || []
          rescue => e
            logger.error("Failed to load chat history for session '#{current_session_id}' (from AgentInteractionRoutes): #{e.message}")
          end

          self.instance_variable_set(:@agent_data, { name: name, description: agent_description_for_view, running: is_running })
          self.instance_variable_set(:@session_id, current_session_id)
          self.instance_variable_set(:@chat_history_events, chat_history_events_list)
          slim :chat
        end

        # POST /agents/:name/chat - Process a user message from the chat interface.
        app.post '/agents/:name/chat' do |name|
          content_type :html
          active_agents_hash = self.instance_variable_get(:@agents)
          session_service = self.instance_variable_get(:@session_service)
          
          current_agent_instance = active_agents_hash[name]
          user_message_text = params['message']&.strip
          
          session[:adk_sessions] ||= {}
          current_session_id = session[:adk_sessions][name]

          view_locals = {
            user_message: user_message_text || "[Empty Message]",
            agent_result: nil,
            agent_name: current_agent_instance ? current_agent_instance.name : name
          }

          unless current_session_id && session_service.get_session(session_id: current_session_id)
            logger.error("Chat POST Error: Missing or invalid session ID (#{current_session_id}) (from AgentInteractionRoutes). Redirecting.")
            session[:adk_sessions].delete(name) # Clear specific agent session
            redirect "/agents/#{name}/chat"
          end
          unless current_agent_instance
            view_locals[:agent_result] = { status: :error, error_message: "[Error: Agent '#{name}' is not running.]" }
            halt 400, slim(:_chat_message, layout: false, locals: view_locals)
          end
          if user_message_text.nil? || user_message_text.empty?
            view_locals[:agent_result] = { status: :error, error_message: "[Error: Message cannot be empty.]" }
            halt 400, slim(:_chat_message, layout: false, locals: view_locals)
          end

          begin
            logger.info("Agent '#{name}' processing chat in session '#{current_session_id}' (from AgentInteractionRoutes): #{user_message_text}")
            final_event_or_error = current_agent_instance.run_task(
              session_id: current_session_id,
              user_input: user_message_text,
              session_service: session_service
            )
            logger.info("Agent '#{name}' task processing complete (from AgentInteractionRoutes). Final result: #{final_event_or_error.inspect}")
            view_locals[:agent_result] = final_event_or_error
            slim :_chat_message, layout: false, locals: view_locals
          rescue => e
            logger.error("Error processing chat for agent #{name} (from AgentInteractionRoutes): #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
            view_locals[:agent_result] = { status: :error, error_message: "[Internal Error executing task: #{e.message}]" }
            halt 500, slim(:_chat_message, layout: false, locals: view_locals)
          end
        end

        # POST /agents/:name/execute - Execute a task directly via JSON input.
        app.post '/agents/:name/execute' do |name|
          content_type :json # Default to JSON for this route
          active_agents_hash = self.instance_variable_get(:@agents)
          session_service = self.instance_variable_get(:@session_service)
          agent_instance = active_agents_hash[name]

          error_handler = lambda do |message, code = 400|
            trigger_event = (code == 400) ? 'showTaskError' : 'showTaskServerError'
            headers 'HX-Trigger-After-Swap' => trigger_event
            halt 200, json(error: message) 
          end

          success_handler = lambda do |result_hash|
            format_execution_result_html(result_hash) # Helper is available in instance context
          end

          error_handler.call("Error: Agent '#{name}' not found or not running.", 400) unless agent_instance
          task_json_string = params['task_json']
          error_handler.call("Error: Missing 'task_json' data.", 400) unless task_json_string && !task_json_string.empty?

          task_desc = nil; exec_params = nil; tool_to_exec = nil
          begin
            parsed_data = JSON.parse(task_json_string)
            if parsed_data.is_a?(Hash)
              if parsed_data.key?('tool_name') && parsed_data.key?('task') && parsed_data.key?('parameters')
                tool_to_exec = parsed_data['tool_name']&.strip
                task_desc = parsed_data['task']
                exec_params = parsed_data['parameters']
                error_handler.call("Error: Missing 'tool_name' in JSON for direct execution.", 400) if tool_to_exec.nil? || tool_to_exec.empty?
                error_handler.call("Error: Missing or invalid 'parameters' object in JSON for direct execution.", 400) unless exec_params.is_a?(Hash)
              elsif parsed_data.key?('task')
                task_desc = parsed_data['task']
                error_handler.call("Error: Invalid JSON. Use {'task': '...'} or {'tool_name': ..., 'task': ..., 'parameters': {...}}.", 400) unless (parsed_data.keys - ['task']).empty?
              else
                error_handler.call("Error: Invalid JSON structure. Missing 'task' key.", 400)
              end
            else
              error_handler.call("Error: Input must be a JSON object.", 400)
            end
          rescue JSON::ParserError => e
            logger.warn("Invalid JSON for /execute (AgentInteractionRoutes): #{e.message}. Input: #{task_json_string}")
            error_handler.call("Error: Invalid JSON format - #{e.message}", 400)
          end
          error_handler.call("Error: Missing task description.", 400) if tool_to_exec.nil? && (task_desc.nil? || task_desc.empty?)

          temp_adk_session = nil
          begin
            if tool_to_exec
              logger.info("Agent '#{name}' executing DIRECT tool '#{tool_to_exec}' (AgentInteractionRoutes) with params: #{exec_params.inspect}")
              tool_instance_to_run = agent_instance.find_tool(tool_to_exec.to_sym)
              error_handler.call("Error: Tool '#{tool_to_exec}' not configured for agent '#{name}'.", 400) unless tool_instance_to_run
              temp_adk_session = session_service.create_session(app_name: name, user_id: "web_direct_#{SecureRandom.hex(4)}")
              tool_ctx = ADK::ToolContext.new(session_id: temp_adk_session.id, user_id: temp_adk_session.user_id, app_name: temp_adk_session.app_name, tool_registry: agent_instance.tool_registry)
              result = tool_instance_to_run.execute(exec_params.transform_keys(&:to_sym), tool_ctx)
              success_handler.call(result)
            else
              logger.info("Agent '#{name}' executing task via PLANNER (AgentInteractionRoutes): #{task_desc}")
              temp_adk_session = session_service.create_session(app_name: name, user_id: "web_direct_#{SecureRandom.hex(4)}")
              final_result = agent_instance.run_task(session_id: temp_adk_session.id, user_input: task_desc, session_service: session_service)
              content_to_show = final_result.is_a?(ADK::Event) ? final_result.content : final_result
              success_handler.call(content_to_show)
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
          halt 503, json(error: "Definition Store unavailable.") unless definition_store

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
              tm[:parameters].each { |pn, d| params << { name: pn, type: d[:type], description: d[:description], required: d[:required] } }
            end
            tm.merge(parameters: params, source: :native)
          end

          mcp_configs_list = JSON.parse(mcp_servers_config_json) rescue []
          mcp_fetch_results = fetch_mcp_tools(mcp_configs_list) # Helper method from app instance
          
          mcp_tools_meta = []
          mcp_fetch_results.each do |res|
            if res[:status] == :success && res[:tools]
              res[:tools].each do |schema|
                params = ADK::Mcp::Util::SchemaConverter.json_to_adk(schema.dig(:inputSchema, 'properties') || {}, schema.dig(:inputSchema, 'required') || [])
                mcp_tools_meta << { name: schema[:name].to_sym, description: schema[:description] || '', parameters: params, source: :mcp }
              end
            end
          end

          all_tools_map = (native_tools_meta + mcp_tools_meta).each_with_object({}) { |t, map| map[t[:name]] ||= t }
          final_configured_tools_meta = configured_tool_syms_list.map { |sym| all_tools_map[sym] }.compact

          if final_configured_tools_meta.empty?
            return json(example: { task: "Agent '#{name}' tools metadata incomplete. Cannot generate." })
          end

          tool_details_for_prompt = final_configured_tools_meta.map do |meta|
            params_str = meta[:parameters].empty? ? 'None' : meta[:parameters].map { |p| "#{p[:name]} (#{p[:type]}, #{p[:required] ? 'required' : 'optional'})" }.join(', ')
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
          logger.debug("Gemini Prompt (AgentInteractionRoutes):
#{gemini_prompt}")

          begin
            google_api_key = ENV['GOOGLE_API_KEY']
            halt 503, json(error: "GOOGLE_API_KEY not configured.") unless google_api_key && !google_api_key.empty?
            
            logger.info("Using model '#{agent_model_name}' for example task generation (AgentInteractionRoutes).")
            # Ensure Gemini library is available
            # require 'gemini-ai' - this should be at the top of app.rb or here if not already loaded
            gemini_client = Gemini.new(credentials: { service: 'generative-language-api', api_key: google_api_key }, options: { model: agent_model_name, server_sent_events: false })
            response = gemini_client.generate_content({ contents: [{ role: 'user', parts: { text: gemini_prompt } }] })
            
            generated_json_str = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
            halt 500, json(error: "AI service returned empty response.") unless generated_json_str && !generated_json_str.strip.empty?
            
            logger.debug("Raw Gemini Response (AgentInteractionRoutes): #{generated_json_str}")
            clean_json_str = generated_json_str.strip.delete_prefix('```json').delete_suffix('```').strip.delete_prefix('```').delete_suffix('```').strip
            
            parsed_json_output = JSON.parse(clean_json_str)
            unless parsed_json_output.is_a?(Hash) && parsed_json_output.key?('tool_name') && parsed_json_output.key?('task') && parsed_json_output.key?('parameters')
              raise JSON::ParserError, "Generated JSON structure incorrect."
            end
            JSON.pretty_generate(parsed_json_output) # Return pretty JSON
          rescue JSON::ParserError => e
            logger.error("Gemini invalid JSON (AgentInteractionRoutes): #{e.message}. Cleaned: #{clean_json_str}")
            halt 500, json(error: "Failed to generate valid JSON example: #{e.message}")
          rescue StandardError => e # Catch other API/client errors
            logger.error("Gemini API error (AgentInteractionRoutes): #{e.class} - #{e.message}")
            halt 503, json(error: "AI service communication error.")
          end
        end
      end
    end
  end
end 