# File: lib/adk/web/routes/agent_runtime_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentRuntimeRoutes
      def self.registered(app)
        # POST /agents/:name/start/detail - Start a runtime instance (from agent detail view).
        app.post '/agents/:name/start/detail' do |name|
          content_type :html
          # `self` is the Sinatra app instance here
          agent = self.send(:_start_agent, name) # Call private helper

          is_running = !agent.nil?
          agent_data_for_view = nil
          # Access instance variables of the app instance via `self`
          definition_store = self.instance_variable_get(:@definition_store)

          if agent # Agent started successfully
            agent_data_for_view = agent # Assuming agent object has needed attrs for partial
          else # Agent failed to start, fetch definition for display
            if definition_store
              begin
                definition = definition_store.get_definition(name)
                if definition
                  agent_data_for_view = {
                    name: name, description: definition[:description],
                    running: false, model: definition[:model]
                    # Add other fields if the partial needs them
                  }
                else
                  agent_data_for_view = { name: name, description: "Error: Definition not found", running: false,
                                          model: "N/A" }
                end
              rescue ADK::DefinitionStore::StoreError => e
                logger.error("Store error fetching definition after failed start for '#{name}' (from AgentRuntimeRoutes): #{e.message}")
                agent_data_for_view = { name: name, description: "Error retrieving definition", running: false,
                                        model: "N/A" }
              end
            else
              agent_data_for_view = { name: name, description: "Error: Store unavailable", running: false,
                                      model: "N/A" }
            end
          end

          status_controls_html = slim(:_agent_status_controls, layout: false,
                                                               locals: { agent_data: agent_data_for_view })

          execute_button_text = is_running ? 'Execute' : 'Execute (Requires Start)'
          disabled_attr_string = is_running ? '' : 'disabled'
          execute_button_oob_html = %(
            <button class="button is-primary" id="execute-task-button" type="submit" #{disabled_attr_string} hx-swap-oob="true">
              <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
              <span>#{execute_button_text}</span>
            </button>
          )
          chat_input_oob_html = %(
            <input class="input" id="chat-input" type="text" name="message" placeholder="Enter your message..." required="true" autofocus #{disabled_attr_string} hx-swap-oob="true">
          )
          chat_button_oob_html = %(
            <button class="button is-info" id="send-button" type="submit" #{disabled_attr_string} hx-swap-oob="true">
              <span>Send</span>
              <span class="icon is-small htmx-indicator ml-2" id="send-button-indicator"><i class="fas fa-spinner fa-pulse"></i></span>
            </button>
          )
          # Logic for chat_help_oob_html based on is_running
          chat_help_class = is_running ? 'is-hidden' : ''
          chat_help_oob_html = %(<p id="chat-status-help" hx-swap-oob="outerHTML" class="help is-danger #{chat_help_class}">Agent must be running to chat.</p>)

          status 200
          status_controls_html + execute_button_oob_html + chat_input_oob_html + chat_button_oob_html + chat_help_oob_html
        end

        # POST /agents/:name/stop/detail - Stop a runtime instance (from agent detail view).
        app.post '/agents/:name/stop/detail' do |name|
          content_type :html
          # `self` is the Sinatra app instance here
          self.send(:_stop_agent, name) # Call private helper

          agent_data_for_view = nil
          # Access instance variables of the app instance via `self`
          definition_store = self.instance_variable_get(:@definition_store)

          if definition_store
            begin
              agent_definition = definition_store.get_definition(name)
              if agent_definition
                agent_data_for_view = {
                  name: name, description: agent_definition[:description],
                  running: false, model: agent_definition[:model]
                  # Add other fields if the partial needs them
                }
              else
                agent_data_for_view = { name: name, description: "Error: Definition not found", running: false,
                                        model: "N/A" }
              end
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error fetching definition after stop detail for '#{name}' (from AgentRuntimeRoutes): #{e.message}")
              agent_data_for_view = { name: name, description: "Error retrieving definition", running: false,
                                      model: "N/A" }
            end
          else
            agent_data_for_view = { name: name, description: "Error: Store unavailable", running: false, model: "N/A" }
          end

          status_controls_html = slim(:_agent_status_controls, layout: false,
                                                               locals: { agent_data: agent_data_for_view })

          execute_button_oob_html = %(
            <button class="button is-primary" id="execute-task-button" type="submit" disabled hx-swap-oob="true">
              <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
              <span>Execute (Requires Start)</span>
            </button>
          )
          chat_input_oob_html = %(
            <input class="input" id="chat-input" type="text" name="message" placeholder="Enter your message..." required="true" autofocus disabled hx-swap-oob="true">
          )
          chat_button_oob_html = %(
            <button class="button is-info" id="send-button" type="submit" disabled hx-swap-oob="true">
              <span>Send</span>
              <span class="icon is-small htmx-indicator ml-2" id="send-button-indicator"><i class="fas fa-spinner fa-pulse"></i></span>
            </button>
          )
          chat_help_oob_html = %(<p id="chat-status-help" hx-swap-oob="outerHTML" class="help is-danger">Agent must be running to chat.</p>)

          status 200
          status_controls_html + execute_button_oob_html + chat_input_oob_html + chat_button_oob_html + chat_help_oob_html
        end

        # Start agent from main list view (hx-post from _agent_row.slim)
        app.post '/agents/:name/start' do |name|
          # `self` is the Sinatra app instance here
          agent = self.send(:_start_agent, name) # Call private helper
          definition_store = self.instance_variable_get(:@definition_store) # Access ivar

          # Fetch the full definition to ensure all necessary fields for fragments are present
          agent_definition_for_view = definition_store&.get_definition(name) if definition_store

          agent_data_for_view = if agent_definition_for_view
                                  agent_definition_for_view.dup # Make a mutable copy
                                else
                                  { name: name, description: "N/A", model: "N/A", tools: [] } # Minimal fallback with all expected keys by _agent_row or its fragments
                                end

          agent_data_for_view[:running] = !agent.nil? # Update running status based on actual start

          if agent
            logger.info "Agent '#{name}' started from main list (from AgentRuntimeRoutes)."
            status 200
            # Use the helper that generates OOB fragments for the agent row
            # The agent_status_fragments helper is defined in app.rb
            # Ensure all data needed by the fragments (and the elements they target in _agent_row) is in agent_data_for_view
            headers 'Content-Type' => 'text/html' # Ensure correct content type for HTML fragments
            agent_status_fragments(agent_data_for_view)
          else
            logger.error "Failed to start agent '#{name}' from main list (from AgentRuntimeRoutes)."
            status 500 # Keep error status
            agent_data_for_view[:running] = false # Ensure it shows as stopped
            headers 'Content-Type' => 'text/html'
            # Even on failure, we might want to return fragments that update the UI to show 'Stopped'
            # and ensure buttons are correctly disabled/enabled.
            agent_status_fragments(agent_data_for_view)
          end
        end

        # Stop agent from main list view (hx-post from _agent_row.slim)
        app.post '/agents/:name/stop' do |name|
          # `self` is the Sinatra app instance here
          success = self.send(:_stop_agent, name) # Call private helper
          definition_store = self.instance_variable_get(:@definition_store) # Access ivar

          agent_definition_for_view = definition_store&.get_definition(name) if definition_store

          agent_data_for_view = if agent_definition_for_view
                                  agent_definition_for_view.dup
                                else
                                  { name: name, description: "N/A", model: "N/A", tools: [] }
                                end

          agent_data_for_view[:running] = false # After a stop action, it should be marked as not running

          if success
            logger.info "Agent '#{name}' stopped from main list (from AgentRuntimeRoutes)."
            status 200
            headers 'Content-Type' => 'text/html'
            agent_status_fragments(agent_data_for_view)
          else
            logger.error "Failed to stop agent '#{name}' from main list (from AgentRuntimeRoutes) - _stop_agent returned false."
            status 500 # Internal error if _stop_agent fails unexpectedly
            # Still return fragments reflecting the intended (stopped) state or current persisted state
            # Re-fetch definition to be sure of the persisted state if _stop_agent failed.
            current_def_after_fail = definition_store&.get_definition(name)
            if current_def_after_fail
              agent_data_for_view[:running] = (current_def_after_fail[:persistent_status] == 'running')
            else # fallback if def somehow disappeared
              agent_data_for_view[:running] = false # Best guess
            end
            headers 'Content-Type' => 'text/html'
            agent_status_fragments(agent_data_for_view)
          end
        end
      end
    end
  end
end
