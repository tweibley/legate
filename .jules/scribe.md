## 2024-05-23 - Docs Organization and Broken Links

**Gap:** `README.md` contained broken links to key documentation (Sidekiq, Webhooks) because the files were located in `docs/Completed/` instead of `docs/` or `docs/guides/`. The CLI documentation was also buried in `public/docs/cli/` without a link from the README.
**Learning:** Documentation files in `docs/Completed/` are likely "completed plans" that should be promoted to actual guides. Keeping them there breaks discoverability and links.
**Action:** Move "completed" documentation to `docs/guides/` or `docs/cli/` to establish a clear structure and update all references.
