# Contributing to ADK Ruby

## Quick Start
1. **Fork & Clone:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/adk-ruby.git
   cd adk-ruby
   ```
2. **Setup:**
   ```bash
   bin/setup # Installs deps, copies .env, checks Redis/Ruby
   ```
3. **Branch:** `git checkout -b my-feature`

## Development
*   **Style:** `bundle exec rubocop` (or `bundle exec rubocop -a` to fix)
*   **Tests:** `bundle exec rspec`
*   **Docs:** `bundle exec yard`
*   **All-in-one:** `bundle exec rake setup` runs spec, rubocop, and yard.

## Submitting Changes
1.  **Commit:** Use clear messages (e.g., `feat: Add tool`, `fix: Fix bug`).
2.  **Push:** `git push origin my-feature`
3.  **Pull Request:** Open against `main` and describe your changes.

## Resources
*   `README.md`: General overview.
*   `AGENTS.md`: Deep dive into architecture, tools, and patterns.
