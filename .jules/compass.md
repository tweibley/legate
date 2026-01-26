## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-26 - Setup Script Friction

**Friction:** `bin/setup` failed because `.env.example` was missing, confusing new contributors.
**Learning:** Setup scripts must be self-contained or verify prerequisites clearly. Implicit dependencies on untracked files break the "fresh clone" experience.
**Action:** Created `.env.example` and added `CONTRIBUTING.md` to guide new developers.
