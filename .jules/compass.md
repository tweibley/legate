## 2025-01-22 - Broken Setup Script

**Friction:** The `bin/setup` script failed immediately because it tried to copy `.env.example`, which did not exist in the repository.
**Learning:** The setup script assumed the existence of a standard configuration template, but it had been deleted or never committed. This created a hard blocker for any new contributor trying to follow the "Quick Start" instructions.
**Action:** Created `.env.example` with documented configuration variables and updated `.gitignore` to ensure it remains tracked.
