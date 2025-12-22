## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2024-05-23 - Decomposing Monolithic Loops in Agent Execution

**Issue:** `ADK::Agent#execute_plan` had excessive complexity (ABC 137, 120 lines) due to handling iteration, parameter injection, execution, and sanitization all in one loop.
**Learning:** Features like "parameter injection" and "result sanitization" were added inline, bloating the loop body and obscuring the high-level flow.
**Action:** Extracted the loop body into `_process_plan_step`, separating the "how a step is processed" from the "how the plan is orchestrated".
