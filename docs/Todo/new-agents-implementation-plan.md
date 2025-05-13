# Implementation Plan: Multi-Agent Systems (MAS) for ADK-Ruby (Reviewed & Enhanced)

This plan details the steps to introduce multi-agent capabilities into the `adk-ruby` library, allowing for more complex and modular agent-based applications.

## Phase 1: Core Agent Hierarchy and State Management Enhancements

**Objective:** Establish foundational parent-child agent relationships and improve inter-agent communication via shared state.

### Step 1.1: Modify `ADK::Agent` for Hierarchy

*   **Task:** Add attributes and methods to `ADK::Agent` to support parent-child relationships.
*   **Files to Change:**
    *   `lib/adk/agent.rb`
    *   `spec/adk/agent_spec.rb` (for new/updated tests)
*   **Checklist & Changes:**
    *   [X] **Add `parent_agent` attribute:**
        *   In `ADK::Agent`: `attr_reader :parent_agent`
        *   Initialize `@parent_agent = nil` in `ADK::Agent#initialize`.
    *   [X] **Add `sub_agents` attribute:**
        *   In `ADK::Agent`: `attr_reader :sub_agents`
        *   Initialize `@sub_agents = []` in `ADK::Agent#initialize`.
    *   [X] **Update `ADK::Agent#initialize` for `sub_agents` (programmatic composition):**
        *   Add an optional keyword argument `sub_agents: []`.
        *   **Logic:**
            ```ruby
            # Inside ADK::Agent#initialize
            # (Assuming `definition` is nil or doesn't specify sub-agents for this path)
            # `provided_sub_agents_array` is the value from the new `sub_agents:` keyword arg.
            if provided_sub_agents_array.is_a?(Array)
              provided_sub_agents_array.each do |sub_agent_instance|
                unless sub_agent_instance.is_a?(ADK::Agent)
                  ADK.logger.warn("Skipping non-agent object in sub_agents: #{sub_agent_instance.inspect}")
                  next
                end
                if sub_agent_instance.parent_agent
                  raise ADK::ConfigurationError, "Agent '#{sub_agent_instance.name}' already has a parent ('#{sub_agent_instance.parent_agent.name}'). Cannot add as sub-agent to '#{self.name}'."
                end
                sub_agent_instance.instance_variable_set(:@parent_agent, self)
                @sub_agents << sub_agent_instance
              end
            end
            ```
    *   [X] **Implement `ADK::Agent#find_sub_agent(name_sym)`:**
        *   **Logic:**
            ```ruby
            # Inside ADK::Agent
            def find_sub_agent(name_sym)
              @sub_agents.find { |sa| sa.name == name_sym.to_sym } # Ensure comparison with symbol
            end
            ```
    *   [ ] **Implement `ADK::Agent#root_agent`:**
        *   **Logic:**
            ```ruby
            # Inside ADK::Agent
            def root_agent
              agent = self
              agent = agent.parent_agent while agent.parent_agent
              agent
            end
            ```
    *   [ ] **Implement `ADK::Agent#find_agent(name_sym)` (for searching from root):**
        *   **Logic (recursive DFS):**
            ```ruby
            # Inside ADK::Agent
            def find_agent(name_sym_to_find)
              # Start search from the root of the current agent's hierarchy
              root_agent.send(:_find_agent_recursive, name_sym_to_find.to_sym)
            end

            protected # Or private

            def _find_agent_recursive(name_sym_to_find)
              return self if self.name == name_sym_to_find
              @sub_agents.each do |sub_agent|
                found = sub_agent.send(:_find_agent_recursive, name_sym_to_find)
                return found if found
              end
              nil
            end
            ```
    *   [X] **Add Tests:** Unit tests for parent/child linking, single parent rule, `find_sub_agent`, `root_agent`, and `find_agent`.
        *   File: `spec/adk/agent_spec.rb`

### Step 1.2: `ADK::AgentDefinition` and `DefinitionProxy` for Hierarchy

