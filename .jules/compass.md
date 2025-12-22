## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2024-05-22 - Setup Broken by .gitignore

**Friction:** `bin/setup` failed because `.env.example` was missing. It turned out `.env*` in `.gitignore` was ignoring it, preventing it from being committed.
**Learning:** Broad ignore patterns like `.env*` can accidentally hide critical template files. Always whitelist exceptions like `!.env.example`.
**Action:** Restored `.env.example` and fixed `.gitignore`.
