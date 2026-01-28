# Contributing to ADK Ruby

Thank you for your interest in contributing! We love to see new agents, tools, and improvements. 🎉

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/adk-ruby.git
   cd adk-ruby
   ```
3. **Run setup**:
   ```bash
   bin/setup
   ```
   This will install dependencies, create your `.env` file, and verify your environment.

4. **Create a branch** for your work:
   ```bash
   git checkout -b my-feature-branch
   ```

## Development Workflow

### Code Style

We use **RuboCop** to maintain code quality. Please ensure your code passes linting before submitting.

```bash
bundle exec rake rubocop          # Check style
bundle exec rubocop -a            # Auto-fix safe issues
```

### Testing

We use **RSpec** for testing. All changes must include tests.

```bash
bundle exec rake spec             # Run all tests
bundle exec rspec spec/path/to_file_spec.rb # Run specific test file
```

### Documentation

If you modify code, please update the documentation:

```bash
bundle exec rake yard             # Generate API documentation
```

## Submitting a Pull Request

1. **Verify your changes**: Run `bin/setup` or `bundle exec rake setup` to ensure everything is green.
2. **Commit your changes**:
   - Use clear, descriptive commit messages.
   - Example: `feat: Add new WeatherTool` or `fix: Handle timeout in Planner`.
3. **Push to your fork**: `git push origin my-feature-branch`.
4. **Open a Pull Request**: Submit your PR against the `main` branch.

## Getting Help

- Check `README.md` for core concepts and examples.
- Explore `examples/` directory for working code.
- If you're stuck, open an issue or ask in the PR!

Happy coding! 🧭
