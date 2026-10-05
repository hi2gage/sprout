# Sprout — Implementation Specification

A language-agnostic specification for implementing Sprout, a CLI tool that creates git worktrees and launches an AI coding assistant (Claude Code) with contextual prompts from Jira tickets, GitHub issues, GitHub PRs, or raw text.

## 1. Purpose

Sprout automates the setup phase of working on a ticket:

1. Accept input (raw prompt, Jira ticket ID, GitHub issue/PR number, or URL)
2. Detect what kind of input it is
3. Fetch context from the appropriate source (Jira API, GitHub API, or use as-is)
4. Create a git worktree with an appropriate branch name
5. Write a prompt file containing the composed context
6. Execute a user-defined shell script to launch Claude Code in the new worktree

Once launched, Sprout exits. It is a launcher, not a daemon.

---

## 2. CLI Interface

### 2.1 Commands

```
sprout launch <input>    # Create worktree + launch (default subcommand)
sprout list              # List existing worktrees
sprout prune [branch]    # Remove worktrees and their branches
```

`launch` is the default subcommand, so `sprout <input>` is equivalent to `sprout launch <input>`.

### 2.2 Launch Options

| Option | Short | Type | Description |
|--------|-------|------|-------------|
| `<input>` | | positional, required | The input to process |
| `--jira <id>` | `-j` | string | Force Jira source with this ticket ID |
| `--github <num>` | `-g` | string | Force GitHub issue source |
| `--pr <num>` | | string | Force GitHub PR source |
| `--prompt <text>` | `-p` | string | Force raw prompt source |
| `--branch <name>` | `-b` | string | Override computed branch name |
| `--type <type>` | `-t` | string | Branch type prefix (e.g., feature, bugfix, hotfix, chore). Defaults to `"feature"` |
| `--config <path>` | `-c` | string | Use alternate config file path |
| `--dry-run` | `-n` | flag | Print what would happen, don't execute |
| `--verbose` | `-v` | flag | Print detailed output |

### 2.3 List Options

| Option | Type | Description |
|--------|------|-------------|
| `--branches-only` | flag | Output only branch names (for piping to other commands) |
| `--include-main` | flag | Include the main repository worktree in output |

### 2.4 Prune Options

| Option | Short | Type | Description |
|--------|-------|------|-------------|
| `[branch]` | | positional, optional | Branch name or substring to match |
| `--force` | `-f` | flag | Delete without interactive confirmation |
| `--dry-run` | `-n` | flag | Show what would be deleted |
| `--stdin` | | flag | Read branch names from stdin (one per line) |
| `--verbose` | `-v` | flag | Print verbose output |

### 2.5 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Configuration error (missing file, invalid TOML, missing required fields) |
| 2 | Source error (auth failed, ticket not found, network error, repo mismatch) |
| 3 | Git error (not in repo, worktree creation failed) |
| 4 | Script execution error (non-zero exit from launch script) |

---

## 3. Configuration

### 3.1 File Location

Default: `~/.sprout/config.toml`

Override with `--config <path>`.

### 3.2 Format

TOML. The file MUST exist (no implicit defaults for the whole file), and MUST contain at least a `[launch]` section with a `script` field.

### 3.3 Schema

```toml
# REQUIRED
[launch]
script = "..."           # Shell script to execute after worktree setup
pr_script = "..."        # Optional: separate script for PR launches (defaults to script)

# OPTIONAL
[worktree]
path_template = "../worktrees/{branch}"   # Where to create worktrees
branch_template = "{ticket_id}"           # How to name branches
default_branch_type = "feature"           # Default for {branch_type} when --type not provided

[prompt]
prefix = "..."           # Text prepended to the prompt
template = "# {title}\n\n{description}"   # Body template
suffix = "..."           # Text appended to the prompt

[sources.jira]
base_url = "https://company.atlassian.net"
email = "user@company.com"
token = "..."            # Optional — prefer JIRA_TOKEN env var
default_project = "IOS"  # Optional
fields = ["summary", "description"]  # Optional

[sources.github]
repo = "owner/repo"      # Optional — auto-detected from git remote
token = "..."             # Optional — prefer gh CLI or GITHUB_TOKEN env var

[detection]
jira_pattern = "[A-Z]+-[0-9]+"           # Optional — regex for Jira ticket IDs
github_patterns = ["#[0-9]+", "gh:[0-9]+"]  # Optional — patterns for GitHub refs

[variables]
user = "gage"            # Arbitrary key-value pairs for interpolation
team = "ios"
```

