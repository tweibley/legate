# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/adk-ruby.git
   cd adk-ruby
   ```
3. **Setup** the environment:
   ```bash
   bin/setup
   ```
4. **Create a branch** for your changes:
   ```bash
   git checkout -b my-feature-branch
   ```

## Making Changes

### Code Style
We use **RuboCop** to enforce code style.
```bash
bundle exec rubocop          # Check style
bundle exec rubocop -a       # Auto-fix safe issues
```

### Testing
Please include tests for your changes.
```bash
bundle exec rspec            # Run all tests
```
*Note: Ensure Redis is running for tests to pass.*

## Submitting a Pull Request

1. Push your branch to GitHub.
2. Open a Pull Request against the `main` branch.
3. Provide a clear title and description of your changes.
4. Ensure CI checks pass.

## Resources
- **Issues**: [Search existing issues](https://github.com/tweibley/adk-ruby/issues) before opening a new one.
- **Documentation**: See `README.md` and `docs/` for architecture details.
