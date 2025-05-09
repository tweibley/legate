Okay, I've reviewed the `lib/adk/web` directory components based on the provided code, screenshots, and your previous analysis.

Here's a breakdown of findings, focusing on completeness, potential bugs, and broken features, followed by the proposed changes.

## Web UI Analysis:

**Overall:**

*   The Web UI is quite comprehensive, offering CRUD for agent definitions, runtime control, a chat interface, tool browsing, and even documentation viewing.
*   HTMX is used effectively for dynamic updates, enhancing user experience.
*   The new multi-session chat feature is a significant addition and seems mostly well-integrated in the backend and views.
*   The inline editing of agent definition fields is a good UX pattern.

**Identified Issues & Areas for Improvement:**

1.  **Broken Feature: Bulk Configuration Edit (High Priority)**
    *   **Symptom:** The "Config" tab on the agent detail page (`agent.slim`) is intended to allow editing of Model, Fallback, MCP Config, and Instructions together. The view `_edit_agent_configuration.slim` is designed for this, but the `PUT /agents/:name/update/configuration` route it submits to is missing.
    *   **Impact:** Users cannot save changes made in the bulk "Configuration Details" edit form.

2.  **Tool Listing Anomaly (Medium Priority)**
    *   **Symptom:** Abstract base tool classes like `base_async_job_tool` are listed on the `/tools` page (Screenshot 1).
    *   **Impact:** Confusing for users, as these are not directly usable tools.
    *   **Cause:** `ADK::GlobalToolManager.list_all_tools` likely includes all `ADK::Tool` subclasses without filtering for abstract/base ones.

3.  **Missing CSS for `.is-newly-added` (Low Priority)**
    *   **Symptom:** The `_agent_row.slim` partial uses a class `is-newly-added` for new agent rows, but there's no corresponding CSS in `main.scss`.
    *   **Impact:** No visual feedback when a new agent is added to the list via HTMX.

4.  **Redundant/Unclear Tool Detail View (Low Priority)**
    *   **Symptom:** Two Slim templates seem to exist for tool details: `tool.slim` (which includes a "Try it out" form and is linked from the main tools list) and `tool_detail.slim` (which shows parameters and an example JSON input). The screenshots primarily show `tool.slim` in action.
    *   **Impact:** Potential for confusion, dead code, or inconsistent display if both are meant to be used.

5.  **Agent Start/Stop from Main List - Feedback (UX Improvement)**
    *   **Symptom:** When starting/stopping an agent from the main `/agents` list, the success/failure feedback is handled by swapping HTML fragments. While functional, a toast notification (like for config updates) might provide clearer, less jarring feedback.
    *   **Impact:** Minor UX inconsistency.

6.  **Error Handling in Forms (UX Improvement)**
    *   While individual field update routes have some error handling (e.g., for invalid MCP JSON), the display of these errors back in the form could be more robust or consistent across all editable fields. The bulk configuration route will especially need good error feedback if multiple fields are invalid.

**Code Completeness & Minor Observations:**

*   **Session Management in Chat:** The multi-session chat logic in `agent_interaction_routes.rb` (for `GET /agents/:name/chat`) and its interaction with `_active_session_info.slim` and the session sidebar in `chat.slim` is well-implemented, including security checks for session ownership.
*   **JavaScript in `layout.slim`:** The JavaScript for CodeMirror, Highlight.js, Mermaid, health checks, and HTMX event handling is generally robust. The `adjustDropdownDirection` is a nice detail.
*   **Webhook Listener:** The listener and its interaction with the `GlobalDefinitionRegistry` (for Procs) and `DefinitionStore` (for serializable data) is a sound approach for handling webhook configurations.
*   **`_display_agent_configuration.slim` and `_edit_agent_configuration.slim`:** These files form the basis of the "Config" tab. `_display_agent_configuration.slim` correctly uses the individual `_display_agent_FIELD.slim` partials. `_edit_agent_configuration.slim` is the form for the broken bulk update feature.

## Proposed Changes:

Here are the detailed changes required to address the identified issues, focusing on the highest priority first.

---

**Change 1: Implement Bulk Configuration Update Route and UI Flow (High Priority)**

**Summary:**
The "Config" tab on the agent detail page should allow users to edit Model, Fallback mode, MCP Server Configurations, and Instructions simultaneously. This requires:
1.  An "Edit All" button on the display view (`_display_agent_configuration.slim`).
2.  A GET route to render the bulk edit form (`_edit_agent_configuration.slim`).
3.  A PUT route to process the submission from this form.

**Files to Change:**

1.  `lib/adk/web/views/_display_agent_configuration.slim`
2.  `lib/adk/web/routes/agent_definition_routes.rb`

**1. `lib/adk/web/views/_display_agent_configuration.slim`**
   *   Add an "Edit All" button that loads the bulk edit form.
   *   Change individual display partials to hide their own edit buttons when shown in this bulk display context.