### 3.4 Defaults

When optional sections or fields are missing:

| Field | Default |
|-------|---------|
| `worktree.path_template` | `"../worktrees/{branch}"` |
| `worktree.branch_template` | `"{ticket_id}"` |
| `worktree.default_branch_type` | `"feature"` |
| `prompt.template` | `"# {title}\n\n{description}"` |
| `launch.pr_script` | Same as `launch.script` |
| `sources.jira.fields` | `["summary", "description"]` |
| `detection.jira_pattern` | `"[A-Z]+-[0-9]+"` |
| `detection.github_patterns` | `["#[0-9]+", "gh:[0-9]+"]` |

---

## 4. Input Detection

When no explicit source flag is provided (`--jira`, `--github`, `--pr`, `--prompt`), the input is classified using these rules in order:

### 4.1 Detection Order

1. **Jira URL** — Contains `atlassian.net/browse/` followed by a Jira ticket pattern
   - Example: `https://acme.atlassian.net/browse/IOS-1234`
   - Extract: ticket ID `IOS-1234`
   - Result: Jira source

2. **GitHub PR URL** — Contains `github.com/{owner}/{repo}/pull/{number}`
   - Example: `https://github.com/org/repo/pull/567`
   - Extract: PR number `567`, repo `org/repo`
   - Result: GitHub PR source

3. **GitHub Issue URL** — Contains `github.com/{owner}/{repo}/issues/{number}`
   - Example: `https://github.com/org/repo/issues/123`
   - Extract: issue number `123`, repo `org/repo`
   - Result: GitHub issue source

4. **Jira ticket pattern** — Entire input matches `^[A-Z]+-[0-9]+$`
   - Example: `IOS-1234`
   - Result: Jira source

5. **GitHub PR shorthand** — Entire input matches `^(?i)pr:\d+$`
   - Example: `pr:77`
   - Extract: number `77`
   - Result: GitHub PR source

6. **GitHub issue shorthand** — Entire input matches `^#\d+$` or `^(?i)gh:\d+$`
   - Examples: `#567`, `gh:99`
   - Extract: number from pattern
   - Result: GitHub issue source

7. **Raw prompt** — Anything else
   - The entire input string is used as the prompt text
   - Result: Raw prompt source

### 4.2 Explicit Flags

Explicit source flags (`--jira`, `--github`, `--pr`, `--prompt`) bypass auto-detection entirely. They only apply to single-input mode (not batch).

### 4.3 Batch Mode

If the input contains commas, it is split into multiple inputs. Each is processed independently through the full pipeline (detect, fetch, create worktree, launch). A 1.5-second delay is inserted between launches to prevent terminal window collisions.

---

## 5. Context Fetching

### 5.1 Jira

**Authentication:**
1. Token: `JIRA_TOKEN` env var → `JIRA_API_TOKEN` env var → `config.sources.jira.token`
2. Email: `JIRA_EMAIL` env var → `JIRA_USER` env var → `config.sources.jira.email`
3. Base URL: `JIRA_BASE_URL` env var → `config.sources.jira.base_url`

**API call:**
- `GET {base_url}/rest/api/3/issue/{ticket_id}`
- Header: `Accept: application/json`
- Header: `Authorization: Basic base64({email}:{token})`

**Response parsing:**
- `key` → ticket ID
- `fields.summary` → title
- `fields.description` → ADF (Atlassian Document Format); extract plain text by recursively joining `content[].content[].text` nodes
- `fields.creator.displayName` → author
- `fields.labels` → labels array

**Error mapping:**
- 401 → auth failed
- 404 → ticket not found
- Other non-200 → network error

### 5.2 GitHub Issues

