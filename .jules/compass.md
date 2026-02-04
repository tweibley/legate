## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-05-02 - Fix and Promote Automated Setup

**Friction:** The `bin/setup` script failed because `.env.example` was missing, and `README.md` directed users to perform manual setup steps instead of using the script.
**Learning:** Users (and agents) expect `bin/setup` to work out of the box. Manual configuration steps in READMEs drift from reality and increase onboarding friction.
**Action:** Re-created `.env.example` to fix the script and updated `README.md` to make `bin/setup` the primary entry point.
