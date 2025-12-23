# Contributing to ADK Ruby

## Getting Started

### Prerequisites

- [mise](https://mise.jdx.dev/) (recommended for Ruby version management)
- Redis

### Setup

1.  **Prepare environment:**
    ```bash
    mise install
    eval "$(mise activate bash --shims)"
    ```

2.  **Run setup script:**
    ```bash
    bin/setup
    ```
    This will install dependencies and create your `.env` file.

3.  **Verify installation:**
    ```bash
    bundle exec rspec
    ```

## Development

### Running Tests

Run the full test suite:
```bash
bundle exec rspec
```

### Code Style

We use RuboCop to enforce code style. Please check your changes before submitting:

```bash
bundle exec rubocop
```