*   **Task:** Allow agent definitions to specify sub-agent *names* for runtime instantiation.
*   **Files to Change:**
    *   `lib/adk/agent.rb` (for `ADK::AgentDefinition`, `DefinitionProxy`, and `ADK::Agent` modifications)
    *   `lib/adk/definition_store/redis_store.rb`
    *   `spec/adk/agent_definition_spec.rb` (New or updated, for definition changes)
    *   `spec/adk/agent_spec.rb` (for changes to agent instantiation)
    *   `spec/adk/definition_store/redis_store_spec.rb` (for store changes)
*   **Checklist & Changes:**
    *   [X] **Add `sub_agent_names` to `ADK::AgentDefinition`:**
        *   In `ADK::AgentDefinition`: `attr_reader :sub_agent_names`
        *   In `initialize`: `@sub_agent_names = []`
        *   In `to_h`: `sub_agent_names: @sub_agent_names.map(&:to_s)` (store as strings in hash for serialization)
    *   [X] **Add DSL method `sub_agents_define(*agent_names)` to `DefinitionProxy`:**
        *   **Logic:**
            ```ruby
            # Inside ADK::AgentDefinition::DefinitionProxy
            def sub_agents_define(*names)
              parsed_names = names.map do |item|
                raise ArgumentError, "Sub-agent definition names must be Symbols or Strings." unless item.is_a?(Symbol) || item.is_a?(String)
                item.to_sym
              end
              @definition.instance_variable_set(:@sub_agent_names, parsed_names.uniq)
            end
            ```
    *   [ ] **New `ADK::AgentDefinition.from_hash(definition_hash)` class method:**
        *   **Task:** Create this method to reliably convert a hash (e.g., from `RedisStore`) into a fully populated `ADK::AgentDefinition` object. **Note:** This method (and `ADK::AgentDefinition#to_h`) must be kept up-to-date to handle *all* attributes added in subsequent steps (e.g., `sequential_sub_agent_names`, `parallel_sub_agent_names`, loop attributes, `delegation_targets`, `agent_type`).
        *   **Logic:**
            ```ruby
            # Inside ADK::AgentDefinition (class level)
            def self.from_hash(hash_data)
              definition = new # Create a new blank definition
              proxy = DefinitionProxy.new(definition) # Get its proxy

              proxy.name(hash_data[:name].to_sym) if hash_data[:name]
              proxy.description(hash_data[:description] || '')
              proxy.instruction(hash_data[:instruction] || '')
              proxy.model_name(hash_data[:model_name].to_sym) if hash_data[:model_name]
              proxy.temperature(hash_data[:temperature].to_f) if hash_data[:temperature]
              (hash_data[:tool_names] || []).each { |tn| proxy.use_tool(tn.to_sym) }
              proxy.output_key(hash_data[:output_key].to_sym) if hash_data[:output_key] # Already planned, good to have here
              proxy.webhook_enabled(hash_data[:webhook_enabled]) if hash_data.key?(:webhook_enabled)
              proxy.webhook_validator(hash_data[:webhook_validator].to_sym) if hash_data[:webhook_validator] # Assuming stored as symbol string
              proxy.webhook_secret(hash_data[:webhook_secret]) if hash_data.key?(:webhook_secret)
              # Note: Procs for transformer/extractor cannot be deserialized from hash,
              # they must be re-associated if the definition object is loaded by name from GlobalDefinitionRegistry.
              proxy.fallback_mode(hash_data[:fallback_mode].to_sym) if hash_data[:fallback_mode]
              proxy.mcp_servers(*(JSON.parse(hash_data[:mcp_servers_json] || '[]'))) # Parse JSON
              
              # New MAS attributes
              proxy.sub_agents_define(*(hash_data[:sub_agent_names] || []).map(&:to_sym))
              # Add other workflow-specific attributes here as they are defined (e.g., sequential_sub_agent_names)
              # Ensure all new attributes from Phases 1-3 are handled here and in #to_h

              definition.validate! # Validate after populating
              definition
            rescue => e
              ADK.logger.error("Error creating AgentDefinition from hash: #{e.message}. Hash: #{hash_data.inspect}")
              nil
            end
            ```
    *   [X] **Update `ADK::Agent#initialize` when using `definition` hash (from store directly):**
        *   **Logic:**
            ```ruby
            # Inside ADK::Agent#initialize, if `definition` is a Hash (from RedisStore, deprecated path)
            # This path should ideally be removed or refactored to always expect an AgentDefinition object.
            # For now, ensure sub_agent_names is processed if it's a hash.
            elsif definition.is_a?(Hash) # If it's a hash from store
              @definition_hash_from_store = definition # Store the hash
              # ... existing hash processing ...
              sub_agent_names_from_hash = (definition[:sub_agent_names] || []).map(&:to_sym)
              if sub_agent_names_from_hash.any?
                sub_agent_names_from_hash.each do |sub_agent_name_sym|
                  # Load full AgentDefinition object for sub-agent
                  sub_definition_object = ADK::GlobalDefinitionRegistry.find(sub_agent_name_sym) ||
                                          ADK::AgentDefinition.from_hash(ADK.config.definition_store.get_definition(sub_agent_name_sym))

                  if sub_definition_object
                    sub_agent_instance = ADK::Agent.new(definition: sub_definition_object, session_service: @session_service)
                    sub_agent_instance.instance_variable_set(:@parent_agent, self) # Explicitly set parent
                    @sub_agents << sub_agent_instance
                  else
                    ADK.logger.warn("Could not find or load definition for sub-agent '#{sub_agent_name_sym}' declared in parent '#{self.name}'. Skipping.")
                  end
                end
              end
            end
            ```
        *   **Refinement:** `ADK::Agent#initialize` should consistently expect `definition` to be an `ADK::AgentDefinition` *object*. The loading logic (hash -> object) should happen *before* calling `ADK::Agent.new`.
            *   Caller (e.g., Web UI, CLI, Workflow Agent) is responsible for:
                1.  Fetching definition *hash* from `RedisStore`.
                2.  Converting hash to `ADK::AgentDefinition` *object* using `ADK::AgentDefinition.from_hash` or retrieving from `GlobalDefinitionRegistry`.
                3.  Passing the *object* to `ADK::Agent.new(definition: agent_def_object)`.
    *   [X] **Update `ADK::DefinitionStore::RedisStore`:**
        *   Add `sub_agent_names` (as JSON string of strings) to `AGENT_DEFINITION_FIELDS`.
        *   `save_definition`: store `sub_agent_names.map(&:to_s).to_json`.
        *   `get_definition`: parse `sub_agent_names` JSON into an array of strings (hash uses string keys/values). `from_hash` will convert to symbols.
        *   `update_definition`: handle `sub_agent_names`.
    *   [X] **Add Tests:** For DSL, definition persistence, `from_hash`, and agent instantiation with sub-agents from definition.
        *   Files: `spec/adk/agent_definition_spec.rb`, `spec/adk/agent_spec.rb`, `spec/adk/definition_store/redis_store_spec.rb`.

