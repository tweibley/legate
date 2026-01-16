# Contributing to ADK Ruby

Welcome! We love contributions. Here's how to get started.

## Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/tweibley/adk-ruby.git
    cd adk-ruby
    ```

2.  **Run Setup:**
    ```bash
    # Installs dependencies and creates .env
    bin/setup
    ```

3.  **Verify Setup:**
    ```bash
    # Runs the test suite
    bundle exec rspec
    ```

## Development

-   **Tests:** `bundle exec rspec`
-   **Linting:** `bundle exec rubocop`
-   **Docs:** `bundle exec yard`

## Making Changes

1.  Create a branch.
2.  Make your changes.
3.  Ensure tests and linting pass (`rake verify` runs both).
4.  Submit a Pull Request.

## Architecture

For a deep dive into the system architecture, Agent concepts, and Tool definitions, please read **[AGENTS.md](AGENTS.md)**.
