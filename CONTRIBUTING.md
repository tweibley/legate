# Contributing to ADK Ruby

Thank you for your interest in contributing to the Agent Development Kit (ADK) for Ruby! We welcome contributions from everyone.

## Getting Started

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally:
    ```bash
    git clone https://github.com/YOUR_USERNAME/adk-ruby.git
    cd adk-ruby
    ```
3.  **Run the setup script**:
    This script will install dependencies, create your `.env` file, and check prerequisites.
    ```bash
    bin/setup
    ```
4.  **Create a branch** for your work:
    ```bash
    git checkout -b my-feature-branch
    ```

## Development Environment

We use `mise` to manage Ruby versions, but standard `rbenv` or `rvm` should also work as long as you are using Ruby >= 3.0.0.

-   **Redis**: Required for session storage and background jobs. Ensure it's running (`redis-cli ping`).
-   **Environment Variables**: Check `.env` (created by `bin/setup`) for configuration.

## Development Workflow

### Running the Agent

You can use the CLI to interact with agents during development:

```bash
# List available agents
bundle exec adk agent list

# Run a specific agent
bundle exec adk agent execute my_agent "Hello world"
```

### Running the Web UI

To work on the web interface:

```bash
bundle exec adk web start
```

## Testing

We use RSpec for testing. Please ensure all tests pass before submitting a PR.

```bash
# Run all tests
bundle exec rspec

# Run a specific test file
bundle exec rspec spec/adk/agent_spec.rb
```

## Code Style

We use RuboCop to enforce code style.

```bash
# Check for offenses
bundle exec rubocop

# Auto-fix safe offenses
bundle exec rubocop -A
```

## Submitting a Pull Request

1.  Push your branch to GitHub.
2.  Open a Pull Request against the `main` branch.
3.  Fill out the PR template with details about your changes.
4.  Wait for CI checks to pass.

## Getting Help

If you have questions, please open an issue or check existing documentation in the `docs/` folder or `AGENTS.md`.