### Step 1.3: Enhance State Management (`output_key`)

*   **Task:** Allow agents to automatically save their final result to session state.
*   **Files to Change:**
    *   `lib/adk/agent.rb` (`ADK::Agent` and `ADK::AgentDefinition::DefinitionProxy`)
    *   `lib/adk/definition_store/redis_store.rb`
    *   `spec/adk/agent_definition_spec.rb` (for `output_key` DSL and persistence in definition)
    *   `spec/adk/agent_spec.rb` (for `run_task` behavior)
    *   `spec/adk/definition_store/redis_store_spec.rb` (for store changes)
*   **Checklist & Changes:**
    *   [X] **Add `output_key` to `ADK::AgentDefinition`:**
        *   Attribute, initialize, `to_h` (store as string).
    *   [X] **Add DSL method `output_key(key_name)` to `DefinitionProxy`:** Stores as symbol.
    *   [X] **Add `output_key` attribute to `ADK::Agent`:** Initialize from definition object or options.
    *   [X] **Modify `ADK::Agent#run_task`:**
        *   Logic to save result to session state using `session_for_output.set_state(@output_key, result_to_save)` is correct. The subsequent saving of the `final_agent_event` by the session service will persist the entire updated session.
    *   [X] **Update `ADK::DefinitionStore::RedisStore`:**
        *   Add `output_key` (as string) to `AGENT_DEFINITION_FIELDS`.
        *   Modify `save_definition` to store `output_key.to_s`.
        *   Modify `get_definition` to load `output_key` (as string, `from_hash` handles symbol conversion).
        *   Modify `update_definition` to handle `output_key`.
    *   [X] **Add Tests:** For `output_key` DSL, persistence, and `run_task` behavior.