**Authentication (in priority order):**
1. Run `gh auth token` (uses GitHub CLI's stored credentials)
2. `GITHUB_TOKEN` env var

**Repo resolution (in priority order):**
1. If input was a URL, use the `owner/repo` from the URL. Validate it matches the current git remote (case-insensitive). Throw `repoMismatch` if different.
2. `config.sources.github.repo`
3. Parse `git remote get-url origin` (supports both SSH `git@github.com:owner/repo.git` and HTTPS `https://github.com/owner/repo.git` formats)

**API call:**
- `GET https://api.github.com/repos/{owner}/{repo}/issues/{number}`
- Header: `Accept: application/vnd.github+json`
- Header: `Authorization: Bearer {token}`
- Header: `X-GitHub-Api-Version: 2022-11-28`

**Response parsing:**
- `number` → ticket ID (as string)
- `title` → title
- `body` → description
- `html_url` → url
- `user.login` → author
- `labels[].name` → labels array
- slug is computed from title

### 5.3 GitHub PRs

Same authentication and repo resolution as GitHub Issues.

**API call:**
- `GET https://api.github.com/repos/{owner}/{repo}/pulls/{number}`
- Same headers as issues

**Response parsing:**
Same as issues, plus:
- `head.ref` → source branch (stored as `sourceBranch` on the context)
- ticket ID is prefixed with `pr-` (e.g., `pr-123`)

The presence of `sourceBranch` triggers PR-specific behavior in worktree creation and script selection.

### 5.4 Raw Prompt

No API call. The input text becomes both the title and description. A ticket ID is generated as `prompt-{hash}` where `{hash}` is derived from the slugified prompt text (first 8 digits of the hash magnitude).

---

## 6. Variable System

### 6.1 Built-in Variables

These are always available for interpolation:

| Variable | Source | Example |
|----------|--------|---------|
| `{ticket_id}` | From context | `IOS-1234`, `567`, `prompt-12345678` |
| `{branch}` | Computed from template | `IOS-1234`, `gage/IOS-1234` |
| `{branch_type}` | `--type` flag or config default | `feature`, `bugfix`, `hotfix` |
| `{worktree}` | Computed absolute path | `/Users/gage/Dev/worktrees/IOS-1234` |
| `{repo_root}` | `git rev-parse --show-toplevel` | `/Users/gage/Dev/my-app` |
| `{repo_name}` | Last path component of repo root | `my-app` |
| `{timestamp}` | Unix epoch seconds | `1704067200` |
| `{date}` | ISO 8601 date | `2025-01-01` |
| `{worktree_created}` | Whether worktree was new | `true` or `false` |

### 6.2 Context Variables (from ticket sources)

Only present when the source provides them:

| Variable | Source |
|----------|--------|
| `{title}` | Ticket title/summary |
| `{description}` | Full description body |
| `{slug}` | Slugified title |
| `{url}` | Link back to the ticket |
| `{author}` | Ticket creator |
| `{labels}` | Comma-separated labels |

### 6.3 Special Variables (non-PR only)

| Variable | Description |
|----------|-------------|
| `{prompt}` | Escaped prompt content (for inline use in scripts) |
| `{prompt_file}` | Path to the written prompt file (only set if script uses `{prompt_file}`) |

### 6.4 Custom Variables

Any key-value pairs under `[variables]` in the config are merged into the variable dictionary. They are added last and can reference any key name.

### 6.5 Interpolation

Simple `{key}` replacement. For each key in the variable dictionary, replace all occurrences of `{key}` in the template with the value. Unknown `{tokens}` are left as-is (not an error).

---

## 7. Branch Name Computation

Priority order:

1. **Explicit `--branch` flag** — used as-is
2. **PR source branch** — if the context has a `sourceBranch` (from a GitHub PR), use it directly
3. **Branch template** — interpolate `worktree.branch_template` (default: `{ticket_id}`) with available variables (`ticket_id`, `slug`, `user`, `branch_type`, and any custom variables)

The `{branch_type}` variable is resolved as: explicit `--type` flag → `worktree.default_branch_type` config → `"feature"`.

---

## 8. Worktree Path Computation

1. Interpolate `worktree.path_template` (default: `../worktrees/{branch}`) using `{branch}` (with `/`, `\`, `:` replaced by `_` to prevent subdirectory creation) and `{repo_name}`
2. If the result is a relative path, resolve it relative to the repo root
3. The final value is an absolute path

---

## 9. Worktree Creation

### 9.1 Flow

```
Prune stale worktree references (git worktree prune)
         │
         ▼
Does a worktree already exist at the computed path?
    ├── YES → Skip creation, mark worktree_created = false
    │         (worktree already existed = true, so "created" = false)
    └── NO ──┐
             ▼
    Create parent directory if needed
             │
             ▼
    Is this a PR (has sourceBranch)?
    ├── YES → Fetch branch from remote, then create worktree from existing branch
    └── NO ──┐
             ▼
    Does the branch exist locally or remotely?
    ├── YES → Create worktree from existing branch
    └── NO  → Create worktree with new branch (git worktree add <path> -b <branch>)
```

### 9.2 Conflict Recovery

When creating a worktree from an existing branch, git may fail with "branch is already used by worktree at '/path'". Recovery:

1. Parse the conflicting worktree path from the error message (regex: `is already used by worktree at '([^']+)'`)
2. Check if the conflicting path exists on disk
3. If it does NOT exist: the reference is stale. Run `git worktree prune`, re-fetch if PR, then retry creation
4. If it DOES exist: the branch is genuinely checked out elsewhere. Force-create with `git worktree add --force <path> <branch>`

