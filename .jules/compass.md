## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Missing CONTRIBUTING.md

**Friction:** New contributors lack a central guide for workflows, PR process, and code style expectations.
**Learning:** Even with a good README and setup script, the "how to contribute" process is implicit.
**Action:** Created `CONTRIBUTING.md` to document the contribution lifecycle.
