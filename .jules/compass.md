## 2025-05-18 - Broken Setup Script due to Missing Config

**Friction:** New contributors faced an immediate crash when running `bin/setup` because `.env.example` was missing, which the script attempts to copy to `.env`.
**Learning:** Automation scripts (like `bin/setup`) are brittle if they depend on files that are not committed or maintained. A missing configuration template blocks the entire onboarding process.
**Action:** Added `.env.example` with standard defaults and created `CONTRIBUTING.md` to guide users through the setup process.
