# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

## Getting Started

1. **Fork** the repository and **clone** your fork.
2. Run the automated setup script to install dependencies and configure your environment:
   ```bash
   bin/setup
   ```
3. Create a feature branch: `git checkout -b my-feature`

## Making Changes

### Code Style & Testing

We use **RuboCop** for style and **RSpec** for testing. Please ensure all checks pass before submitting.

```bash
bundle exec rake rubocop       # Check code style
bundle exec rake spec          # Run all tests
bundle exec rake yard          # Generate documentation
```

### Commit Messages

Use conventional commit messages (e.g., `feat: Add new tool`, `fix: Resolve auth issue`).

## Submitting a Pull Request

1. Push your branch: `git push origin my-feature`
2. Open a PR against `main`.
3. Provide a clear description of the changes and the "why".

## Architecture & Resources

- **Architecture**: See `AGENTS.md` for a deep dive into the system design.
- **Journals**: Check `.jules/` for critical project learnings.
