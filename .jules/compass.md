## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-01-01 - Broken Setup Script

**Friction:** `bin/setup` was failing because it referenced a missing `.env.example` file, blocking new contributors from easily setting up the environment.
**Learning:** Build artifacts or configuration examples that are ignored by git but required by scripts need to be carefully managed or forced into the repo.
**Action:** Restored `.env.example` and force-added it to git to ensure `bin/setup` works out of the box.
