# Contributing to ADK Ruby

Thank you for your interest in contributing! 🎉

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/adk-ruby.git`
3. Run setup: `bin/setup`
4. Create a branch: `git checkout -b my-feature`

## Making Changes

### Code Style & Testing

We use RuboCop and RSpec. Please ensure your changes pass:

```bash
bundle exec rubocop           # Check style
bundle exec rspec             # Run tests
```

### Key Commands

- `bundle exec adk web start` - Start the web UI
- `bundle exec adk agent list` - List agents
- `bundle exec rake yard`     # Generate documentation

## Submitting a Pull Request

1. Push your branch: `git push origin my-feature`
2. Open a PR against `main`
3. Ensure the title follows conventional commits (e.g., `feat:`, `fix:`)

## Getting Help

- 📖 Read `AGENTS.md` for architectural overview
- 💬 Open an issue for questions
