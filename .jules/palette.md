## 2024-05-22 - CLI "Did You Mean?" Suggestions

**Learning:** Ruby's bundled `did_you_mean` gem is excellent for providing helpful suggestions in CLI tools without adding external dependencies. Centralizing error handling in Thor commands (e.g., via a helper like `handle_agent_not_found`) allows for consistent application of such UX improvements across multiple commands.

**Action:** When implementing CLI lookups that can fail (e.g., finding resources by name), always consider implementing a suggestion mechanism using `DidYouMean::SpellChecker` and centralized error handling to catch typos early and guide the user.
