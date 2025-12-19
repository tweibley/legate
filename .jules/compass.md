## 2025-12-17 - Missing Setup Script

**Friction:** New contributors have to manually install dependencies and create `.env` file based on prose in README.
**Learning:** `bin/setup` is a standard convention (Scripts to Rule Them All) that is missing here, leading to friction and potential configuration errors.
**Action:** Created `bin/setup` and `.env.example` to automate the initial environment configuration.

## 2025-12-17 - Missing .env.example Regression

**Friction:** `bin/setup` failed because `.env.example` was missing, despite a previous journal entry claiming it was created.
**Learning:** Files can go missing or be reverted. Setup scripts must be robust or the required files must be present. Also discovered `README.md` references `GEMINI_API_KEY` but code uses `GOOGLE_API_KEY`.
**Action:** Restored `.env.example` to fix the broken setup process and unblock new contributors.

**Correction:** The previous journal entry missed that `.env.example` was ignored by `.gitignore`. Unignored it.