### Step 1.4: Documentation Update

*   **Task:** Document new hierarchy and `output_key` features.
*   **Files to Change:**
    *   Relevant documentation files in `docs/` (e.g., `docs/core_concepts/agents.md`, `docs/guides/agent_definitions.md` - actual file names may vary)
*   **Checklist & Changes:**
    *   [X] Explain `parent_agent`, `sub_agents`, and `sub_agent_names` in agent definitions.
    *   [X] Document the single parent rule.
    *   [X] Document `find_sub_agent`, `root_agent`, `find_agent`.
    *   [X] Explain `output_key` and its usage for inter-agent communication via session state.
    *   [X] Emphasize shared `SessionService` for sub-agents in a workflow.

## Phase 2: Workflow Agent Implementation

**Objective:** Create specialized agent classes for orchestrating sub-agents.

### Step 2.0: Add `agent_type` to Definition (Pre-requisite for UI/Workflow)

*   **Task:** Add an attribute to distinguish standard LLM agents from workflow agents.
*   **Files to Change:**
    *   `lib/adk/agent.rb` (Definition, Proxy, `from_hash`, `to_h`)
    *   `lib/adk/definition_store/redis_store.rb`
    *   `spec/adk/agent_definition_spec.rb`
    *   `spec/adk/definition_store/redis_store_spec.rb`
*   **Checklist & Changes:**
    *   [ ] **Add `agent_type` attribute to `ADK::AgentDefinition`:**
        *   `attr_reader :agent_type`
        *   Initialize to `:llm` (default)
        *   Update `to_h` (store as string)
    *   [ ] **Add DSL `agent_type(type_symbol)` to `DefinitionProxy`:**
        *   Accepts symbols like `:llm`, `:sequential`, `:parallel`, `:loop`.
        *   Validates input against allowed types.
        *   Sets `@definition.instance_variable_set(:@agent_type, type_symbol)`
    *   [ ] **Update `ADK::AgentDefinition.from_hash`:**
        *   Load `agent_type` (convert string back to symbol, default to `:llm`).
    *   [ ] **Update `ADK::DefinitionStore::RedisStore`:**
        *   Add `agent_type` (as string) to `AGENT_DEFINITION_FIELDS`.
        *   Update save/get/update methods.
    *   [ ] **Add Tests:** For DSL, persistence, default value, validation.

### Step 2.1: Create New Directory `lib/adk/agents/`

*   **Task:** Create a new directory to house the workflow agent classes.
*   **Files to Create/Change:**
    *   `lib/adk/agents/` (New Directory)
    *   `lib/adk/agents.rb` (New File - manifest to require agents in this directory, optional but good practice)
    *   `lib/adk.rb` (To require `adk/agents` if the manifest file is created)
*   **Checklist & Changes:**
    *   [X] Create the directory.
    *   [ ] Add a `README.md` or manifest file if desired (e.g., `lib/adk/agents.rb` to require all agents in this directory). If `lib/adk/agents.rb` is created, `lib/adk.rb` will need to `require_relative 'adk/agents'`.

### Step 2.2: Implement `ADK::Agents::SequentialAgent`

*   **Task:** Create an agent that executes sub-agents in a defined sequence.
*   **Files to Change/Create:**
    *   `lib/adk/agents/sequential_agent.rb` (New File)
    *   `lib/adk/agent.rb` (Add DSL to `ADK::AgentDefinition::DefinitionProxy`, update `ADK::AgentDefinition.from_hash` and `ADK::AgentDefinition#to_h` for new attributes)
    *   `lib/adk/definition_store/redis_store.rb` (For new definition attributes)
    *   `lib/adk/agents.rb` (If created in 2.1, to `require_relative 'agents/sequential_agent'`)
    *   `spec/adk/agents/sequential_agent_spec.rb` (New File)
    *   `spec/adk/agent_definition_spec.rb` (For tests related to new attributes like `sequential_sub_agent_names`)
