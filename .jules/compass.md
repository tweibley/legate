## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-02-06 - Missing Contribution Guide

**Friction:** New contributors have no clear entry point or guidelines for contributing.
**Learning:** `README.md` mentions contributing but links to the repo, which creates a circular reference for "how to".
**Action:** Added `CONTRIBUTING.md` to standardize setup, testing, and PR workflow.
