# sprout

A CLI tool that creates git worktrees and launches Claude Code with contextual prompts from Jira tickets, GitHub issues, or GitHub PRs.

## Installation

### Using Mint

```bash
mint install hi2gage/sprout
```

### From Source

```bash
git clone https://github.com/gagehalverson/sprout.git
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

# Dry run to see what would happen
sprout launch IOS-1234 --dry-run

# Verbose output
sprout launch IOS-1234 --verbose
```

## Configuration

Create a config file at `~/.sprout/config.toml`:

```toml
[sources.jira]
base_url = "https://your-company.atlassian.net"
email = "you@company.com"
api_token = "your-api-token"

[sources.github]
repo = "owner/repo"  # Optional - auto-detected from git remote

[worktree]
branch_template = "{ticket_id}"
path_template = "../worktrees/{branch}"

[launch]
script = """
osascript -e 'tell application "iTerm"
    create window with default profile
    tell current session of current window
        write text "cd {worktree} && claude --prompt-file {prompt_file}"
    end tell
end tell'
"""

[variables]
user = "your-username"
```

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

- macOS 15+
- Swift 6.1+
- Git
