## 2024-02-12 - Broken Setup Script

**Friction:** `bin/setup` failed immediately because `.env.example` was missing from the repository, but the script (and README) relied on it.
**Learning:** The file was likely ignored by a broad `.env*` pattern in `.gitignore` and never committed, causing the setup process to be broken for all new contributors.
**Action:** Created `.env.example` and explicitly whitelisted it in `.gitignore` to prevent regression.
