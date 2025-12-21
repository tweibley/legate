## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-21 - Broken Setup Dependencies

**Friction:** New contributors faced a broken `bin/setup` script because `.env.example` was missing and ignored by git, plus README instructions were outdated.
**Learning:** Automation scripts (`bin/setup`) are fragile if their dependencies (example files) aren't tracked; documentation must align with the automated path to ensure it's tested and working.
**Action:** Restored `.env.example`, fixed `.gitignore`, and updated README to prioritize `bin/setup`.
