## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-19 - Missing Contributing Guide

**Friction:** No clear entry point for how to contribute, run tests, or lint code, forcing new contributors to guess or dig through the `README.md`.
**Learning:** A `CONTRIBUTING.md` file is a standard expectation for open source projects and serves as the definitive guide for contributor workflows.
**Action:** Created `CONTRIBUTING.md` to document the setup, testing, and contribution process.
