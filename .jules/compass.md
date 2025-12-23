## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-23 - Broken Setup Script

**Friction:** `bin/setup` crashed because `.env.example` was missing from the repository (ignored by `.env*` in `.gitignore`).
**Learning:** Generic ignore patterns like `.env*` can accidentally hide critical template files.
**Action:** Restored `.env.example` and whitelisted it in `.gitignore` with `!.env.example`. Added `CONTRIBUTING.md` to guide new users.
