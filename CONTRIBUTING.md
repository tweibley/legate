# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

This guide will help you set up your development environment and submit your first pull request.

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/adk-ruby.git
   cd adk-ruby
   ```
3. **Setup environment:**
   We provide a script to automate dependency installation and environment checks.
   ```bash
   bin/setup
   ```
   *This script ensures Ruby 3.0+ is installed, checks for Redis, installs gems, and creates your `.env` file.*

4. **Verify the setup:**
   Run the tests to make sure everything is working correctly.
   ```bash
   bundle exec rspec
   ```

## Making Changes

### Code Style

We use [RuboCop](https://rubocop.org/) to enforce a consistent code style.

- **Check style:**
  ```bash
  bundle exec rubocop
  ```
- **Auto-fix safe issues:**
  ```bash
  bundle exec rubocop -a
  ```

### Testing

All changes must include tests. We use RSpec.

- **Run all tests:**
  ```bash
  bundle exec rspec
  ```
- **Run a specific test file:**
  ```bash
  bundle exec rspec spec/adk/agent_spec.rb
  ```

### Documentation

We use [YARD](https://yardoc.org/) for documentation.

- **Generate docs:**
  ```bash
  bundle exec rake yard
  ```

## Submitting a Pull Request

1. **Create a branch** for your feature or fix:
   ```bash
   git checkout -b feat/my-new-feature
   ```
   *Use conventional prefixes like `feat:`, `fix:`, `docs:`, `refactor:`.*

2. **Commit your changes:**
   ```bash
   git commit -m "feat: Add support for X"
   ```

3. **Push to your fork:**
   ```bash
   git push origin feat/my-new-feature
   ```

4. **Open a Pull Request** against the `main` branch.

## Getting Help

- 📖 Read the `README.md` for architectural overviews and usage examples.
- 💬 Open an issue if you encounter bugs or have feature requests.
