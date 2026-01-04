## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2024-02-18 - Missing Development Console

**Friction:** Developers must type `bundle exec irb -r ./lib/adk` to start an interactive console, which is verbose and hard to remember for newcomers expecting standard conventions.
**Learning:** `bin/console` is a standard Ruby/Rails convention that provides immediate access to the environment, reducing friction for exploration and debugging.
**Action:** Added `bin/console` script to standardize and simplify the interactive development workflow.
