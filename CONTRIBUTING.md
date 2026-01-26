# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/tweibley/adk-ruby.git`
3. Run setup: `bin/setup`
4. Create a branch: `git checkout -b my-feature`

## Making Changes

### Code Style

We use RuboCop for consistent code style:

```bash
bundle exec rubocop           # Check style
bundle exec rubocop -a        # Auto-fix safe issues
```

### Testing

All changes must include tests:

```bash
bundle exec rspec                        # Run all tests
bundle exec rspec spec/path/to_spec.rb   # Run specific file
bundle exec rspec -e "description"       # Run tests matching pattern
```

### Commit Messages

Use conventional commit messages:

- `feat: Add new feature`
- `fix: Fix bug in X`
- `docs: Update README`
- `test: Add tests for Y`
- `refactor: Simplify Z`

## Submitting a Pull Request

1. Push your branch: `git push origin my-feature`
2. Open a PR against `main`
3. Fill out the PR template
4. Wait for CI to pass
5. Address review feedback

## Getting Help

- 💬 Open an issue for questions
- 📖 Check existing issues before opening new ones
- 🏷️ Look for `good first issue` labels