### 9.3 Git Commands Used

| Operation | Command |
|-----------|---------|
| Get repo root | `git rev-parse --show-toplevel` |
| Create worktree (new branch) | `git worktree add <path> -b <branch>` |
| Create worktree (existing branch) | `git worktree add <path> <branch>` |
| Create worktree (force) | `git worktree add --force <path> <branch>` |
| List worktrees | `git worktree list --porcelain` |
| Remove worktree | `git worktree remove <path> --force` |
| Prune stale refs | `git worktree prune` |
| Fetch branch | `git fetch origin <branch>:<branch>` (fallback: `git fetch origin <branch>`) |
| Check local branch | `git show-ref --verify --quiet refs/heads/<branch>` |
| Check remote branch | `git ls-remote --heads origin <branch>` |
| Delete branch | `git branch -D <branch>` |
| Get remote URL | `git remote get-url origin` |

---

## 10. Prompt Composition

### 10.1 Structure

The prompt is assembled from three optional parts:

```
{prefix}          ← config.prompt.prefix (interpolated)

{body}            ← config.prompt.template (interpolated, default: "# {title}\n\n{description}")

{suffix}          ← config.prompt.suffix (interpolated)
```

Parts are joined with double newlines (`\n\n`). Each part is trimmed of leading/trailing whitespace before joining.

### 10.2 Prompt File

Written to `~/.sprout/prompts/{sanitized_branch}.md` where the branch name has `/`, `\`, `:` replaced with `_`.

The prompt file is only written if the launch script contains `{prompt_file}`. This avoids unnecessary file creation when the user inlines the prompt differently.

### 10.3 Inline Prompt Variable

The composed prompt content is also available as `{prompt}`, escaped for shell/AppleScript use:
- `\` → `\\`
- `"` → `\"`
- `'` → `'\''`
- newlines → `\n`

