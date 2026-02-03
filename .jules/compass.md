## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Missing Contributing Guide

**Friction:** No central entry point (`CONTRIBUTING.md`) exists to guide new contributors on workflows, testing, and style expectations.
**Learning:** Even with a good README, a dedicated CONTRIBUTING file is standard practice and signals a welcoming environment for collaboration.
**Action:** Created `CONTRIBUTING.md` to document setup, testing, and style guidelines.
