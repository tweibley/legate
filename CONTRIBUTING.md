# Contributing to Legate

Thanks for your interest in contributing to Legate!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/legate.git`
3. Install dependencies: `bundle install`
4. Run the tests: `bundle exec rspec`

## Development

```bash
bundle exec rspec              # Run tests (all must pass)
bundle exec rubocop            # Lint
bundle exec rubocop -a         # Auto-fix lint issues
bundle exec legate web start   # Start dev server on port 4567
```

## Submitting Changes

1. Create a feature branch from `main`
2. Write tests for your changes
3. Ensure all tests pass and RuboCop is clean
4. Submit a pull request with a clear description of the change

## Reporting Bugs

Open an issue on GitHub with:
- Steps to reproduce
- Expected vs actual behavior
- Ruby version and OS

## Code Style

This project uses RuboCop for code style. Run `bundle exec rubocop` before submitting.