```slim
/ File: lib/adk/web/views/_display_agent_configuration.slim
/ Displays the read-only configuration fields for an agent.
/ Expects locals: agent_data

.box
  .level.mb-4 / Use Bulma level for alignment
    .level-left
      h3.title.is-5 Configuration Details
    .level-right
      /! Edit button for the entire configuration block
      button.button.is-link.is-light( hx-get="/agents/#{agent_data[:name]}/edit/configuration"
                                      hx-target="closest .box" /! Target the parent .box to replace display with edit form
                                      hx-swap="innerHTML"
                                      hx-indicator="this .htmx-indicator")
        span.icon.is-small.htmx-indicator
           i.fas.fa-spinner.fa-spin
        span.icon.is-small
          i.fas.fa-pencil-alt
        span Edit All Configurations

  / --- Model ---
  div#agent-model-display-container.mb-4
    /! Pass show_edit_button: false to hide individual edit button
    == slim :_display_agent_model, locals: { agent_data: agent_data, show_edit_button: false }

  / --- Fallback ---
  div#agent-fallback-display-container.mb-4
    /! Pass show_edit_button: false
    == slim :_display_agent_fallback, locals: { agent_data: agent_data, show_edit_button: false }

  / --- MCP ---
  div#agent-mcp-display-container.mb-4
    /! Pass show_edit_button: false
    == slim :_display_agent_mcp, locals: { agent_data: agent_data, show_edit_button: false }

  / --- Instructions ---
  div#agent-instruction-display-container
    /! Pass show_edit_button: false
    == slim :_display_agent_instruction, locals: { agent_data: agent_data, show_edit_button: false }
```

**2. `lib/adk/web/routes/agent_definition_routes.rb`**
   *   Add a new `GET /agents/:name/edit/configuration` route to render `_edit_agent_configuration.slim`.
   *   Add the missing `PUT /agents/:name/update/configuration` route to handle the form submission.

