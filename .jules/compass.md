## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2026-01-14 - Missing Contributing Guide

**Friction:** No clear entry point for how to contribute, run tests, or use the console.
**Learning:** `CONTRIBUTING.md` is a standard community file that was missing, despite extensive internal docs in `AGENTS.md`.
**Action:** Added `CONTRIBUTING.md` with streamlined setup, testing, and console instructions.
