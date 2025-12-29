## 2025-12-17 - Refactoring Complex Initialization

**Issue:** `ADK.initialize_logger` had high Cyclomatic Complexity and ABC Size due to mixing environment variable parsing, logger configuration, and side effects (puts).
**Learning:** Initialization logic tends to grow organically and become a dump for configuration rules.
**Action:** Split into `determine_log_level_str`, `configure_log_settings`, and `announce_logger` to separate concerns and improve readability.

## 2025-12-17 - Data Normalization Extraction

**Issue:** `ADK::AgentDefinitionStore.register` had high complexity due to mixing validation, normalization, and storage logic in one method.
**Learning:** Extracting data normalization logic into a dedicated private helper method (`normalize_definition`) significantly improves readability and reduces the main method's complexity. This pattern separates "preparing the data" from "performing the action".
**Action:** Look for similar patterns where methods perform both data preparation/normalization and the core business logic, and extract the preparation steps.
