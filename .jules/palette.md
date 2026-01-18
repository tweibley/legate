## 2025-10-26 - [CLI Typo Suggestions]

**Learning:** Users often make typos in CLI arguments (like `operashun` instead of `operation`). Providing a "did you mean?" suggestion significantly improves the experience by saving them a trip to the documentation.
**Action:** When validating a set of known keys/names in CLI commands, always use `DidYouMean::SpellChecker` to offer corrections for unknown inputs.
