# sprout

A CLI tool that creates git worktrees and launches Claude Code with contextual prompts from Jira tickets, GitHub issues, or GitHub PRs.

## Installation

### Using Mint

```bash
mint install hi2gage/sprout
```

### From Source

```bash
git clone https://github.com/hi2gage/sprout.git
cd sprout
swift build -c release
cp .build/release/sprout /usr/local/bin/
```

## Usage

```bash
# Launch from a Jira ticket
sprout launch IOS-1234

# Launch from a GitHub issue
sprout launch "#567"

# Launch from a GitHub PR (uses existing branch)
sprout launch --pr 123

# Launch from a URL
sprout launch "https://github.com/owner/repo/issues/123"

# Launch with a raw prompt
sprout launch "Add a logout button to the settings page"

# Batch mode - process multiple tickets
sprout launch "IOS-1234, IOS-5678, IOS-9012"

# Launch with a branch type prefix
sprout launch IOS-1234 --type bugfix

# Dry run to see what would happen
sprout launch IOS-1234 --dry-run

# Verbose output
sprout launch IOS-1234 --verbose
```

## Configuration

Create a config file at `~/.sprout/config.toml`. The only required section is `[launch]` with a `script` field.

### `[launch]` (required)

| Key | Required | Description |
|-----|----------|-------------|
| `script` | Yes | Shell script to execute after worktree setup |
| `pr_script` | No | Separate script for PR launches (defaults to `script`) |
| `resume_script` | No | Script for resuming an existing worktree (defaults to `script`) |

```toml
[launch]
script = """
osascript -e 'tell application "iTerm"
    create window with default profile
    tell current session of current window
        write text "cd {worktree} && claude --prompt-file {prompt_file}"
    end tell
end tell'
"""
```

### `[worktree]`

| Key | Default | Description |
|-----|---------|-------------|
| `path_template` | `"../worktrees/{branch}"` | Where to create worktrees (relative to repo root, or absolute) |
| `branch_template` | `"{ticket_id}"` | Template for naming branches |
| `default_branch_type` | `"feature"` | Default value for `{branch_type}` when `--type` is not provided |

```toml
[worktree]
path_template = "../worktrees/{branch}"
branch_template = "{branch_type}/{ticket_id}/{slug}"
default_branch_type = "feature"
```

### `[prompt]`

| Key | Default | Description |
|-----|---------|-------------|
| `prefix` | _(none)_ | Text prepended before the prompt body |
| `template` | `"# {title}\n\n{description}"` | Template for the prompt body |
| `suffix` | _(none)_ | Text appended after the prompt body |

```toml
[prompt]
prefix = """
You are working in an iOS codebase using Swift and SwiftUI.
Follow existing code patterns and conventions.
"""
suffix = "Start by understanding the codebase structure, then implement the changes."
```

### `[sources.jira]`

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `base_url` | Yes | | Jira instance URL (e.g., `"https://company.atlassian.net"`) |
| `email` | Yes | | Email for authentication (overridden by `JIRA_EMAIL` or `JIRA_USER` env var) |
| `token` | No | | API token (prefer `JIRA_TOKEN` or `JIRA_API_TOKEN` env var) |
| `default_project` | No | | Default project key for auto-detection |
| `fields` | No | `["summary", "description"]` | Jira fields to include in the prompt |

```toml
[sources.jira]
base_url = "https://your-company.atlassian.net"
email = "you@company.com"
```

### `[sources.github]`

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `repo` | No | _(auto-detected from git remote)_ | Default repo for issue/PR lookup (e.g., `"owner/repo"`) |
| `token` | No | | API token (prefer `gh auth login` or `GITHUB_TOKEN` env var) |

```toml
[sources.github]
repo = "owner/repo"
```

### `[detection]`

| Key | Default | Description |
|-----|---------|-------------|
| `jira_pattern` | `"[A-Z]+-[0-9]+"` | Regex pattern for detecting Jira ticket IDs |
| `github_patterns` | `["#[0-9]+", "gh:[0-9]+"]` | Patterns for detecting GitHub issue references |

### `[variables]`

Arbitrary key-value pairs available for interpolation in all templates and scripts.

```toml
[variables]
user = "your-username"
team = "ios"
```

### Available Variables

These variables can be used in `script`, `path_template`, `branch_template`, and prompt templates:

| Variable | Description |
|----------|-------------|
| `{ticket_id}` | Raw identifier from input (e.g., `IOS-1234`, `567`) |
| `{branch}` | Computed branch name |
| `{branch_type}` | Branch type prefix from `--type` flag or config default (e.g., `feature`, `bugfix`) |
| `{worktree}` | Absolute path to the worktree |
| `{repo_root}` | Root of the current git repository |
| `{repo_name}` | Name of the repository directory |
| `{timestamp}` | Unix timestamp |
| `{date}` | Date in YYYY-MM-DD format |
| `{title}` | Ticket title/summary (from source) |
| `{description}` | Full description (from source) |
| `{slug}` | Slugified title |
| `{url}` | Link back to the ticket |
| `{author}` | Ticket creator |
| `{labels}` | Comma-separated labels |
| `{prompt}` | Escaped prompt content (for inline shell use) |
| `{prompt_file}` | Path to the generated prompt file |
| Any `[variables]` key | Custom variables from config |

## Commands

- `sprout launch <input>` - Create a worktree and launch Claude Code with context
- `sprout prune` - Clean up stale worktrees

## Features

- Auto-detects input type (Jira ticket, GitHub issue/PR, URL, or raw prompt)
- Creates isolated git worktrees for each task
- Fetches ticket/issue context and composes prompts
- Supports batch mode for processing multiple tickets
- Configurable launch scripts (iTerm, Terminal, tmux, etc.)
- Variable interpolation in templates

## Requirements

- Swift 6.2+
- Git
- Linux or macOS
