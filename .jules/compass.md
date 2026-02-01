## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-02-19 - Broken Setup Script

**Friction:** `bin/setup` crashed immediately for new clones because it expected `.env.example` which was missing from the repository.
**Learning:** Build scripts must be tested against a fresh checkout to ensure all file dependencies (like sample configs) are actually committed.
**Action:** Added `.env.example` to ensure `bin/setup` works out of the box.