*   **Checklist & Changes:**
    *   [X] **Define `ADK::Agents::SequentialAgent < ADK::Agent`**.
    *   [X] **Add DSL `sequential_sub_agents(sequence_array)` to `DefinitionProxy`:**
        *   Stores `sequence_array` (e.g., `[:name1, :name2]`) in `ADK::AgentDefinition` as `@sequential_sub_agent_names` (array of symbols).
        *   (Ensure `ADK::AgentDefinition.from_hash` and `to_h` in `lib/adk/agent.rb` handle this new attribute).
    *   [X] **Update `ADK::DefinitionStore::RedisStore` for `sequential_sub_agent_names`** (store as JSON string of strings, load as array of strings; `from_hash` converts to symbols).
    *   [X] **`SequentialAgent#initialize`:**
        *   Call `super`.
        *   Load its own definition (which now includes `sequential_sub_agent_names`).
        *   Instantiate sub-agents based on these names (using `GlobalDefinitionRegistry.find` or `ADK::AgentDefinition.from_hash(store.get_definition(...))`, then `ADK::Agent.new(definition: sub_def_obj, session_service: @session_service)`). Store them in an ordered instance variable like `@ordered_sub_agents`.
        *   Set `self` as `parent_agent` for these instantiated sub-agents.
    *   [X] **Override `SequentialAgent#run_task(session_id:, user_input:, session_service:)`:**
        *   Loop through `@ordered_sub_agents`.
        *   Determine input for current sub-agent (initially `user_input`; subsequently, check session state for a key set by the previous agent's `output_key` if applicable. More complex input/output mapping is outside the scope of this initial plan).
        *   Call `sub_agent.run_task(...)` using the *same* `session_id` and `session_service`.
        *   Handle error/pending/escalate from sub-agent's returned event.
        *   Return the event from the last sub-agent or an aggregated/custom event.
    *   [X] **Add Tests:** For DSL, instantiation, sequential execution, state passing, error propagation.
        *   File: `spec/adk/agents/sequential_agent_spec.rb` (New File)

### Step 2.3: Implement `ADK::Agents::ParallelAgent`

*   **Task:** Create an agent that executes sub-agents concurrently.
*   **Files to Change/Create:**
    *   `lib/adk/agents/parallel_agent.rb` (New File)
    *   `lib/adk/agent.rb` (DSL, `ADK::AgentDefinition.from_hash`, `ADK::AgentDefinition#to_h`)
    *   `lib/adk/definition_store/redis_store.rb`
    *   `lib/adk/agents.rb` (If created, to require the new agent)
    *   `spec/adk/agents/parallel_agent_spec.rb` (New File)
    *   `spec/adk/agent_definition_spec.rb` (For tests related to `parallel_sub_agent_names`)
*   **Checklist & Changes:**
    *   [X] **Define `ADK::Agents::ParallelAgent < ADK::Agent`**.
    *   [X] **Add DSL `parallel_sub_agents(agent_names_array)` to `DefinitionProxy`:**
        *   Stores in `ADK::AgentDefinition` as `@parallel_sub_agent_names`.
        *   (Ensure `ADK::AgentDefinition.from_hash` and `to_h` in `lib/adk/agent.rb` handle this).
    *   [X] **Update `ADK::DefinitionStore::RedisStore` for `parallel_sub_agent_names`**.
    *   [X] **`ParallelAgent#initialize`:** Similar to `SequentialAgent`, instantiate sub-agents.
    *   [X] **Override `ParallelAgent#run_task(...)`:**
        *   Use `Concurrent::Promises.zip` or `Concurrent::Future.execute` for each sub-agent. (Ensure `concurrent-ruby` gem or chosen library is in `Gemfile`).
        *   Pass the same `session_id`, `session_service`, and initial `user_input` to all.
        *   Sub-agents **must** use distinct `output_key`s to avoid state overwrites.
        *   Wait for all to complete.
        *   Return an event summarizing completion, errors, or pending job IDs.
    *   [X] **Add Tests:** For concurrent execution, correct state key usage by sub-agents, result aggregation.
        *   File: `spec/adk/agents/parallel_agent_spec.rb` (New File)
    *   [ ] **Add Documentation:** Clearly document that users defining parallel workflows are responsible for ensuring sub-agents use distinct `output_key`s if they intend to save state, to avoid race conditions overwriting session data.

### Step 2.4: Implement `ADK::Agents::LoopAgent`

*   **Task:** Create an agent that executes sub-agents sequentially in a loop.
*   **Files to Change/Create:**
    *   `lib/adk/agents/loop_agent.rb` (New File)
    *   `lib/adk/agent.rb` (DSL, `ADK::AgentDefinition.from_hash`, `ADK::AgentDefinition#to_h`)
    *   `lib/adk/definition_store/redis_store.rb`
    *   `lib/adk/agents.rb` (If created, to require the new agent)
    *   `spec/adk/agents/loop_agent_spec.rb` (New File)
    *   `spec/adk/agent_definition_spec.rb` (For tests related to new loop attributes)
*   **Checklist & Changes:**
    *   [X] **Define `ADK::Agents::LoopAgent < ADK::Agent`**.
    *   [X] **Add DSL to `DefinitionProxy`:**
        *   `loop_sub_agents(sequence_array)` -> `@loop_sub_agent_names`
        *   `loop_max_iterations(count)` -> `@loop_max_iterations` (default, e.g., 10)
        *   `loop_condition_state_key(key_symbol)` -> `@loop_condition_state_key` (optional string/symbol)
        *   `loop_condition_expected_value(value)` -> `@loop_condition_expected_value` (optional, for state key check)
        *   (Ensure `ADK::AgentDefinition.from_hash` and `to_h` in `lib/adk/agent.rb` handle these new attributes).
    *   [X] **Update `ADK::DefinitionStore::RedisStore` for these attributes.**
    *   [X] **`LoopAgent#initialize`:** Load definition and sub-agents.
    *   [X] **Override `LoopAgent#run_task(...)`:**
        *   Loop, executing `loop_sub_agents` sequentially in each iteration.
        *   **Termination Logic:** After each full iteration:
            *   Increment iteration counter; break if `max_iterations` reached.
            *   Check if the last event from the sequence has `actions[:escalate] == true`; if so, break.
            *   If `loop_condition_state_key` is set, fetch its value from `session_service.get_session(...).get_state(@loop_condition_state_key)`. Compare with `@loop_condition_expected_value` (if set, otherwise check for truthiness). Break if condition met.
    *   [X] **Add Tests:** For looping, max iterations, event escalation, state-based termination.
        *   File: `spec/adk/agents/loop_agent_spec.rb` (New File)
    *   [X] **`ADK::Agent#execute_plan` Modification:** Handle `step[:type] == :agent_transfer`.
        *   **Logic:** Use `self.find_sub_agent(target_name)` (V1: direct sub-agent). Call `target_sub_agent.run_task(...)` with same `session_id` and `session_service`.
        *   *Note:* Using `find_sub_agent` restricts delegation to direct children only in this version. Future enhancements could consider `self.find_agent` for hierarchy-wide delegation if needed.
    *   [ ] **Planner `build_multi_step_gemini_prompt` update:**
        *   The prompt needs to be aware of `can_delegate_to` targets and their descriptions to suggest sensible transfers. This means the `tools_description` part of the prompt should also include descriptions of delegable sub-agents.

### Step 2.5: Modify `ADK::Event` for Escalation

*   **Task:** Add an `actions` field to `ADK::Event` to support escalation.
*   **Files to Change:**
    *   `lib/adk/event.rb`
    *   `spec/adk/event_spec.rb` (New or updated for testing `actions` field)
*   **Checklist & Changes:**
    *   [X] **Add `actions` attribute:** (Already in plan)
    *   [X] **Update `to_h` and `from_h`**. (Or equivalent serialization methods)
    *   [X] **Add Tests**.

## Phase 3: Advanced Interaction Mechanisms

**Objective:** Implement dynamic LLM-driven delegation and refine agent-as-tool invocation.

### Step 3.1: LLM-Driven Delegation (Agent Transfer)

*   **Task:** Enable planners to output "agent_transfer" steps and agents to handle them.
*   **Files to Change:**
    *   `lib/adk/planner.rb`
    *   `lib/adk/agent.rb` (both `ADK::Agent` for `execute_plan`, and `ADK::AgentDefinition::DefinitionProxy` for DSL, and `ADK::AgentDefinition.from_hash`/`to_h` for `@delegation_targets`)
    *   `lib/adk/definition_store/redis_store.rb` (for `@delegation_targets`)
    *   `spec/adk/planner_spec.rb` (For planner changes)
    *   `spec/adk/agent_spec.rb` (For `execute_plan` changes)
    *   `spec/adk/agent_definition_spec.rb` (For `delegation_targets` DSL and persistence)
*   **Checklist & Changes:**
    *   [X] **Planner Output:** Modify `ADK::Planner#plan` prompt.
    *   [X] **`ADK::AgentDefinition::DefinitionProxy` DSL:** `can_delegate_to(agent_name_array)` -> `@delegation_targets`. Persist.
        *   (Ensure `ADK::AgentDefinition.from_hash` and `to_h` in `lib/adk/agent.rb` handle this).
    *   [X] **`ADK::Agent#execute_plan` Modification:** Handle `step[:type] == :agent_transfer`.
        *   **Logic:** Use `self.find_sub_agent(target_name)` (V1: direct sub-agent). Call `target_sub_agent.run_task(...)` with same `session_id` and `session_service`.
    *   [ ] **Planner `build_multi_step_gemini_prompt` update:**
        *   The prompt needs to be aware of `can_delegate_to` targets and their descriptions to suggest sensible transfers. This means the `tools_description` part of the prompt should also include descriptions of delegable sub-agents.
    *   [X] **Add Tests.**

### Step 3.2: Review and Enhance `ADK::Tools::AgentTool`

*   **Task:** Make `ADK::Tools::AgentTool` more flexible for MAS, especially regarding session context.
*   **Files to Change:**
    *   `lib/adk/tools/agent_tool.rb`
    *   `lib/adk/agent.rb` (To ensure `ADK::Agent#initialize` accepts `session_service:`)
    *   `spec/adk/tools/agent_tool_spec.rb` (New or updated)
    *   `spec/adk/agent_spec.rb` (For testing `ADK::Agent#initialize` with `session_service:`)
*   **Checklist & Changes:**
    *   [X] **Implement `use_calling_session` parameter:**
        *   Add to `ADK::Tools::AgentTool`: `parameter :use_calling_session, type: :boolean, default: false, ...`
        *   In `perform_execution`:
            *   If true, pass `context.session_id` and `context.session_service` (or `agent.session_service` if context is from tool wrapper) to target agent's `run_task`.
            *   The target agent will be instantiated (from definition store) using the calling agent's session service if `use_calling_session` is true. This means `ADK::Agent.new` needs to accept `session_service:`
    *   [X] **Clarify `ADK::Agent.new` `session_service` parameter:**
        *   Ensure `ADK::Agent.new` can accept a `session_service:` keyword argument. If provided, it should use that instance. If not, it should fall back to `ADK.config.session_service`. This is crucial for `AgentTool` to correctly inject the session service. (Impacts `lib/adk/agent.rb`)
    *   [X] **State Passing:** If `use_calling_session` is true, state is naturally shared.
    *   [X] **Return Value:** Ensure it propagates correctly.
    *   [X] **Add Tests.**

## Phase 4: Documentation, Examples, and Testing

**Objective:** Provide comprehensive resources for users to understand and utilize the new MAS features.

*   **Files to Change/Create:**
    *   Various documentation files in `docs/` (New and updated)
    *   New example files in `examples/` directory (e.g., `examples/mas_workflow_example.rb`)
    *   New or updated spec files across `spec/` for comprehensive testing.
*   Identical to previous plan, looks good.
    *   [X] Create New Documentation
    *   [X] Update Existing Documentation
    *   [X] Create New Examples
    *   [X] Implement Comprehensive Tests

## Phase 5: Web UI Enhancements for MAS (New Phase)

**Objective:** Update the Web UI to support MAS features.

*   **Task:** Modify Sinatra app and views to display and manage agent hierarchies and workflow agent configurations.
*   **Files to Change:**
    *   `lib/adk/web/app.rb`
    *   `lib/adk/web/routes/*` (especially `AgentDefinitionRoutes`, `AgentInteractionRoutes` or equivalent files handling these concerns)
    *   `lib/adk/web/views/*` (e.g., `agents.slim`, `agent.slim`, new partials for workflow configs, agent creation/edit forms)
    *   Relevant spec files in `spec/adk/web/` or feature spec directory (New or updated for UI changes)
*   **Checklist & Changes:**
    *   [ ] **Agent List (`agents.slim`):** Indicate if an agent is a workflow type.
    *   [ ] **Agent Detail (`agent.slim`):**
        *   Display parent agent (if any).
        *   List sub-agents (names, link to their detail pages).
        *   If workflow agent, display its specific configuration (e.g., sequential steps, parallel tasks, loop settings).
        *   Allow editing of these workflow-specific configurations.
    *   [ ] **Agent Creation/Edit Form:**
        *   Add fields to select agent type (standard LLM, Sequential, Parallel, Loop) - *Requires `agent_type` attribute from Step 2.0*.
        *   Conditionally show configuration sections based on agent type (e.g., for `sub_agent_names`, `sequential_sub_agent_names`, `loop_max_iterations`).
        *   Allow selection/ordering of sub-agents.
    *   [ ] **Chat Interface:** Consider if/how interactions with workflow agents are represented or if chat is only for primary LLM agents.
    *   [ ] **Add Tests:** For new UI elements and interactions.

## General Considerations & Refinements:

1.  **Error Handling:**
    *   Ensure robust error handling for `ADK::ConfigurationError` (e.g., sub-agent definition not found during parent instantiation, single parent rule violation).
    *   Workflow agents need to gracefully handle failures in their sub-agents and propagate errors or make decisions based on them.
    *   *Files potentially affected:* `lib/adk/agent.rb`, new agent classes in `lib/adk/agents/`, potentially a custom error file like `lib/adk/errors.rb`.

2.  **`ADK.rb` Requires:**
    *   Ensure all new agent classes (e.g., `ADK::Agents::SequentialAgent`) are properly `require`d.
    *   *Files to Change:*
        *   `lib/adk.rb` (to `require_relative 'adk/agents'` if a manifest is used)
        *   `lib/adk/agents.rb` (New file - to `require_relative` individual agent files like `agents/sequential_agent`)
        *   Alternatively, `lib/adk.rb` could directly require each new agent class if `lib/adk/agents.rb` is not created.

3.  **Circular Dependency in Definitions:**
    *   The chosen path of instantiating sub-agents when the parent is instantiated (or when its `run_task` is first called, for workflow agents) can lead to stack overflows if definitions are circular (A defines B, B defines A).
    *   *Mitigation V1:* Add recursion depth detection during sub-agent instantiation. If a certain depth is exceeded or a specific agent name is re-encountered in the instantiation chain, raise an `ADK::ConfigurationError("Circular agent definition detected: ... -> #{agent_name} -> ...")`. (Logic likely in `lib/adk/agent.rb`).
    *   *Documentation:* Clearly document this limitation and the error.
    *   *Files to Change:* `lib/adk/agent.rb`.

4.  **Agent Naming and Uniqueness:**
    *   Agent instance names (e.g., `sequential_agent.name`) should still be unique if they are to be looked up globally or managed in a flat list of running instances (like the Web UI's `@agents` hash).
    *   The `ADK::AgentDefinitionStore` already enforces uniqueness for definition names. (No direct file changes anticipated beyond existing store logic).

5.  **Tool Scoping in `ToolContext` for Sub-Agents:**
    *   When a workflow agent calls a sub-agent, the `ToolContext` implicitly created within the sub-agent's `run_task` will use the sub-agent's *own* `ToolRegistry`. This is correct. The parent's tools are not automatically available unless the sub-agent's definition also includes them. (No direct file changes anticipated, confirms behavior).

This enhanced plan is more detailed and addresses some potential pitfalls.

