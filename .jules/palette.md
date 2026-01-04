## 2024-05-23 - Enhanced Tool Validation & Coercion

**Learning:** Developers (and LLMs) often pass tool parameters as strings (e.g., from CLI or JSON) even when the tool expects integers or booleans. Previously, this caused confusing type errors or silent failures deep in execution.
**Action:** Implemented `validate_and_coerce_params` in `ADK::Tool` to:
1. Provide rich error messages for missing parameters (listing what was missing AND what was provided).
2. Automatically coerce string inputs to the expected type (Integer, Float, Boolean, JSON Array/Hash) based on DSL definition.
3. Validate types strictly if coercion fails.
This improves CLI ergonomics (no need to manually parse strings in tools) and debugging speed.

## 2024-05-24 - CLI Spinner for Long-Running Tasks

**Learning:** When using `::CLI::UI::Spinner`, it writes to stdout/stderr and requires `::CLI::UI::StdoutRouter.enable` to be called first. However, if the command is intended to be pipeable (e.g., outputting code to stdout), we must strictly avoid initializing the UI components or printing anything other than the payload to stdout. Testing this requires capturing `Kernel#stdout` directly, as `Thor` commands may bypass the `Thor::Shell` abstraction for direct output.

**Action:** For future CLI commands that have dual modes (interactive vs. pipeable), explicitly check the mode early. If interactive, enable `CLI::UI` and use spinners. If pipeable, avoid all `CLI::UI` calls and use standard `puts` for the data payload. When testing, verify both the presence of UI elements (via mocks) in interactive mode and the purity of stdout in pipeable mode.
