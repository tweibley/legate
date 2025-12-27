## 2024-05-23 - Chatty Library Initialization

**Learning:** Libraries that print to `STDOUT` (e.g. `puts`) or log at `INFO` level during initialization degrade the CLI experience, especially for JSON output or piping.
**Action:** Demote initialization logs to `DEBUG`. Remove any `puts` calls in library code. Ensure CLI tools explicitly control log output formats, but the library itself should remain silent by default unless provoked.
