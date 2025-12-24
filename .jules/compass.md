## 2025-12-24 - Fix Broken Setup

**Friction:** New contributors could not run `bin/setup` because it crashed due to a missing `.env.example` file.
**Learning:** The setup script assumed the existence of a file that was not present in the repository, likely due to `.gitignore` configuration or accidental deletion.
**Action:** Restored `.env.example` and ensured it is not ignored by git, allowing `bin/setup` to run successfully.
