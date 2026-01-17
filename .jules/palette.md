## 2025-05-26 - Test Doubles and Helper Methods

**Learning:** When refactoring CLI commands to use helper methods that rely on external services (like `GlobalDefinitionRegistry`), test setup can become brittle if those helpers are not properly mocked or if the helpers rely on side effects that were previously handled inline.
In this case, `load_agent_definition_or_exit` calls `GlobalDefinitionRegistry.find`, which wasn't mocked in the `execute` command tests, causing the helper to fail and the command to exit early with "Agent definition not found", even though the tests were setting up `AgentDefinitionStore`.

**Action:** When extracting logic into helpers, ensure that all external dependencies accessed by that helper are identified and mocked in the corresponding tests. If a helper combines multiple checks (memory, redis), the test setup needs to account for the precedence logic in that helper.
