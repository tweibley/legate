# Contributing to ADK Ruby

Thank you for your interest in contributing to the Agent Development Kit (ADK) for Ruby! We welcome contributions from everyone.

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/adk-ruby.git
   cd adk-ruby
   ```
3. **Run the setup script**:
   ```bash
   bin/setup
   ```
   This script will install dependencies, create a `.env` file from the example, and check prerequisites like Ruby version and Redis.

4. **Create a branch** for your changes:
   ```bash
   git checkout -b my-new-feature
   ```

## Development Workflow

### Running Tests

We use RSpec for testing. Ensure all tests pass before submitting a pull request.

```bash
bundle exec rspec
```

You can also run a specific test file:
```bash
bundle exec rspec spec/adk/agent_spec.rb
```

### Code Style

We use RuboCop to enforce code style. Please check your code before committing.

```bash
bundle exec rubocop
```

To automatically fix safe issues:
```bash
bundle exec rubocop -a
```

### Running the Application

To start the web interface for development:

```bash
bundle exec adk web start
```

## Submitting a Pull Request

1. Push your branch to GitHub: `git push origin my-new-feature`.
2. Open a Pull Request against the `main` branch.
3. Provide a clear title and description of your changes.
4. Ensure CI passes (tests and linting).

## Questions?

If you have questions, please open an issue on GitHub.