```ruby
# File: lib/adk/web/routes/agent_definition_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentDefinitionRoutes
      def self.registered(app)
        # ... (existing GET /agents, POST /agents, DELETE /agents/:name, GET /agents/:name routes) ...

        # --- NEW: Route to display the bulk configuration edit form ---
        app.get '/agents/:name/edit/configuration' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, "Definition Store unavailable." unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, "Agent definition not found." unless agent_definition

          agent_data_for_edit = {
            name: name,
            description: agent_definition[:description],
            model: agent_definition[:model] || ADK::Agent::DEFAULT_MODEL, # Ensure model has a value
            fallback_mode: (agent_definition[:fallback_mode] || :error).to_s, # Ensure string for select
            mcp_servers_json: agent_definition[:mcp_servers_json] || '[]',
            instruction: agent_definition[:instruction] || ''
          }
          available_models_for_view = ADK::Web::App::AVAILABLE_MODELS

          slim :_edit_agent_configuration, layout: false, locals: { agent_data: agent_data_for_edit, available_models: available_models_for_view, error_message: nil }
        end
        # --- END NEW EDIT ROUTE ---

        # GET /agents/:name/edit/:field - Show edit form for a specific agent field.
        app.get '/agents/:name/edit/:field' do |name, field|
          supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction'] # Removed 'configuration'
          halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)

          # ... (existing logic for individual field edits remains, no change needed here for 'configuration' as it has its own route now)
          # ... The rest of this route remains the same as in the provided file ...
          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, "Definition Store unavailable." unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, "Agent definition not found." unless agent_definition

          agent_data = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode],
            mcp_servers_json: agent_definition[:mcp_servers_json],
            instruction: agent_definition[:instruction]
          }

          view_locals = { agent_data: agent_data }

          if field == 'model'
            view_locals[:available_models] = ADK::Web::App::AVAILABLE_MODELS
          elsif field == 'tools'
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
                  fetched_mcp_meta << { name: schema[:name].to_sym, description: schema[:description] || "",
                                        parameters: params }
                end
              end
            end
            view_locals[:all_available_tools] = (native_tools + fetched_mcp_meta).uniq { |t|
              t[:name]
            }.sort_by { |t| t[:name].to_s }
          end
          slim :"_edit_agent_#{field}", layout: false, locals: view_locals
        end

        # GET /agents/:name/display/:field - Display an agent field (after edit cancel).
        app.get '/agents/:name/display/:field' do |name, field|
          supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction', 'configuration'] # Add 'configuration'
          halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)

          definition_store = self.instance_variable_get(:@definition_store)
          halt 503, "Definition Store unavailable." unless definition_store

          agent_definition = definition_store.get_definition(name)
          halt 404, "Agent definition not found." unless agent_definition

          agent_data_for_display = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode],
            mcp_servers_json: agent_definition[:mcp_servers_json],
            instruction: agent_definition[:instruction]
          }
          mcp_json_val = agent_definition[:mcp_servers_json]
          agent_data_for_display[:mcp_display_string] = begin
            parsed = JSON.parse(mcp_json_val)
            (parsed.is_a?(Array) && parsed.empty?) ? "No MCP Server(s) Configured." : pretty_json(parsed)
          rescue JSON::ParserError
            mcp_json_val
          end

          if field == 'configuration'
            # Render the main display configuration partial
            halt slim(:_display_agent_configuration, layout: false, locals: { agent_data: agent_data_for_display })
          end

          response_locals = { agent_data: agent_data_for_display, show_edit_button: true }

          if field == 'tools'
            configured_tool_names_str = agent_definition[:tools]
            all_native_tools = ADK::GlobalToolManager.list_all_tools
            response_locals[:configured_tools] = configured_tool_names_str.map { |tn|
              all_native_tools.find { |t| t[:name].to_s == tn }
            }.compact
          end
          slim :"_display_agent_#{field}", layout: false, locals: response_locals
        end

        # GET /agents/:name/display/tool_table
        # ... (this route remains as is) ...
        app.get '/agents/:name/display/tool_table' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, "Definition Store unavailable." unless definition_store
          agent_definition = definition_store.get_definition(name)
          halt 404, "Agent not found" unless agent_definition

          agent_data = {
            name: name, description: agent_definition[:description], model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode], mcp_servers_json: agent_definition[:mcp_servers_json],
            running: active_agents_hash.key?(name)
          }
          configured_tool_names = agent_definition[:tools]
          configured_tool_syms = configured_tool_names.map(&:to_sym)

          all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map { |tm|
            tm.merge(source: :native, source_detail: "Native")
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
                                                description: mcp_tool_schema[:description] || "", parameters: parameters, source: :mcp, source_detail: "MCP (#{result[:server]})" }
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

        # --- NEW: Route to handle PUT for bulk configuration update ---
        app.put '/agents/:name/update/configuration' do |name|
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, "Definition Store unavailable." unless definition_store

          # Original agent definition for fallback and filling unchanged fields
          original_agent_definition = definition_store.get_definition(name)
          halt 404, "Agent definition not found." unless original_agent_definition

          updates_for_store = {}
          errors = {}

          # Validate and collect Model
          new_model = params['model']&.strip
          if new_model && !new_model.empty?
            if ADK::Web::App::AVAILABLE_MODELS.include?(new_model)
              updates_for_store[:model] = new_model
            else
              errors[:model] = "Invalid model selected."
            end
          # If not provided or empty, it will keep the original or default during update_definition
          end

          # Validate and collect Fallback Mode
          new_fallback_mode_str = params['fallback_mode']&.strip
          if new_fallback_mode_str && !new_fallback_mode_str.empty?
            if ['error', 'echo'].include?(new_fallback_mode_str)
              updates_for_store[:fallback_mode] = new_fallback_mode_str.to_sym
            else
              errors[:fallback_mode] = "Invalid fallback mode selected."
            end
          end

          # Validate and collect MCP Servers JSON
          new_mcp_servers_json = params['mcp_servers_json']&.strip
          mcp_to_save = (new_mcp_servers_json.nil? || new_mcp_servers_json.empty?) ? '[]' : new_mcp_servers_json
          begin
            parsed_mcp = JSON.parse(mcp_to_save)
            raise JSON::ParserError, "MCP configuration must be a valid JSON array." unless parsed_mcp.is_a?(Array)
            updates_for_store[:mcp_servers_json] = mcp_to_save
          rescue JSON::ParserError => e
            errors[:mcp_servers_json] = "Invalid MCP JSON: #{e.message}"
          end

          # Collect Instruction (allow empty)
          new_instruction = params['instruction'] # Keep nil if not present, strip if present
          updates_for_store[:instruction] = new_instruction.strip if new_instruction

          # If there are validation errors, re-render the edit form with error messages
          unless errors.empty?
            agent_data_for_edit_form = {
              name: name,
              model: new_model || original_agent_definition[:model],
              fallback_mode: new_fallback_mode_str || original_agent_definition[:fallback_mode].to_s,
              mcp_servers_json: new_mcp_servers_json || original_agent_definition[:mcp_servers_json],
              instruction: new_instruction || original_agent_definition[:instruction]
            }
            error_summary = errors.map { |k, v| "#{k.to_s.capitalize.gsub('_', ' ')}: #{v}" }.join("<br>")
            halt 200, slim(:_edit_agent_configuration, layout: false,
                                                        locals: { agent_data: agent_data_for_edit_form,
                                                                  available_models: ADK::Web::App::AVAILABLE_MODELS,
                                                                  error_message: error_summary })
          end

          # Proceed with update if no errors and there are changes
          if updates_for_store.empty?
            logger.info("No actual configuration changes submitted for agent '#{name}'.")
            # Re-render display view
            # Fetch the latest, potentially unchanged, definition for display
            current_definition_for_display = definition_store.get_definition(name) || original_agent_definition
            agent_data_for_display = { name: name }.merge(current_definition_for_display.slice(:description, :model, :fallback_mode, :mcp_servers_json, :instruction))
            mcp_json_val_disp = agent_data_for_display[:mcp_servers_json]
            agent_data_for_display[:mcp_display_string] = begin
              parsed_disp = JSON.parse(mcp_json_val_disp)
              (parsed_disp.is_a?(Array) && parsed_disp.empty?) ? "No MCP Server(s) Configured." : pretty_json(parsed_disp)
            rescue JSON::ParserError
              mcp_json_val_disp
            end
            halt 200, slim(:_display_agent_configuration, layout: false, locals: { agent_data: agent_data_for_display })
          end

          begin
            update_success = definition_store.update_definition(name, updates_for_store)
            halt 404, "Agent not found for configuration update." unless update_success # Should not happen if original_def loaded
            logger.info("Agent '#{name}' configuration updated with fields: #{updates_for_store.keys.join(', ')}.")

            trigger_events = ['showSaveSuccessToast'] # Start with save success
            was_running = active_agents_hash.key?(name)
            if was_running
              logger.info("Agent '#{name}' config updated while running. Triggering auto-restart.")
              self.send(:_stop_agent, name)
              newly_started_agent = self.send(:_start_agent, name)
              trigger_events << (!newly_started_agent.nil? ? 'showRestartToast' : 'showRestartErrorToast')
            end
            headers 'HX-Trigger-After-Swap' => trigger_events.join(',')

            # Re-fetch the full definition for display
            full_updated_def = definition_store.get_definition(name)
            halt 500, "Failed to reload agent definition after update." unless full_updated_def

            agent_data_for_display = {
              name: name, description: full_updated_def[:description],
              model: full_updated_def[:model], fallback_mode: full_updated_def[:fallback_mode],
              mcp_servers_json: full_updated_def[:mcp_servers_json], instruction: full_updated_def[:instruction]
            }
            mcp_json_val_disp = full_updated_def[:mcp_servers_json]
            agent_data_for_display[:mcp_display_string] = begin
              parsed_disp = JSON.parse(mcp_json_val_disp)
              (parsed_disp.is_a?(Array) && parsed_disp.empty?) ? "No MCP Server(s) Configured." : pretty_json(parsed_disp)
            rescue JSON::ParserError
              mcp_json_val_disp
            end

            slim :_display_agent_configuration, layout: false, locals: { agent_data: agent_data_for_display }

          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error bulk updating agent '#{name}': #{e.message}")
            halt 500, "Error updating agent configuration."
          rescue ArgumentError => e # From store validation if any
            agent_def_for_error = definition_store.get_definition(name) || { name: name }
            agent_data_for_edit_form = { name: name }.merge(agent_def_for_error) # Base on fetched
            agent_data_for_edit_form.merge!(updates_for_store.transform_keys(&:to_sym)) # Overlay submitted values
            agent_data_for_edit_form[:fallback_mode] = agent_data_for_edit_form[:fallback_mode].to_s # Ensure string for form
            halt 200, slim(:_edit_agent_configuration, layout: false, locals: { agent_data: agent_data_for_edit_form, available_models: ADK::Web::App::AVAILABLE_MODELS, error_message: "Invalid input for store: #{e.message}"})
          end
        end
        # --- END NEW UPDATE ROUTE ---

        # PUT /agents/:name/update/:field - Update a specific field of an agent definition.
        app.put '/agents/:name/update/:field' do |name, field|
          # ... (existing single field update logic) ...
          # Add HX-Trigger for save success toast to this route as well.
          # (Code from provided file with added HX-Trigger)
          supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction']
          halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)
          definition_store = self.instance_variable_get(:@definition_store)
          active_agents_hash = self.instance_variable_get(:@agents)
          halt 503, "Definition Store unavailable." unless definition_store

          field_to_update_in_store = case field
                                     when 'fallback' then 'fallback_mode'
                                     when 'mcp' then 'mcp_servers_json'
                                     else field
                                     end
          new_value_for_store = nil
          agent_data_for_display_partial = { name: name }
          error_message_for_edit_form = nil

          case field
          when 'tools'
            current_definition = definition_store.get_definition(name)
            halt 404, "Agent not found for tool update." unless current_definition
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
            all_native_meta = ADK::GlobalToolManager.list_all_tools.map do |tm|
              params_array = []
              if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
                tm[:parameters].each { |pn, d|
                  params_array << { name: pn, type: d[:type], description: d[:description], required: d[:required] }
                }
              end
              tm.merge(parameters: params_array, source: :native, source_detail: "Native")
            end
            fetched_mcp_meta = []
            mcp_results.each do |res|
              if res[:status] == :success && res[:tools]
                res[:tools].each do |schema|
                  params = ADK::Mcp::Util::SchemaConverter.json_to_adk(
                    schema.dig(:inputSchema, 'properties') || {}, schema.dig(:inputSchema, 'required') || []
                  )
                  fetched_mcp_meta << { name: schema[:name].to_sym, description: schema[:description] || "",
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
            agent_data_for_display_partial[:mcp_tool_results] = mcp_results
          when 'mcp'
            submitted_json = params['value']&.strip
            new_value_for_store = (submitted_json.nil? || submitted_json.empty?) ? '[]' : submitted_json
            begin
              parsed = JSON.parse(new_value_for_store)
              raise JSON::ParserError, "Input must be a valid JSON array." unless parsed.is_a?(Array)
            rescue JSON::ParserError => e
              error_message_for_edit_form = "Invalid JSON: #{e.message}"
            end
            agent_data_for_display_partial[:mcp_servers_json] = new_value_for_store
            agent_data_for_display_partial[:mcp_display_string] = (JSON.parse(new_value_for_store).empty? rescue true) ? "No MCP Server(s) Configured." : pretty_json(JSON.parse(new_value_for_store) rescue new_value_for_store)
          when 'fallback'
            submitted_value = params['value']&.strip
            unless ['error', 'echo'].include?(submitted_value)
              error_message_for_edit_form = "Invalid fallback mode."
            end
            new_value_for_store = submitted_value.to_sym if error_message_for_edit_form.nil?
            agent_data_for_display_partial[:fallback_mode] = new_value_for_store || (definition_store.get_definition(name)&.[](:fallback_mode) || :error)
          when 'instruction', 'description', 'model'
            new_value_for_store = params['value']&.strip
            if new_value_for_store.nil? && field != 'instruction' && field != 'description'
              error_message_for_edit_form = "#{field.capitalize} cannot be empty."
            elsif new_value_for_store.nil?
              new_value_for_store = ""
            end
            if field == 'model' && !ADK::Web::App::AVAILABLE_MODELS.include?(new_value_for_store)
              error_message_for_edit_form = "Invalid model selected."
            end
            agent_data_for_display_partial[field.to_sym] = new_value_for_store || (definition_store.get_definition(name)&.[] (field.to_sym))
          end

          if error_message_for_edit_form
            current_def = definition_store.get_definition(name) || { name: name }
            agent_data_for_edit_form = { name: name }.merge(current_def.slice(:description, :model, :fallback_mode, :mcp_servers_json, :instruction))
            agent_data_for_edit_form[field.to_sym] = params['value'] # Show the invalid submitted value
            agent_data_for_edit_form[:fallback_mode] = agent_data_for_edit_form[:fallback_mode].to_s if agent_data_for_edit_form[:fallback_mode].is_a?(Symbol)

            view_locals = { agent_data: agent_data_for_edit_form, error_message: error_message_for_edit_form }
            view_locals[:available_models] = ADK::Web::App::AVAILABLE_MODELS if field == 'model'
            if field == 'tools'
              view_locals[:configured_tool_names] = current_def[:tools].map(&:to_s)
              view_locals[:all_available_tools] = ADK::GlobalToolManager.list_all_tools # Simplified for example
            end
            halt 200, slim(:"_edit_agent_#{field}", layout: false, locals: view_locals)
          end

          begin
            update_success = definition_store.update_definition(name, { field_to_update_in_store.to_sym => new_value_for_store })
            halt 404, "Agent not found for update." unless update_success
            logger.info("Agent '#{name}' field '#{field_to_update_in_store}' updated.")

            trigger_events = ['showSaveSuccessToast']
            was_running = active_agents_hash.key?(name)
            if was_running
              logger.info("Agent '#{name}' config updated while running. Triggering auto-restart.")
              self.send(:_stop_agent, name)
              newly_started_agent = self.send(:_start_agent, name)
              agent_data_for_display_partial[:running] = !newly_started_agent.nil?
              trigger_events << (agent_data_for_display_partial[:running] ? 'showRestartToast' : 'showRestartErrorToast')
            else
              agent_data_for_display_partial[:running] = false
            end
            headers 'HX-Trigger-After-Swap' => trigger_events.join(',')

            full_updated_def = definition_store.get_definition(name)
            halt 500, "Failed to reload agent definition after update." unless full_updated_def
            agent_data_for_display_partial.merge!(
              description: full_updated_def[:description], model: full_updated_def[:model],
              fallback_mode: full_updated_def[:fallback_mode], mcp_servers_json: full_updated_def[:mcp_servers_json],
              instruction: full_updated_def[:instruction]
            )
            if field == 'mcp'
              mcp_json_val_disp = full_updated_def[:mcp_servers_json]
              agent_data_for_display_partial[:mcp_display_string] = begin
                parsed_disp = JSON.parse(mcp_json_val_disp)
                (parsed_disp.is_a?(Array) && parsed_disp.empty?) ? "No MCP Server(s) Configured." : pretty_json(parsed_disp)
              rescue JSON::ParserError
                mcp_json_val_disp
              end
            end
            response_locals_for_display = { agent_data: agent_data_for_display_partial, show_edit_button: true }
            if field == 'tools'
              slim :_agent_tool_table, layout: false, locals: agent_data_for_display_partial
            else
              slim :"_display_agent_#{field}", layout: false, locals: response_locals_for_display
            end
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error updating agent '#{name}': #{e.message}")
            halt 500, "Error updating agent definition."
          rescue ArgumentError => e
            halt 400, "Invalid input: #{e.message}"
          end
        end
      end
    end
  end
end

```

