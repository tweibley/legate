## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2024-05-24 - Missing CONTRIBUTING.md

**Friction:** New contributors have to guess the workflow for submitting changes (branch naming, commit style, testing requirements) because there is no dedicated guide.
**Learning:** The project has a comprehensive README and AGENTS.md, but lacks the standard human-centric entry point for contribution guidelines.
**Action:** Create a clear, concise CONTRIBUTING.md file that outlines the setup, testing, and submission process.
