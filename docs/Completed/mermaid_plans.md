Yes, absolutely! Leveraging Mermaid.js to visualize an agent's actions and tool usage from `ADK::Event` data is an excellent idea for debugging, understanding agent behavior, and showcasing its process.

Here's a plan to implement this feature:

**Core Idea:**

Translate the sequence of events (especially `user_input`, `tool_request`, `tool_result`, and final `agent` response, often found within `plan_details` of the final agent event) into a Mermaid sequence diagram definition.

**1. Backend Changes (`lib/adk/web/app.rb` Helpers):**

We'll create a new helper method to generate the Mermaid diagram string.

```ruby
# File: lib/adk/web/app.rb
# ... (existing code) ...

helpers do
  # ... (existing helpers) ...

  # --- NEW HELPER: Generate Mermaid Sequence Diagram from Agent Event ---
  # Takes the final ADK::Event from an agent.run_task call.
  # The event.content is expected to be a hash, potentially containing :plan_details.
  # Also takes the original_user_input for the start of the diagram.
  def generate_mermaid_sequence_diagram(final_agent_event_content, original_user_input)
    return "" unless final_agent_event_content.is_a?(Hash)

    mermaid_def = ["sequenceDiagram"]
    participants = Set.new(['User', 'Agent']) # Start with base participants

    plan_details = final_agent_event_content[:plan_details]
    plan_details = [] unless plan_details.is_a?(Array) # Ensure it's an array

    # Collect all unique tool names to declare them as participants
    plan_details.each do |step|
      participants.add("Tool(#{step[:tool_name]})") if step[:tool_name]
    end
    participants.each { |p| mermaid_def << "  participant #{p}" }

    # 1. User to Agent (Initial Request)
    mermaid_def << "  User->>Agent: #{escape_mermaid_label(original_user_input)}"

    # 2. Agent to Tool and Tool to Agent (from plan_details)
    plan_details.each_with_index do |step, index|
      tool_name_str = step[:tool_name]&.to_s || "UnknownTool"
      tool_participant = "Tool(#{tool_name_str})"
      params_summary = step[:params].is_a?(Hash) ? summarize_for_mermaid(step[:params]) : "Invalid Params"

      mermaid_def << "  Agent->>#{tool_participant}: Call #{tool_name_str} with #{params_summary}"

      result_data = step[:result] # This is the {status: ..., result/error_message: ...} hash
      if result_data.is_a?(Hash)
        status = result_data[:status]&.to_s || "unknown"
        case status.to_sym
        when :success
          result_summary = summarize_for_mermaid(result_data[:result])
          mermaid_def << "  #{tool_participant}-->>Agent: Result: #{result_summary}"
        when :error
          error_summary = summarize_for_mermaid(result_data[:error_message] || "Unknown Error")
          mermaid_def << "  #{tool_participant}-->>Agent: Error: #{error_summary}"
        when :pending
          job_id_summary = summarize_for_mermaid(result_data[:job_id] || "N/A")
          mermaid_def << "  #{tool_participant}-->>Agent: Pending (Job ID: #{job_id_summary})"
        else
          mermaid_def << "  #{tool_participant}-->>Agent: Result (Status: #{status}): #{summarize_for_mermaid(result_data)}"
        end
      else
        mermaid_def << "  #{tool_participant}-->>Agent: Malformed Result: #{summarize_for_mermaid(result_data)}"
      end
    end

    # 3. Agent to User (Final Response)
    final_response_summary = ""
    if final_agent_event_content[:status] == :success
      final_response_summary = "Final Result: #{summarize_for_mermaid(final_agent_event_content[:result])}"
    elsif final_agent_event_content[:status] == :error
      final_response_summary = "Final Error: #{summarize_for_mermaid(final_agent_event_content[:error_message])}"
    elsif final_agent_event_content[:status] == :pending
      final_response_summary = "Task Pending: Job ID #{summarize_for_mermaid(final_agent_event_content[:job_id])}"
    else
      final_response_summary = "Final Response (Status: #{final_agent_event_content[:status]}): #{summarize_for_mermaid(final_agent_event_content)}"
    end
    mermaid_def << "  Agent-->>User: #{final_response_summary}"

    mermaid_def.join("\n")
  end

  # Helper to sanitize and summarize complex data for Mermaid labels
  def summarize_for_mermaid(data, max_length = 70)
    return "nil" if data.nil?
    summary = ""
    if data.is_a?(Hash) || data.is_a?(Array)
      summary = data.inspect # Basic inspection for complex types
    else
      summary = data.to_s
    end

    # Escape characters that break Mermaid syntax
    summary = escape_mermaid_label(summary)

    if summary.length > max_length
      summary = summary[0...(max_length - 3)] + "..."
    end
    summary
  end

  # Helper to escape characters problematic for Mermaid labels
  def escape_mermaid_label(text)
    return "" if text.nil?
    text.to_s.gsub(":", "#colon;")
             .gsub(";", "#semi;")
             .gsub("(", "#lpar;")
             .gsub(")", "#rpar;")
             .gsub("\n", "<br>") # Mermaid uses <br> for newlines in labels
             .gsub("`", "#bquot;")
             .gsub("\"", "&quot;")
             .gsub(/->>/, "-&gt;&gt;")
             .gsub(/-->>/, "--&gt;&gt;")
             .gsub(/->/, "-&gt;")
             .gsub(/--/, "- -") # Avoid activating solid lines unintentionally
  end
  # --- END NEW HELPERS ---

  # ... (process_agent_response and other helpers) ...
