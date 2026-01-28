## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-17 - Missing Contribution Guide

**Friction:** Contributing guidelines were missing, making it unclear how to run tests, lint code, or submit PRs.
**Learning:** Even with a good README, the specific workflows for contribution (style, testing) need a dedicated home to be discoverable.
**Action:** Added `CONTRIBUTING.md` with clear instructions for setup, style, testing, and PR submission.
