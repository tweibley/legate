## 2024-10-15 - [Setup Friction]

**Friction:** `bin/setup` fails immediately because it tries to copy `.env.example`, which is missing from the repository. Also, there is no `CONTRIBUTING.md` to guide new contributors.
**Learning:** The project relies on implicit knowledge or missing artifacts for setup. The `AGENTS.md` is great for agents but `CONTRIBUTING.md` is the standard entry point for humans.
**Action:** Create `.env.example` to unblock `bin/setup` and create a concise `CONTRIBUTING.md`.