end

# ... (rest of app.rb) ...
```

**2. Frontend Changes:**

**Modify `lib/adk/web/views/_chat_message.slim`:**

Add a section to display the Mermaid diagram, perhaps hidden by default and expandable.

```slim
/ File: lib/adk/web/views/_chat_message.slim
/ ... (existing user message part) ...

- response_data = process_agent_response(agent_result)
- original_user_input_for_diagram = user_message # Capture user_message for the diagram

.message class="#{response_data[:msg_class]} agent-message is-small mb-4" id="event-#{response_data[:event_id]}" style="border-radius: 6px; overflow: hidden;"
  .message-header style="border-top-left-radius: 6px; border-top-right-radius: 6px;"
    / ... (existing header content for agent name, tool request/result status) ...
    
    - unless response_data[:raw_json_content].empty?
      button.button.is-light.is-small.ml-1( onclick="var el = document.getElementById('raw-#{response_data[:event_id]}'); el.style.display = (el.style.display == 'none' ? 'block' : 'none');" )
        | Raw JSON
    /! --- NEW: Mermaid Diagram Toggle ---
    - if agent_result.is_a?(ADK::Event) && agent_result.role == :agent && agent_result.content.is_a?(Hash) && agent_result.content[:plan_details]
      button.button.is-light.is-small.ml-1( onclick="var el = document.getElementById('mermaid-#{response_data[:event_id]}'); el.style.display = (el.style.display == 'none' ? 'block' : 'none'); if(el.style.display == 'block') { mermaid.run({nodes: [el.querySelector('.mermaid')]}) };" )
        span.icon.is-small
          i.fas.fa-project-diagram
        span Flow
    /! --- END NEW ---
  
  .message-body style="border-bottom-left-radius: 6px; border-bottom-right-radius: 6px;"
    / ... (existing logic for displaying textual response_data[:display_content] and plan_details) ...
    
    - unless response_data[:raw_json_content].empty?
      div.raw-json-container id="raw-#{response_data[:event_id]}" style="display: none;"
        pre.raw-json-pre= response_data[:raw_json_content]

    /! --- NEW: Mermaid Diagram Container ---
    - if agent_result.is_a?(ADK::Event) && agent_result.role == :agent && agent_result.content.is_a?(Hash) && agent_result.content[:plan_details]
      - mermaid_definition = generate_mermaid_sequence_diagram(agent_result.content, original_user_input_for_diagram)
      - unless mermaid_definition.empty?
        div.mermaid-diagram-container id="mermaid-#{response_data[:event_id]}" style="display: none; margin-top: 1rem; border-top: 1px dashed #ccc; padding-top: 1rem;"
          pre.mermaid= mermaid_definition
    /! --- END NEW ---
