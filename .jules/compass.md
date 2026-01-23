## 2025-05-27 - [Broken Setup Script]

**Friction:** `bin/setup` fails immediately on fresh clones because it attempts to copy `.env.example` to `.env`, but `.env.example` is missing from the repository.
**Learning:** The `.gitignore` file contains `.env*`, which unintentionally ignores `.env.example` along with `.env`. This prevents the example configuration from being committed.
**Action:** Create `.env.example` with documented environment variables and update `.gitignore` to explicitly whitelist it.
