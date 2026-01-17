## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-17 - Missing Contribution Guide

**Friction:** No clear entry point for new contributors explaining the process, style guide, or testing requirements.
**Learning:** Even with a good setup script, the lack of a CONTRIBUTING.md leaves developers guessing about standards and workflows.
**Action:** Created CONTRIBUTING.md to document the PR process, testing requirements, and helpful resources.
