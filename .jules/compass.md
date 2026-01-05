## 2024-05-23 - Missing Console Script

**Friction:** The `bin/console` script was missing, despite being referenced in `AGENTS.md` and being a standard Ruby convention. This forced manual `irb` loading which is error-prone.
**Learning:** Documentation can drift from reality if not automatically verified. `AGENTS.md` stated the script was "available" likely as an intent or outdated fact.
**Action:** Created `bin/console` to provide a reliable interactive environment for new contributors.
