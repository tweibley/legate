## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Missing Contributing Guide

**Friction:** No central place for new contributors to learn about the contribution workflow (tests, linting, PRs), requiring them to search through README or guess.
**Learning:** While `README.md` covers development, a dedicated `CONTRIBUTING.md` is the standard entry point for contributors on GitHub and helps set expectations early.
**Action:** Created a concise `CONTRIBUTING.md` that points to existing scripts (`bin/setup`) and defines the PR process.
