# Contributing to ADK Ruby

Thanks for your interest! 🧭

## Quick Start

1.  **Clone & Setup:**
    ```bash
    git clone https://github.com/YOUR_USERNAME/adk-ruby.git
    cd adk-ruby
    bin/setup
    ```
    This installs dependencies and checks prerequisites (Ruby 3.0+, Redis).

2.  **Make Changes:**
    -   Create a branch: `git checkout -b my-feature`
    -   Follow standard Ruby style.

## Verification

Before submitting a PR, ensure everything passes:

```bash
# Run tests
bundle exec rspec

# Check code style
bundle exec rubocop
```

## Submitting

-   Open a PR against `main`.
-   Use [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat: ...`, `fix: ...`).
-   See `README.md` and `AGENTS.md` for more context.

Happy coding!
