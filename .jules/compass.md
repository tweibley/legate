## 2024-12-17 - Missing Setup Script

**Friction:** New developers had to manually install dependencies, create .env files, and check Redis status, leading to setup errors.
**Learning:** Manual steps are error-prone; a standardized `bin/setup` script is essential for consistent onboarding.
**Action:** Create `bin/setup` to automate dependency installation and environment checks.

## 2025-02-18 - Missing CONTRIBUTING.md

**Friction:** New contributors lack a clear entry point. `README.md` lists manual steps instead of the existing `bin/setup` script, and `AGENTS.md` is too technical for day-one onboarding.
**Learning:** `AGENTS.md` is great for architecture, but standard `CONTRIBUTING.md` is expected for quick starts.
**Action:** Add concise `CONTRIBUTING.md` pointing to `bin/setup` and core workflows.
