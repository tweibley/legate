# Refactoring ADK Tool Metadata DSL Checklist

- [X] Create `docs/checklist.md` (This file)
- [X] Integrate DSL into `ADK::Tool`: Edit `lib/adk/tool.rb` to `include ADK::Tool::MetadataDsl`.
- [X] Fix Registration Trigger:
    - [X] Modify `ADK::Tool.inherited` hook in `lib/adk/tool.rb` to call `ADK::GlobalToolManager.register_tool(self)`.
    - [X] Remove `ADK::GlobalToolManager.register_tool(self)` call from `ADK::Tool.define_metadata`.
- [X] Add Deprecation Warning: Add warning to `ADK::Tool.define_metadata` guiding users to the new DSL methods (`tool_description`, `parameter`, etc.).
- [X] Refactor `ADK::Tool#initialize`: Update to use `self.class.tool_metadata` instead of individual class attributes (`@tool_name`, `@description`). Made lenient for missing metadata.
- [X] Run Specs: Execute RSpec tests (`bundle exec rspec`) after changes to `lib/adk/tool.rb`, `lib/adk/global_tool_manager.rb`, `lib/adk/agent.rb`, and related specs, ensuring they pass.
- [X] (Optional) Review/Refactor DSL method names (`tool_description` vs `description`) and variable scope based on implementation and testing. (Completed during debugging)
- [ ] (Optional) Update `docs/better-tools.md` to accurately reflect the final implementation details. 