---
**Change 2: Filter Abstract Tools from Tool Listings (Medium Priority)**

**Summary:**
Prevent abstract base tool classes like `ADK::Tools::BaseAsyncJobTool` from appearing in user-selectable tool lists in the Web UI and CLI.

**Approach:**
1.  Add an `abstract?` class method to `ADK::Tool`, defaulting to `false`.
2.  Override `abstract?` in base classes like `ADK::Tools::BaseAsyncJobTool` to return `true`.
3.  Modify `ADK::GlobalToolManager.list_all_tools` to filter out tools where `klass.abstract?` is true.

**File Changes:**

**1. `lib/adk/tool.rb`**

```ruby
# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'
require_relative 'tool_context'
require_relative 'global_tool_manager'
require_relative 'tool/metadata_dsl'

module ADK
  class Tool
    include MetadataDsl

    class << self
      attr_reader :tool_name, :description, :parameters_definition

      def define_metadata(name:, description:, parameters: {})
        warn "[DEPRECATION] `define_metadata` is deprecated. Use `tool_description`, `parameter`, and rely on class name inference (or `self.explicit_tool_name = :my_name`) instead. Called from #{caller_locations(1,1)[0].label}"
        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
      end

      # New method to indicate if a tool is an abstract base class
      # and should not be directly instantiated or listed as a usable tool.
      # @return [Boolean] true if the tool is abstract, false otherwise.
      def abstract?
        false
      end
    end

    def self.inherited(subclass)
      super
      ADK.logger.debug("Tool subclass #{subclass} inherited. Attempting registration.")
      ADK::GlobalToolManager.register_tool(subclass)
    end

    attr_reader :name, :description, :parameters

    def initialize(**_options)
      metadata = self.class.tool_metadata
      @name = metadata[:name]
      @description = metadata[:description]
      @parameters = metadata[:parameters] || {}

      if @name.nil? || @name == :'' || @description.nil? || @description.empty?
        is_anonymous = !self.class.name || self.class.name.empty? || self.class.name.start_with?('#<Class:')
        unless is_anonymous
          missing = []
          missing << ':name' if @name.nil? || @name == :''
          missing << ':description' if @description.nil? || @description.empty?
          ADK.logger.warn("Tool class #{self.class} initialized with missing metadata: [#{missing.join(', ')}] using #{self.class.tool_metadata}. Tool may not function correctly.")
        end
        @description ||= ""
      end
    end

    def execute(params = {}, context = nil)
      validate_params(params)
      ADK.logger.debug("Executing tool '#{@name}' with validated params: #{params.inspect} and context: #{context&.to_h.inspect}")
      perform_execution(params, context)
    end

    def validate_params(params)
      current_parameters = @parameters || {}
      required_param_names = current_parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
      present_keys = params.keys.map(&:to_s)
      missing_params = required_param_names - present_keys
      unless missing_params.empty?
        log_message = "Validation failed for tool '#{@name}'. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}"
        ADK.logger.error(log_message)
        raise ADK::ToolArgumentError, "Missing required parameters: #{missing_params.join(', ')}"
      end
    end

    private

    def perform_execution(params, context)
      raise NotImplementedError, "Subclasses must implement #perform_execution(params, context)"
    end
  end
end
```

