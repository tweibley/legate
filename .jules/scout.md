## 2025-02-27 - Extracted Method for Parameter Injection

**Issue:** `ADK::Agent#execute_plan` contained complex nested logic for parameter injection, making it hard to read and test.
**Learning:** Breaking down complex logic into small, named private methods (`inject_previous_result`, `resolve_injected_value`, `extract_value_from_result`) significantly improves readability and isolation.
**Action:** Look for other long methods (like `#initialize`) that mix multiple concerns and extract them into helpers.
