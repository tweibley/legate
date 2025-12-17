## 2025-10-18 - CLI Parameter Typo Suggestions

**Learning:** Users often mistype CLI parameters. The standard `did_you_mean` gem provides an easy, dependency-free way to offer suggestions.
**Action:** When validating keys in CLI commands or configuration hashes, use `DidYouMean::SpellChecker` to provide helpful "Did you mean?" hints for unknown keys.