**2. `lib/adk/tools/base_async_job_tool.rb`**

```ruby
# File: lib/adk/tools/base_async_job_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../error'
require 'sidekiq'
require 'redis'
require 'json'

module ADK
  module Tools
    class BaseAsyncJobTool < ADK::Tool
      tool_description "Base class for tools that initiate long-running tasks via Sidekiq background jobs. Subclasses must implement `sidekiq_worker_class` and `prepare_job_arguments`. Use 'check_job_status' tool to retrieve results."

      # --- Mark this tool as abstract ---
      def self.abstract?
        true
      end
      # --- End abstract marker ---

      JOB_RESULT_REDIS_PREFIX = 'adk:job_result:'
      JOB_RESULT_TTL = 3600

      def sidekiq_worker_class
        raise NotImplementedError, "#{self.class.name} must implement #sidekiq_worker_class"
      end

      def sidekiq_job_options
        { 'queue' => 'default', 'retry' => 3 }
      end

      def prepare_job_arguments(params, context)
        raise NotImplementedError, "#{self.class.name} must implement #prepare_job_arguments(params, context)"
      end

      private def stringify_hash_keys(hash)
        hash.transform_keys(&:to_s)
      end

      private def perform_execution(params, context)
        worker_class = sidekiq_worker_class
        job_args = prepare_job_arguments(params, context)
        job_options = sidekiq_job_options

        unless worker_class && worker_class.respond_to?(:perform_async)
          msg = "sidekiq_worker_class not defined or invalid for tool '#{name}'."
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end

        ADK.logger.info("Enqueuing Sidekiq job for worker '#{worker_class.name}' for tool '#{name}'.")
        ADK.logger.debug("Job Args: #{job_args.inspect}")
        ADK.logger.debug("Job Options: #{job_options.inspect}")

        begin
          job_args = job_args.map do |arg|
            arg.is_a?(Hash) ? stringify_hash_keys(arg) : arg
          end
          jid = worker_class.set(job_options).perform_async(*job_args)
          unless jid
            msg = "Failed to enqueue Sidekiq job for '#{name}'. perform_async returned nil."
            ADK.logger.error(msg)
            raise ADK::ToolError, msg
          end
          ADK.logger.info("Successfully enqueued Sidekiq job '#{jid}' for tool '#{name}'. Task is pending.")
          { status: :pending, job_id: jid }
        rescue Redis::BaseError => e
          msg = "Failed to enqueue job for tool '#{name}': Could not connect to Redis. #{e.message}"
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        rescue StandardError => e
          msg = "Unexpected error enqueuing Sidekiq job for tool '#{name}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          raise ADK::ToolError, msg
        end
      end

      def self.store_job_pending(jid, redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        result_data = { status: :pending, message: "Job processing started." }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored pending status for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store pending status for job #{jid}: #{e.class} - #{e.message}")
      ensure
        redis&.close
      end

      def self.store_job_result(jid, result, redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        result_data = { status: :success, result: result }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored successful result for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store result for job #{jid}: #{e.class} - #{e.message}")
      ensure
        redis&.close
      end

      def self.store_job_error(jid, error_message, error_class = 'StandardError', redis_options = nil)
        redis = Redis.new(redis_options || ADK.redis_options)
        key = "#{JOB_RESULT_REDIS_PREFIX}#{jid}"
        result_data = { status: :error, error_message: "#{error_class}: #{error_message}" }
        redis.setex(key, JOB_RESULT_TTL, result_data.to_json)
        ADK.logger.debug("Stored error result for job #{jid} at key #{key}")
      rescue StandardError => e
        ADK.logger.error("Failed to store error for job #{jid}: #{e.class} - #{e.message}")
      ensure
        redis&.close
      end
    end
  end
end
```

