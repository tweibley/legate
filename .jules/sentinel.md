## 2024-06-03 - Path Traversal Prevention in Documentation

**Vulnerability:** Path traversal risk in `ADK::Web::DocumentationRoutes` where `path_splat` was used to construct file paths. Although `render_markdown` had a check, `sane_path` construction in the route handler was manual and potentially brittle.
**Learning:** `Pathname#ascend` is a robust way to verify file containment within a directory, but it's better to rely on centralized helpers that enforce this check rather than ad-hoc sanitization in routes.
**Prevention:** Use `File.expand_path` and verify the resolved path starts with the expected root directory using `start_with?` or `Pathname` containment checks.