```

**Explanation of Changes:**

*   **`generate_mermaid_sequence_diagram(final_agent_event_content, original_user_input)` Helper:**
    *   Takes the content hash of the final `:agent` event (which should contain `plan_details`) and the original user input.
    *   Initializes a Mermaid sequence diagram definition.
    *   Dynamically declares `User`, `Agent`, and all unique `Tool(ToolName)` participants found in the plan.
    *   Adds the initial `User->>Agent` interaction using the `original_user_input`.
    *   Iterates through `plan_details`:
        *   For each step, it adds `Agent->>Tool(name)` with summarized parameters.
        *   It then adds `Tool(name)-->>Agent` with the summarized result, error, or pending status.
    *   Adds the final `Agent-->>User` response.
    *   Uses a `summarize_for_mermaid` helper to keep labels concise and `escape_mermaid_label` to prevent syntax errors.
*   **`summarize_for_mermaid(data, max_length = 70)` Helper:**
    *   Converts data to a string.
    *   Uses `.inspect` for hashes/arrays to provide a basic string representation.
    *   Escapes characters problematic for Mermaid.
    *   Truncates long strings.
*   **`escape_mermaid_label(text)` Helper:**
    *   Crucial for replacing characters like `:`, `;`, `(`, `)`, `\n`, ``` ` ```, `"` that would break Mermaid syntax or render poorly.
*   **Frontend (`_chat_message.slim`):**
    *   A "Flow" button is added to the agent message header *only if* the agent event contains `plan_details`.
    *   Clicking the button toggles the visibility of a `div.mermaid-diagram-container`.
    *   The `generate_mermaid_sequence_diagram` helper is called to populate a `pre.mermaid` element with the diagram definition.
    *   **Crucially**, the `onclick` for the "Flow" button now also includes `if(el.style.display == 'block') { mermaid.run({nodes: [el.querySelector('.mermaid')]}) };`. This ensures that `mermaid.run()` is explicitly called *only on the newly visible diagram* when the user expands it. This is more efficient than a global `mermaid.run()` after every HTMX swap if many diagrams are potentially hidden.

**Modify `lib/adk/web/views/agent.slim` (for Direct Execution Task Result):**

We need to provide the original task JSON (or at least the "task" description part) to the `generate_mermaid_sequence_diagram` helper.

```slim
/ File: lib/adk/web/views/agent.slim
/ ...
/ Execute Task box
.box.mb-5
  h3.title.is-5 Execute Task
  /! --- MODIFIED: Add an ID to the textarea to grab its content ---
  form#execute-task-form( hx-post="/agents/#{agent_name}/execute"
                          hx-target="#task-result"
                          hx-swap="innerHTML"
                          hx-indicator="#execute-task-button .htmx-indicator" )
      .field
        label.label Task (JSON Input)
        p.help.is-size-7 Format: `{"task": "..."}` or `{"tool_name": "...", ...}`
        .control
          /! --- ADDED ID ---
          textarea.textarea#direct-task-json-input name="task_json" placeholder='e.g., {"task": "Summarize article..."}' required=true rows="10"
      / ... (buttons remain the same) ...

  label.label.mt-4 Result
  /! --- MODIFIED: Add a container for the Mermaid toggle and diagram ---
  div#task-result-container
    #task-result.content.box.is-small( style="min-height: 100px; background-color: #fafafa; white-space: pre-wrap; word-break: break-word;" )
      p.has-text-grey.is-italic Task results will appear here.
    /! --- NEW: Mermaid diagram section for direct execution ---
    div#task-result-mermaid-container.is-hidden.mt-3 style="border-top: 1px dashed #ccc; padding-top: 1rem;"
      button.button.is-small.is-pulled-right(onclick="this.parentElement.classList.add('is-hidden');") Close Diagram
      h4.title.is-6 Execution Flow
      pre.mermaid
        /! Mermaid definition will be injected here by HTMX response or JS
  /! --- END MODIFICATION ---
/ ...
```

**Modify `lib/adk/web/routes/agent_interaction_routes.rb` (for `POST /agents/:name/execute`):**

The route needs to generate the diagram and include it in the response, potentially as a separate OOB swap or part of the main `#task-result` swap.

