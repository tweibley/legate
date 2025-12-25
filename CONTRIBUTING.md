# Contributing to ADK Ruby

Thank you for your interest! 🎉

## Quick Start (2 minutes)

1. **Clone & Setup**:
   ```bash
   git clone <repository_url>
   cd adk-ruby
   bin/setup          # Installs dependencies & checks prerequisites
   ```

2. **Verify Environment**:
   ```bash
   bundle exec rspec  # Run tests
   ```

## Making Changes

### Code Style
We use RuboCop. Please fix offenses before submitting:
```bash
bundle exec rubocop -a
```

### Architecture
See [AGENTS.md](AGENTS.md) for a detailed technical overview.

## Submitting a Pull Request
1. Fork the repo and create a branch.
2. Add tests for your changes.
3. Ensure `bundle exec rspec` passes.
4. Open a PR with a clear description.
