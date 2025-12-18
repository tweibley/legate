# Pull Request Review Process

Guidelines for reviewing PRs using the GitHub CLI.

## Prerequisites

- GitHub CLI installed and authenticated (`gh auth login`)
- Repository cloned locally
- Write access to the repository

## Step 1: List Open PRs

```bash
gh pr list --state open --json number,title,author,createdAt,headRefName,isDraft
```

Review PRs in chronological order (oldest first). Note `isDraft` status—draft PRs require marking ready before merge.

## Step 2: Review Each PR

```bash
gh pr view <PR_NUMBER> --json number,title,body,files,commits,state
```

### Evaluation Criteria

| Criterion | What to Check |
|-----------|---------------|
| **Scope** | Prefer focused changes (2–5 files) over sprawling ones (15+) |
| **CI Status** | All checks must pass |
| **Base Freshness** | Does diff show files as "new" that already exist in main? |
| **Conflicts** | Any merge conflicts? |
| **Duplication** | Does this duplicate another PR's changes? |

## Step 3: Check CI Status

```bash
gh pr checks <PR_NUMBER>
```

**Only merge PRs with passing CI.**

## Step 4: Review the Diff

```bash
gh pr diff <PR_NUMBER>
```

### What to Look For

- **Code Quality**: Clean implementation following project conventions
- **Tests**: New features/fixes should have test coverage
- **Stale Files**: If workflow/doc files show as "new file" but exist in main, the branch is stale

## Step 5: Handle Draft PRs

```bash
gh pr ready <PR_NUMBER>
```

## Step 6: Merge

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

## Step 7: Handle Problematic PRs

**Superseded PRs:**
```bash
gh pr close <PR_NUMBER> --comment "Superseded by PR #X"
```

**Stale PRs:**
```bash
gh pr close <PR_NUMBER> --comment "Stale base. Please rebase off main and resubmit."
```

## Step 8: Version Bump

After merging, pull and bump version:

```bash
git pull origin main
bundle exec rake release:minor  # or :patch or :major
```

## Decision Guidelines

1. **CI first** — Never merge failing PRs
2. **Focused changes** — Prefer 2–5 files over 15+
3. **Fresh base** — Close stale branches, request rebase
4. **No duplicates** — Close superseded PRs with explanation
5. **Oldest first** — Merge in chronological order to minimize conflicts

## Quality Gates

Before marking any task complete, verify:

- [ ] All tests pass
- [ ] Code coverage meets requirements
- [ ] Code follows project's code style guidelines
- [ ] All public functions/methods are documented (e.g., docstrings)
- [ ] No linting or static analysis errors (using the project's configured tools)
- [ ] Documentation updated if needed
- [ ] No security vulnerabilities introduced
- [ ] **Jules journal dates are correct** — The Jules bot hallucinates incorrect dates (e.g., 2024-05-21, 2025-02-18). Verify all dates in `.jules/*.md` files match when the task actually ran.

## Commit Guidelines

### Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, missing semicolons, etc. |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding missing tests |
| `chore` | Maintenance tasks |

### Examples

```bash
git commit -m "feat(auth): Add remember me functionality"
git commit -m "fix(posts): Correct excerpt generation for short posts"
git commit -m "test(comments): Add tests for emoji reaction limits"
git commit -m "style(mobile): Improve button touch targets"
```

## Quick Reference

```bash
gh pr list --state open --json number,title,isDraft
gh pr view <N> --json title,body,files
gh pr checks <N>
gh pr diff <N>
gh pr ready <N>
gh pr merge <N> --squash --delete-branch
gh pr close <N> --comment "reason"
```
