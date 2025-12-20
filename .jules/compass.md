## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-02-20 - Broken Setup Script (Missing .env.example)

**Friction:** `bin/setup` fails because `.env.example` is missing. It was ignored by git due to `.env*` pattern in `.gitignore`.
**Learning:** Overly broad gitignore patterns like `.env*` can accidentally exclude example configuration files which are essential for onboarding.
**Action:** Un-ignore `.env.example`, recreate it, and add `CONTRIBUTING.md`.
