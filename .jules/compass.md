## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-02-12 - Missing CONTRIBUTING.md

**Friction:** New contributors lack a clear guide on contribution workflow (tests, linting, PRs).
**Learning:** README focuses on usage; a dedicated `CONTRIBUTING.md` is standard for developer onboarding.
**Action:** Created `CONTRIBUTING.md` to standardize the contribution process.
