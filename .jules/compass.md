## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-01-25 - Missing .env.example blocked bin/setup

**Friction:** `bin/setup` failed because it tried to copy `.env.example`, which did not exist in the repository.
**Learning:** `.env.example` was likely ignored by `.gitignore` (which had `.env*`), preventing it from being committed despite previous efforts.
**Action:** Re-created `.env.example` and explicitly whitelisted it in `.gitignore` using `!.env.example`.
