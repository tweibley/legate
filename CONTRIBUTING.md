# Contributing to ADK Ruby

Thank you for your interest in contributing! 🧭

## Getting Started

1. **Fork & Clone** the repository.
2. **Setup Environment**:
   ```bash
   # If using mise (recommended)
   eval "$(mise activate bash --shims)"

   # Run the setup script
   bin/setup
   ```
   This will install dependencies and create your `.env` file.

## Development Workflow

- **Run Tests:** `bundle exec rspec`
- **Lint Code:** `bundle exec rubocop`
- **Console:** `bundle exec irb -r ./lib/adk`
- **Start Web UI:** `bundle exec adk web start`

## Making Changes

1. Create a descriptive branch (e.g., `feat/new-tool`, `fix/setup-script`).
2. Make your changes (keep them small and focused).
3. Ensure all tests pass and no linting errors are introduced.
4. Submit a Pull Request.

## Resources

- See `README.md` for project overview and architecture.
- See `AGENTS.md` for deep dive into internal concepts.

Happy coding!