This variable is only set for non-PR sources (PRs use `pr_script` which typically doesn't need a prompt).

---

## 11. Script Execution

### 11.1 PR vs Non-PR

- **Non-PR sources**: use `config.launch.script`
- **PR sources**: use `config.launch.pr_script` (falls back to `config.launch.script`)

### 11.2 Execution

1. Interpolate all variables into the selected script
2. Execute via `/bin/sh -c <script>`
3. Capture stdout and stderr
4. Print stdout to the user
5. Print stderr to stderr
6. If exit code is non-zero, throw a script execution error (exit code 4)

---

## 12. Hooks

### 12.1 Location

Hooks live in the repository at `.sprout/hooks/`. They are shell scripts that must be executable (`chmod +x`).

### 12.2 Available Hooks

| Hook | When it runs |
|------|-------------|
| `post-launch` | After worktree is created/verified, before script execution |
| `post-prune` | After each worktree+branch is removed |
| `pre-prune` | (Defined but not currently invoked) |

### 12.3 Environment Variables

Hooks receive these environment variables (in addition to the inherited process environment):

| Variable | Description |
|----------|-------------|
| `SPROUT_WORKTREE_PATH` | Absolute path to the worktree |
| `SPROUT_BRANCH` | Branch name |
| `SPROUT_REPO_ROOT` | Repository root directory |

### 12.4 Behavior

- If the hook file doesn't exist: silently skip (return false)
- If the hook exists but isn't executable: print a warning with `chmod` instructions, skip
- If the hook exits non-zero: throw a hook error. For `post-launch`, this is caught and printed as a warning (non-fatal). For `post-prune`, same.
- Hook stdout is printed to the user; stderr goes to stderr
- The hook's working directory is set to the repo root

### 12.5 Finding the Repo Root for Hooks

For worktrees, the repo root is found by:
1. Read the `.git` file in the worktree (it's a file, not a directory, containing `gitdir: /path/to/main/.git/worktrees/branchname`)
2. Parse the path and strip everything from `/.git/worktrees/` onward

---

## 13. List Command

1. Run `git worktree list --porcelain`
2. Parse output: each worktree block starts with `worktree <path>` and has `branch refs/heads/<name>`
3. By default, exclude the main worktree (detected by path containing "worktrees" — see note below)
4. With `--include-main`, include all worktrees
5. Output format: `{branch}\t{path}` per line, or just `{branch}` with `--branches-only`

---

## 14. Prune Command

### 14.1 Modes

- **No arguments**: list all worktrees and print usage
- **Branch argument**: filter worktrees where branch contains the argument string
- **`--stdin`**: read branch names from stdin (exact match)
- **`--dry-run` with no branch**: show all worktrees that would be affected

### 14.2 Flow

1. List all worktrees
2. Filter to targets (by branch argument, stdin, or all for dry-run)
3. If not `--force` and not `--dry-run`: prompt for confirmation (`y/N`)
4. For each target:
   a. Remove worktree: `git worktree remove <path> --force`
   b. Delete branch: `git branch -D <branch>`
   c. Run `post-prune` hook if it exists
5. Run `git worktree prune` to clean up stale references

---

## 15. Slugify Algorithm

Convert a string to a URL-safe slug:

1. Lowercase the input
2. Replace spaces and underscores with hyphens
3. Remove all characters that are not alphanumeric or hyphens
4. Collapse consecutive hyphens into a single hyphen
5. Trim leading and trailing hyphens
6. Truncate to 50 characters maximum
7. If truncation leaves a trailing hyphen, trim it

Examples:
- `"Fix Login_Button NOW!!!"` → `"fix-login-button-now"`
- `"Add --verbose flag"` → `"add-verbose-flag"`

---

## 16. Error Handling

### 16.1 Error Categories

| Category | Exit Code | Examples |
|----------|-----------|---------|
| Config | 1 | File not found, read failed, parse failed |
| Source | 2 | Auth failed, ticket not found, network error, repo mismatch |
| Git | 3 | Not in repo, worktree creation failed, command failed |
| Script | 4 | Non-zero exit code from launch script |
| Hook | (non-fatal) | Printed as warnings, don't affect exit code |

### 16.2 Error Output

All error messages are written to stderr, prefixed with "Error: ".

---

## 17. Execution Flow Summary

```
1. Load config from ~/.sprout/config.toml (or --config path)
2. Check for batch mode (comma-separated inputs)
   └── If batch: split and process each independently with 1.5s delay
3. Detect input source (or use explicit flag)
4. Fetch context from source (Jira API / GitHub API / raw prompt)
5. Build variable dictionary:
   a. Get repo root from git
   b. Compute branch name (flag → PR source branch → template)
   c. Compute worktree path (template → resolve to absolute)
   d. Add timestamps, ticket fields, custom variables
6. Ensure worktree exists:
   a. Prune stale refs
   b. Check if worktree exists at path → skip if yes
   c. Create parent directory
   d. Create worktree (with conflict recovery)
7. Run post-launch hook (if exists)
8. Select launch script (pr_script for PRs, script otherwise)
9. Compose prompt content (non-PR only):
   a. Build from prefix + template + suffix
   b. Write prompt file if script uses {prompt_file}
   c. Set {prompt} variable with escaped content
10. Interpolate all variables into launch script
11. Execute script via /bin/sh -c
12. Exit 0
```

---

## 18. Dependencies

| Dependency | Purpose |
|------------|---------|
| TOML parser | Parse config file |
| HTTP client | Jira and GitHub API calls |
| Git CLI | All worktree/branch operations (not libgit2 — uses process execution) |
| Argument parser | CLI flag/argument handling |
| `/bin/sh` | Script execution |
| `gh` CLI (optional) | GitHub token resolution |

---

## 19. File System Layout

```
~/.sprout/
├── config.toml              # Main configuration file
└── prompts/                 # Generated prompt files
    ├── IOS-1234.md
    ├── feature_auth.md      # Branch slashes replaced with underscores
    └── prompt-12345678.md   # Raw prompt ticket IDs

<repo>/.sprout/
└── hooks/                   # Repository-specific hooks
    ├── post-launch          # Runs after worktree creation
    └── post-prune           # Runs after worktree removal
```

---

## 20. Platform Considerations

- The tool targets macOS and Linux
- `FoundationNetworking` must be imported on Linux for URLSession
- Git must be available on PATH
- The `gh` CLI is optional (only for GitHub token resolution)
- Launch scripts are terminal-specific (iTerm, tmux, kitty, etc.) — the tool is agnostic to which terminal is used
