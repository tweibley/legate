## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-01-30 - Broken bin/setup due to missing .env.example

**Friction:** `bin/setup` failed because it attempted to copy `.env.example` which was missing from the repository.
**Learning:** Build artifacts or setup files can be lost or git-ignored incorrectly. Continuous verification of the "fresh clone" experience is vital.
**Action:** Re-created `.env.example` to ensure `bin/setup` works as intended.
