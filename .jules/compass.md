## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-18 - Missing CONTRIBUTING.md

**Friction:** New contributors see "Pull requests are welcome" but have no guide on how to contribute, run tests, or lint code.
**Learning:** A missing `CONTRIBUTING.md` creates uncertainty and slows down contributions. It's a critical entry point.
**Action:** Created `CONTRIBUTING.md` referencing the existing `bin/setup` and standard workflow.