**3. `lib/adk/global_tool_manager.rb`**

```ruby
# lib/adk/global_tool_manager.rb
# frozen_string_literal: true

require 'logger'
require_relative 'tool'
require_relative 'tool/metadata_dsl'

module ADK
  module GlobalToolManager
    @@defined_tools = {}

    def self.register_tool(tool_class)
      unless tool_class < ADK::Tool
        ADK.logger.warn("GlobalToolManager: Attempted to register non-tool class: #{tool_class.inspect}")
        return
      end

      # --- ADDED: Skip registration if tool class is abstract ---
      if tool_class.respond_to?(:abstract?) && tool_class.abstract?
        ADK.logger.debug("GlobalToolManager: Skipping registration of abstract tool class: #{tool_class.name}")
        return
      end
      # --- END ADDED ---

      metadata = tool_class.tool_metadata
      tool_name = metadata[:name]&.to_sym

      if tool_name.nil? || tool_name == :''
        if tool_class.instance_variable_defined?(:@tool_name)
          tool_name = tool_class.instance_variable_get(:@tool_name)
          ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} using name from deprecated @tool_name: #{tool_name.inspect}")
        else
          begin
            if tool_class.respond_to?(:inferred_name)
              inferred = tool_class.inferred_name
              if inferred
                ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} had no explicit name, using inferred name: #{inferred.inspect}")
                tool_name = inferred
              else
                ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no explicit name and inference failed (maybe anonymous?). Skipping registration.")
                return
              end
            else
              ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no name defined via tool_metadata or @tool_name, and does not support inferred_name. Skipping registration.")
              return
            end
          rescue StandardError => e
            ADK.logger.error("GlobalToolManager: Error during name inference for #{tool_class}: #{e.message}")
            return
          end
        end
      end

      tool_name = tool_name&.to_sym
      if tool_name.nil? || tool_name == :''
        ADK.logger.error("GlobalToolManager: Could not determine a valid tool name for #{tool_class}. Skipping registration.")
        return
      end

      if @@defined_tools.key?(tool_name) && @@defined_tools[tool_name] != tool_class
        ADK.logger.warn("GlobalToolManager: Tool name '#{tool_name}' is already registered with class #{@@defined_tools[tool_name]}. Overwriting with #{tool_class}.")
      elsif !@@defined_tools.key?(tool_name)
        ADK.logger.debug("GlobalToolManager: Registered tool '#{tool_name}' with class #{tool_class}.") unless @@defined_tools.key?(tool_name)
      end
      @@defined_tools[tool_name] = tool_class
    end

    def self.list_all_tools
      @@defined_tools.map do |name_sym, klass|
        # --- ADDED: Filter out abstract tools here too for safety ---
        next if klass.respond_to?(:abstract?) && klass.abstract?
        # --- END ADDED ---
        metadata = klass.tool_metadata
        {
          name: metadata[:name] || name_sym,
          description: metadata[:description] || "[No description provided]",
          parameters: metadata[:parameters] || []
        }
      end.compact.sort_by { |t| t[:name].to_s } # Added compact to remove nils from next
    end

    def self.find_class(name_symbol)
      found_class = @@defined_tools[name_symbol.to_sym]
      # --- ADDED: Return nil if found class is abstract ---
      return nil if found_class && found_class.respond_to?(:abstract?) && found_class.abstract?
      # --- END ADDED ---
      found_class
    end

    def self.registered_tool_names
      @@defined_tools.reject { |_, klass| klass.respond_to?(:abstract?) && klass.abstract? }.keys
    end

    def self.create_instance(name_symbol)
      klass = find_class(name_symbol.to_sym) # find_class now handles abstract check
      if klass
        begin
          instance = klass.new
          ADK.logger.debug("GlobalToolManager: Successfully instantiated tool '#{name_symbol}'.")
          instance
        rescue StandardError => e
          ADK.logger.error("GlobalToolManager: Failed to instantiate tool '#{name_symbol}' (Class: #{klass}): #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          nil
        end
      else
        ADK.logger.warn("GlobalToolManager: Attempted to create instance of tool '#{name_symbol}' which is not globally registered or is abstract.")
        nil
      end
    end

    def self.reset!
      @@defined_tools = {}
    end
  end
end
```

