## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Missing CONTRIBUTING.md

**Friction:** New contributors had no clear entry point or guidelines for contributing.
**Learning:** Even with a good README and AGENTS.md, the standard `CONTRIBUTING.md` file is expected by human contributors and GitHub's UI.
**Action:** Created `CONTRIBUTING.md` with setup instructions, code style guide, and PR process.
