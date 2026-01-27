# Contributing to ADK Ruby

Thank you for contributing! 🎉

## Quick Start

1. **Fork & Clone**: `git clone https://github.com/YOUR_USERNAME/adk-ruby.git`
2. **Setup**: Run `bin/setup` to install dependencies and configure environment.
3. **Branch**: `git checkout -b feat/my-feature`

## Development

- **Style**: We use RuboCop.
  ```bash
  bundle exec rubocop          # Check
  bundle exec rubocop -a       # Fix
  ```

- **Testing**: We use RSpec. All changes require tests.
  ```bash
  bundle exec rspec            # Run all
  ```

- **Docs**: Update YARD docs for public APIs.
  ```bash
  bundle exec rake yard
  ```

## Submitting Changes

1. Push your branch and open a PR against `main`.
2. Ensure CI passes (tests & linting).
3. Check `README.md` for architecture details.

Questions? Open an issue! 🚀
