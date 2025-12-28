## 2025-12-28 - Tool Parameter Suggestions

**Learning:** When validating user input (like tool parameters), error messages that simply state "missing parameter" are frustrating if the user made a simple typo. Integrating `did_you_mean` into validation logic provides immediate, actionable feedback.
**Action:** Used `DidYouMean::SpellChecker` to cross-reference provided keys against missing required keys in `ADK::Tool#validate_and_coerce_params`, enhancing the error message with "Did you mean?" suggestions.
