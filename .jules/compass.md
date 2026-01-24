## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2024-05-23 - Missing Contribution Guide & Broken Setup

**Friction:** No `CONTRIBUTING.md` meant the process for contributing was undocumented. Additionally, `bin/setup` failed because `.env.example` was missing from the repository.
**Learning:** Setup scripts rely on the presence of example configuration files. If these are deleted or ignored, the "happy path" for onboarding breaks immediately. Documentation for contributors is just as critical as documentation for users.
**Action:** Created `CONTRIBUTING.md` and restored `.env.example` to ensure `bin/setup` functions correctly.
