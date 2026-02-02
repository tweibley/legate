## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-02-02 - Missing CONTRIBUTING.md

**Friction:** No clear entry point for new contributors on how to setup, test, and submit changes, relying on scattered info in README.
**Learning:** Even with a `bin/setup`, the lack of a standard `CONTRIBUTING.md` creates uncertainty about workflows and expectations.
**Action:** Added `CONTRIBUTING.md` to centralize onboarding instructions and point to `AGENTS.md` for architecture.