---

**Change 3: Add CSS for `.is-newly-added` (Low Priority)**

**Summary:**
Provide visual feedback when a new agent is added to the list on the `/agents` page.

**File Change:**

**1. `lib/adk/web/public/styles/main.scss`** (add at the end or in a relevant section)

```scss
// ... (existing SCSS) ...

/* --- Agent List Enhancements --- */
tr.is-newly-added {
  animation: highlight-new-row 2s ease-out;
}

@keyframes highlight-new-row {
  0% {
    background-color: hsl(171, 100%, 41%); /* Bulma's $primary color */
    color: hsl(0, 0%, 96%); /* Bulma's $primary-invert color */
  }
  20% {
    background-color: hsl(171, 100%, 41%);
    color: hsl(0, 0%, 96%);
  }
  100% {
    background-color: transparent; /* Or initial row color if striped */
    color: inherit;
  }
}
```

**Important:** After changing `main.scss`, you need to recompile it to `main.css`. You can do this by running `bundle exec rake sass` or `bundle exec ruby bin/compile-sass`.

---

**Change 4: Clarify/Remove `tool_detail.slim` (Low Priority)**

**Recommendation:**
Based on the screenshots and current route structure, `tool.slim` is the primary view for tool details and includes the "Try it out" functionality. `tool_detail.slim` seems redundant.

**Action:**
1.  **Verify:** Double-check if `tool_detail.slim` is linked from anywhere or used by any route that isn't already covered by `tool.slim`. (It appears not to be directly used by the main UI flow shown in screenshots).
2.  **If Unused:**
    *   Delete the file: `lib/adk/web/views/tool_detail.slim`.
    *   If there was any route specifically rendering `tool_detail`, remove or refactor that route in `lib/adk/web/routes/tools_ui_routes.rb`. (Currently, only `GET /tools/:name` exists, which renders `tool.slim`).
3.  **If It Has a Purpose:** Document its distinct purpose and ensure it's correctly integrated and styled.

Given the current structure, deletion seems appropriate to simplify the codebase.

---

These changes address the most critical issues and some of the improvements for the ADK Web UI. Further refinements can be made to the UX and error handling as separate steps.