```ruby
# File: lib/adk/web/routes/agent_interaction_routes.rb
# ...
app.post '/agents/:name/execute' do |name|
  # ... (existing setup and error handling for agent, json_string, task_desc) ...
  # ... (inside the final begin/rescue/ensure block for agent_instance.run_task or tool_instance.execute) ...

  # Assuming `final_result_content` is the hash {status: ..., result: ..., plan_details: ...}
  # And `task_desc` is the user's input task string.

  # --- NEW: Generate Mermaid Diagram ---
  mermaid_diagram_html = ""
  original_input_for_diagram = task_desc # Or try to get from parsed_data if more specific
  if final_result_content.is_a?(Hash) && final_result_content[:plan_details]
    mermaid_def = generate_mermaid_sequence_diagram(final_result_content, original_input_for_diagram)
    unless mermaid_def.empty?
      # This HTML will be part of the response swapped into #task-result
      # It includes the pre.mermaid tag and a button to show it.
      # The JS to toggle visibility and run mermaid will be on the main page.
      mermaid_diagram_html = <<~HTML
        <div class="mt-3 pt-3" style="border-top: 1px dashed #ccc;">
          <button class="button is-small is-info is-light mb-2"
                  onclick="var diag = document.getElementById('direct-exec-mermaid-#{name}'); diag.classList.toggle('is-hidden'); if (!diag.classList.contains('is-hidden')) { mermaid.run({nodes: [diag.querySelector('.mermaid')]}); }">
            <span class="icon is-small"><i class="fas fa-project-diagram"></i></span>
            <span>Toggle Execution Flow</span>
          </button>
          <div id="direct-exec-mermaid-#{name}" class="is-hidden">
            <pre class="mermaid">#{mermaid_def}</pre>
          </div>
        </div>
      HTML
    end
  end
  # --- END NEW ---

  # Modify success_handler to include the mermaid diagram HTML
  success_handler = lambda do |result_hash|
    formatted_result_html = format_execution_result_html(result_hash)
    # Append the mermaid diagram HTML to the formatted result
    formatted_result_html + mermaid_diagram_html
  end

  # ... (rest of the execute route logic for calling agent/tool and using success_handler/error_handler) ...
  # Ensure the success_handler is called with the final_result_content (which contains plan_details)
  # Example for planner path:
  # final_result_content = final_result.is_a?(ADK::Event) ? final_result.content : final_result
  # success_handler.call(final_result_content)
end
# ...
```

**3. JavaScript in `lib/adk/web/views/layout.slim`:**

Ensure `mermaid.run()` is called appropriately. The existing `htmx:afterSwap` listener is a good place, but for toggleable diagrams, a more targeted call is better.

The `onclick` handlers added to the "Flow" buttons in `_chat_message.slim` and the "Toggle Execution Flow" button (rendered by the backend for direct execution) now explicitly call `mermaid.run({nodes: [...]})` when the diagram is made visible. This avoids re-rendering all mermaid diagrams on the page.

**Key Steps and Considerations:**

*   **Participant Sanitization:** Tool names in Mermaid participant declarations cannot contain special characters like `( ) : ;`. The `escape_mermaid_label` helper should be robust enough, or you might need a specific sanitizer for participant names. The `Tool(#{name})` syntax is generally safe.
*   **Label Content:**
    *   Keep labels (messages between participants) concise. Long JSON payloads for params/results should be summarized or truncated (as done by `summarize_for_mermaid`).
    *   Escape special Mermaid characters (`:`, `;`, `(`, `)`) and newlines (`<br>`) within labels.
*   **Error Handling in Helper:** The `generate_mermaid_sequence_diagram` helper should be robust against missing `plan_details` or malformed event content.
*   **Performance:** For very long event histories or complex plans, generating the Mermaid string could take some time. This is a server-side operation, so it might slightly delay the response.
*   **Mermaid Initialization:** The `mermaid.run()` call in `htmx:afterSwap` in `layout.slim` should generally pick up new `.mermaid` elements. The targeted `mermaid.run({nodes: [...]})` in the `onclick` handlers is a more precise way to ensure rendering when a specific hidden diagram is revealed.
*   **Styling:** You might want to add some CSS for the `mermaid-diagram-container` and the toggle button.

This implementation provides a powerful visualization tool directly within your ADK Web UI, aiding significantly in understanding and debugging agent behavior.