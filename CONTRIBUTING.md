# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/tweibley/adk-ruby.git`
3. Run setup: `bin/setup` (installs dependencies, checks prerequisites)
4. Create a branch: `git checkout -b my-feature`

## Making Changes

### Code Style & Testing

We use RuboCop for style and RSpec for testing:

```bash
bundle exec rubocop           # Check style
bundle exec rubocop -a        # Auto-fix safe issues
bundle exec rspec             # Run all tests
```

### Console

To explore the codebase interactively: `bundle exec irb -r ./lib/adk`

## Submitting a Pull Request

1. Push your branch: `git push origin my-feature`
2. Open a PR against `main`
3. Fill out the PR template
4. Wait for CI to pass
5. Address review feedback

## Getting Help

- 💬 Open an issue for questions
- 📖 Read `README.md` and `AGENTS.md` (for deep dives)
