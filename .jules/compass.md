## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-27 - Missing Contributing Guide

**Friction:** No central place for new contributors to learn how to contribute, run tests, or follow code style, relying on scattered info in README or assumptions.
**Learning:** `CONTRIBUTING.md` is a critical standard file that GitHub surfaces to potential contributors. Without it, the barrier to entry is higher.
**Action:** Created `CONTRIBUTING.md` consolidating setup, testing, and PR instructions.
