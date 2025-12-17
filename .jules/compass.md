## 2025-12-17 - Automated Setup Script

**Friction:** New contributors had to manually create `.env` files and check for prerequisites like Redis, with instructions scattered across `README.md` and `AGENTS.md`.
**Learning:** Ruby projects often rely on `bin/setup` as a convention for onboarding (established by Rails). Missing this file adds friction and increases cognitive load for setup.
**Action:** Created `bin/setup` and `.env.example` to automate dependency installation, environment configuration, and prerequisite checking.
