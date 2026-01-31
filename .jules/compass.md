## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Broken Setup Script

**Friction:** `bin/setup` failed because `.env.example` was missing, likely ignored by git.
**Learning:** `.gitignore` wildcard rules like `.env*` can accidentally exclude critical example files.
**Action:** Created `.env.example` and whitelisted it in `.gitignore` to ensure `bin/setup` works out of the box.
