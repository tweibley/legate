## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-21 - Missing Contribution Guidelines

**Friction:** New contributors lack a central guide for workflows, testing, and PR process, relying on scattered info in README and AGENTS.md.
**Learning:** `CONTRIBUTING.md` is the standard entry point for open source participation; its absence increases cognitive load for new developers.
**Action:** Created `CONTRIBUTING.md` to unify setup, testing, and style guide instructions.
