# File: lib/adk/web/routes/agent_runtime_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module AgentRuntimeRoutes
      def self.registered(app)
        # POST /agents/:name/start/detail - Start a runtime instance (from agent detail view).
        app.post '/agents/:name/start/detail' do |name|
          content_type :html
          agent_instance = self.send(:_start_agent, name) # Renamed to avoid confusion

          is_running = !agent_instance.nil?
          agent_data_for_view = nil
          definition_store = self.instance_variable_get(:@definition_store)

          if agent_instance # Agent started successfully
            # Ensure agent_data_for_view is a Hash, similar to the else block
            definition = definition_store&.get_definition(name) # Re-fetch definition for consistency
            if definition
              agent_data_for_view = {
                name: name,
                description: definition[:description],
                running: is_running,
                model: definition[:model]
                # Potentially add other fields from definition if needed by partials
              }
            else # Should not happen if agent started, but as a fallback
              agent_data_for_view = { name: name, description: 'Started (Def error)', running: is_running,
                                      model: 'N/A' }
            end
          else # Agent failed to start, fetch definition for display
            if definition_store
              begin
                definition = definition_store.get_definition(name)
                if definition
                  agent_data_for_view = {
                    name: name, description: definition[:description],
                    running: false, model: definition[:model]
                  }
                else
                  agent_data_for_view = { name: name, description: 'Error: Definition not found', running: false,
                                          model: 'N/A' }
                end
              rescue ADK::DefinitionStore::StoreError => e
                logger.error("Store error fetching definition after failed start for '#{name}' (from AgentRuntimeRoutes): #{e.message}")
                agent_data_for_view = { name: name, description: 'Error retrieving definition', running: false,
                                        model: 'N/A' }
              end
            else
              agent_data_for_view = { name: name, description: 'Error: Store unavailable', running: false,
                                      model: 'N/A' }
            end
          end

          # agent_data_for_view is now consistently a Hash
          # ... rest of the route uses agent_data_for_view[:running] ...

          status_controls_html = slim(:_agent_status_controls, layout: false,
                                                               locals: { agent_data: agent_data_for_view })

          execute_button_text = is_running ? 'Execute' : 'Execute (Requires Start)'
          disabled_attr_string = is_running ? '' : 'disabled'
          execute_button_oob_html = %(
            <button class="button is-primary" id="execute-task-button" type="submit" #{disabled_attr_string} hx-swap-oob="outerHTML">
              <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
              <span>#{execute_button_text}</span>
            </button>
          )
          chat_input_oob_html = %(<input class="input" id="chat-input" type="text" name="message" placeholder="Enter your message..." required="true" autofocus #{disabled_attr_string} hx-swap-oob="outerHTML">)
          chat_button_oob_html = %(<button class="button is-link" id="send-button" type="submit" #{disabled_attr_string} hx-swap-oob="outerHTML"><span>Send</span><span class="icon is-small htmx-indicator ml-2" id="send-button-indicator"><i class="fas fa-spinner fa-pulse"></i></span></button>)

          # --- MODIFIED: Determine content for chat-status-help-container ---
          new_chat_status_help_content = ''
          if is_running # is_running reflects the new state of the agent
            # Agent is running, attempt to ensure an active session for the help text
            web_user_id = session[:web_user_id]
            session_service = self.instance_variable_get(:@session_service)
            active_session_object_for_help_check = nil

            if web_user_id && session_service
              # 1. Try to load session from Sinatra session store
              stored_active_adk_session_id = session.dig(:active_agent_sessions, name)
              if stored_active_adk_session_id
                begin
                  potential_session = session_service.get_session(session_id: stored_active_adk_session_id)
                  if potential_session && potential_session.user_id == web_user_id && potential_session.app_name == name
                    active_session_object_for_help_check = potential_session
                    logger.debug "OOB Chat Help (Start): Found valid session '#{stored_active_adk_session_id}' from Sinatra session for agent '#{name}'."
                  else
                    logger.warn "OOB Chat Help (Start): Stored session ID '#{stored_active_adk_session_id}' invalid/mismatched for agent '#{name}'. Clearing from Sinatra session."
                    session[:active_agent_sessions]&.delete(name)
                  end
                rescue => e
                  logger.error("OOB Chat Help (Start): Error fetching stored session '#{stored_active_adk_session_id}' for agent '#{name}': #{e.message}")
                  session[:active_agent_sessions]&.delete(name) # Clear if error
                end
              end

              # 2. If no valid session from Sinatra store, try to find latest or create new
              unless active_session_object_for_help_check
                logger.debug "OOB Chat Help (Start): No valid session from Sinatra store. Attempting to find/create for agent '#{name}', user '#{web_user_id}'."
                begin
                  user_agent_sessions = session_service.list_sessions(app_name: name, user_id: web_user_id)
                  if user_agent_sessions && !user_agent_sessions.empty?
                    latest_session = user_agent_sessions.sort_by(&:updated_at).last
                    if latest_session
                      active_session_object_for_help_check = latest_session
                      logger.info "OOB Chat Help (Start): Found latest existing session '#{latest_session.id}' for agent '#{name}'."
                    end
                  end

                  unless active_session_object_for_help_check
                    new_session = session_service.create_session(app_name: name, user_id: web_user_id,
                                                                 initial_state: {})
                    active_session_object_for_help_check = new_session
                    logger.info "OOB Chat Help (Start): Created new session '#{new_session.id}' for agent '#{name}'."
                  end

                  # Store the found/created session ID in Sinatra session
                  if active_session_object_for_help_check
                    session[:active_agent_sessions] ||= {}
                    session[:active_agent_sessions][name] = active_session_object_for_help_check.id
                    logger.debug "OOB Chat Help (Start): Stored session '#{active_session_object_for_help_check.id}' in Sinatra session for agent '#{name}'."
                  end
                rescue => e
                  logger.error "OOB Chat Help (Start): Critical error finding/creating session for agent '#{name}', user '#{web_user_id}': #{e.message}"
                  # If session creation fails, active_session_object_for_help_check will remain nil
                end
              end
            else
              logger.error "OOB Chat Help (Start): web_user_id or session_service not available. Cannot manage session for help text for agent '#{name}'."
            end

            # Final determination of help content based on whether an active session is now established
            if active_session_object_for_help_check
              new_chat_status_help_content = %(<p class="help is-hidden">No issues.</p>)
            else
              # This branch means session_service might be down, or a user_id is missing, or find/create failed critically.
              new_chat_status_help_content = %(<p id="chat-no-active-session-help" class="help is-warning">Chat session not active. Please try starting a new chat or reloading the page.</p>)
            end
          else
            # Agent is not running
            new_chat_status_help_content = %(<p id="chat-not-running-help" class="help is-danger">Agent must be running to chat.</p>)
          end

          chat_help_oob_html = %(<div id="chat-status-help-container" hx-swap-oob="innerHTML" class="mt-2">#{new_chat_status_help_content}</div>)
          # --- END MODIFICATION ---

          chat_panel_status_html = %(
            <div id="agent-chat-panel-status-display" hx-swap-oob="innerHTML">
              <p>
                <strong>Status:</strong>
                <span class="tag ml-2 #{agent_data_for_view[:running] ? 'is-success' : 'is-danger'}">
                  #{agent_data_for_view[:running] ? 'Running' : 'Stopped (Go to agent page to start)'}
                </span>
              </p>
            </div>
          )
          status 200
          status_controls_html + execute_button_oob_html + chat_input_oob_html + chat_button_oob_html + chat_help_oob_html + chat_panel_status_html
        end

        # POST /agents/:name/stop/detail - Stop a runtime instance (from agent detail view).
        app.post '/agents/:name/stop/detail' do |name|
          content_type :html
          self.send(:_stop_agent, name) # Call private helper

          # Explicitly set status variables after stopping
          is_running = false
          disabled_attr_string = 'disabled'
          execute_button_text = 'Execute (Requires Start)'
          # Ensure agent_data_for_view reflects running: false (already done in previous step)

          agent_data_for_view = nil
          definition_store = self.instance_variable_get(:@definition_store)
          if definition_store
            begin
              agent_definition = definition_store.get_definition(name)
              if agent_definition
                agent_data_for_view = {
                  name: name, description: agent_definition[:description],
                  running: is_running, # Use the explicitly set 'is_running'
                  model: agent_definition[:model]
                }
              else
                agent_data_for_view = { name: name, description: 'Error: Definition not found', running: is_running,
                                        model: 'N/A' }
              end
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error fetching definition after stop detail for '#{name}' (from AgentRuntimeRoutes): #{e.message}")
              agent_data_for_view = { name: name, description: 'Error retrieving definition', running: is_running,
                                      model: 'N/A' }
            end
          else
            agent_data_for_view = { name: name, description: 'Error: Store unavailable', running: is_running,
                                    model: 'N/A' }
          end

          status_controls_html = slim(:_agent_status_controls, layout: false,
                                                               locals: { agent_data: agent_data_for_view })

          execute_button_oob_html = %(<button class="button is-link" id="execute-task-button" type="submit" #{disabled_attr_string} hx-swap-oob="outerHTML"> <span class="icon is-small htmx-indicator mr-1"><i class="fas fa-spinner fa-pulse"></i></span> <span class="icon is-small"><i class="fas fa-play-circle"></i></span> <span>#{execute_button_text}</span> </button>)
          chat_input_oob_html = %(<input class="input" id="chat-input" type="text" name="message" placeholder="Enter your message..." required="true" autofocus #{disabled_attr_string} hx-swap-oob="outerHTML">)
          chat_button_oob_html = %(<button class="button is-link" id="send-button" type="submit" #{disabled_attr_string} hx-swap-oob="outerHTML"><span>Send</span><span class="icon is-small htmx-indicator ml-2" id="send-button-indicator"><i class="fas fa-spinner fa-pulse"></i></span></button>)

          # --- MODIFIED: Determine content for chat-status-help-container ---
          # is_running is false in this context (agent stop)
          new_chat_status_help_content = ''
          if is_running # This will be false
            # This block should ideally not be reached if is_running is false,
            # but keeping structure for clarity, will be optimized by the 'else'.
            web_user_id = session[:web_user_id]
            session_service = self.instance_variable_get(:@session_service)
            active_session_details = nil
            # 'name' is the agent_name from the route parameter

            if web_user_id && session_service
              active_adk_session_id = session.dig(:active_agent_sessions, name)
              if active_adk_session_id
                begin
                  potential_session = session_service.get_session(session_id: active_adk_session_id)
                  if potential_session && potential_session.user_id == web_user_id && potential_session.app_name == name
                    active_session_details = potential_session
                  end
                rescue => e
                  logger.error("OOB Chat Help (Stop - Running Path, Unexpected): Error fetching session #{active_adk_session_id} for agent #{name}: #{e.message}")
                end
              end
            end

            if active_session_details
              new_chat_status_help_content = %(<p class="help is-hidden">No issues.</p>)
            else
              new_chat_status_help_content = %(<p id="chat-no-active-session-help" class="help is-warning">No active chat session. Please start a new chat from the sidebar.</p>)
            end
          else
            # Agent is not running (this is the expected path for agent stop)
            new_chat_status_help_content = %(<p id="chat-not-running-help" class="help is-danger">Agent must be running to chat.</p>)
          end

          chat_help_oob_html = %(<div id="chat-status-help-container" hx-swap-oob="innerHTML" class="mt-2">#{new_chat_status_help_content}</div>)
          # --- END MODIFICATION ---

          chat_panel_status_html = %(
            <div id="agent-chat-panel-status-display" hx-swap-oob="innerHTML">
              <p>
                <strong>Status:</strong>
                <span class="tag ml-2 #{agent_data_for_view[:running] ? 'is-success' : 'is-danger'}">
                  #{agent_data_for_view[:running] ? 'Running' : 'Stopped (Go to agent page to start)'}
                </span>
              </p>
            </div>
          )
          status 200
          status_controls_html + execute_button_oob_html + chat_input_oob_html + chat_button_oob_html + chat_help_oob_html + chat_panel_status_html
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
                                  { name: name, description: 'N/A', model: 'N/A', tools: [] } # Minimal fallback with all expected keys by _agent_row or its fragments
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
                                  { name: name, description: 'N/A', model: 'N/A', tools: [] }
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
