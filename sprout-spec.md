# Sprout CLI Specification

A fire-and-forget CLI tool that creates git worktrees and launches Claude Code with context from various sources.

## Overview

Sprout automates the setup phase of working on a ticket:
1. Accepts input (raw prompt, Jira ticket, GitHub issue)
2. Fetches context from the source
3. Creates a git worktree with an appropriate branch
4. Writes a prompt file with the composed context
5. Executes a user-defined shell script to launch Claude Code

Once launched, Sprout exits. It's a launcher, not a monitor.

---

## CLI Interface

### Basic Usage

```bash
sprout <input>
```

Sprout auto-detects the input type:
- Jira ticket pattern (e.g., `IOS-1234`) → Jira source
- GitHub issue pattern (e.g., `#567` or `gh:567`) → GitHub source  
- URL (e.g., `https://github.com/org/repo/issues/567`) → Parse and route
- Anything else → Raw prompt

### Examples

```bash
# Raw prompt
sprout "Fix the login button alignment on iOS 17"

# Jira ticket (auto-detected)
sprout IOS-1234

# GitHub issue (auto-detected)
sprout "#567"
sprout "gh:567"

# Explicit source override
sprout --jira IOS-1234
sprout --github 567
sprout --prompt "Fix the bug"
```

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--jira <id>` | `-j` | Explicitly use Jira source |
| `--github <id>` | `-g` | Explicitly use GitHub source |
| `--prompt <text>` | `-p` | Explicitly use raw prompt |
| `--branch <name>` | `-b` | Override branch name |
| `--dry-run` | `-n` | Print what would be executed without running |
| `--config <path>` | `-c` | Use alternate config file |
| `--verbose` | `-v` | Print detailed output |
| `--help` | `-h` | Show help |
| `--version` | | Show version |

### Return Codes

| Code | Meaning |
|------|---------|
| 0 | Success - Claude Code launched |
| 1 | Config error (missing, invalid) |
| 2 | Source error (auth failed, ticket not found) |
| 3 | Git error (worktree creation failed) |
| 4 | Script execution error |

---

## Config File

Location: `~/.sprout/config.toml`

### Minimal Config

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
cd {worktree}
claude --print {prompt_file}
"""
```

### Full Config

```toml
# =============================================================================
# Sprout Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Worktree Settings
# -----------------------------------------------------------------------------
[worktree]
# Where to create worktrees (relative to repo root, or absolute path)
path_template = "../worktrees/{branch}"

# Branch naming template
branch_template = "{ticket_id}"

# Alternative branch templates:
# branch_template = "{user}/{ticket_id}"
# branch_template = "{ticket_id}-{slug}"

# -----------------------------------------------------------------------------
# Prompt Composition
# -----------------------------------------------------------------------------
[prompt]
# Prefix added before ticket content
prefix = """
You are working in an iOS codebase using Swift and SwiftUI.
Follow existing code patterns and conventions.
"""

# Template for composing the prompt body
template = """
# {title}

{description}
"""

# Suffix added after ticket content
suffix = """
Start by understanding the codebase structure, then implement the changes.
"""

# -----------------------------------------------------------------------------
# Launch Script
# -----------------------------------------------------------------------------
[launch]
# Shell script executed after worktree creation
# All variables are interpolated before execution
script = """
git worktree add {worktree} -b {branch}
tmux new-window -n {ticket_id} -c {worktree} 'claude --print {prompt_file}'
"""

# -----------------------------------------------------------------------------
# Sources
# -----------------------------------------------------------------------------
[sources.jira]
base_url = "https://yourcompany.atlassian.net"
email = "you@company.com"
# API token: set JIRA_API_TOKEN env var or use token field
# token = "..." (not recommended - use env var)

# Project key for auto-detection (optional)
default_project = "IOS"

# Fields to include in prompt
fields = ["summary", "description", "acceptance_criteria"]

[sources.github]
# Default repo for issue lookup
repo = "org/repo-name"
# Token: set GITHUB_TOKEN env var or use token field

# -----------------------------------------------------------------------------
# Detection Patterns (optional - sensible defaults provided)
# -----------------------------------------------------------------------------
[detection]
jira_pattern = "[A-Z]+-[0-9]+"
github_patterns = ["#[0-9]+", "gh:[0-9]+"]
```

---

## Variable Reference

Variables available for interpolation in `script`, `path_template`, `branch_template`, and `prompt.template`:

### Always Available

| Variable | Description | Example |
|----------|-------------|---------|
| `{ticket_id}` | Raw identifier from input | `IOS-1234`, `567` |
| `{branch}` | Computed branch name | `IOS-1234` |
| `{worktree}` | Full path to worktree | `/Users/gage/dev/worktrees/IOS-1234` |
| `{prompt_file}` | Path to temp file containing prompt | `/tmp/sprout-abc123.md` |
| `{repo_root}` | Root of the current git repository | `/Users/gage/dev/ios-app` |
| `{timestamp}` | Unix timestamp | `1704067200` |
| `{date}` | Date in YYYY-MM-DD | `2025-01-01` |

### From Ticket Sources (Jira/GitHub)

| Variable | Description |
|----------|-------------|
| `{title}` | Ticket title/summary |
| `{description}` | Full description body |
| `{slug}` | Slugified title (lowercase, hyphens) |
| `{url}` | Link back to the ticket |
| `{author}` | Ticket creator |
| `{labels}` | Comma-separated labels/tags |

### Custom Variables

Users can define custom variables in config:

```toml
[variables]
user = "gage"
team = "ios"
```

Then use `{user}` and `{team}` in templates.

---

## Example Configs by Terminal

### tmux

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
tmux new-window -n {ticket_id} -c {worktree} 'claude --print {prompt_file}'
"""
```

### tmux (multiple panes)

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
tmux new-window -n {ticket_id} -c {worktree}
tmux send-keys -t {ticket_id} 'claude --print {prompt_file}' Enter
tmux split-window -h -t {ticket_id} -c {worktree}
tmux send-keys -t {ticket_id} 'nvim .' Enter
tmux select-pane -t {ticket_id}:0.0
"""
```

### iTerm2

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
osascript -e '
tell application "iTerm"
    create window with default profile
    tell current session of current window
        write text "cd {worktree} && claude --print {prompt_file}"
    end tell
end tell'
"""
```

### Kitty

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
kitty @ launch --type=tab --cwd={worktree} --title={ticket_id} claude --print {prompt_file}
"""
```

### WezTerm

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
wezterm cli spawn --cwd {worktree} -- claude --print {prompt_file}
"""
```

### Plain Terminal (macOS)

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
open -a Terminal {worktree}
# Note: Can't easily send commands to Terminal.app
# Consider using iTerm2 or tmux for better automation
"""
```

### Ghostty

```toml
[launch]
script = """
git worktree add {worktree} -b {branch}
ghostty -e "cd {worktree} && claude --print {prompt_file}"
"""
```

---

## Prompt File Format

Sprout writes a temporary markdown file containing the composed prompt:

```markdown
You are working in an iOS codebase using Swift and SwiftUI.
Follow existing code patterns and conventions.

# Fix login button alignment on iOS 17

The login button is misaligned on iOS 17 devices. It appears 
to be shifted 8px to the left compared to the design.

## Acceptance Criteria
- Button should be centered horizontally
- Should match Figma design exactly
- Fix should not affect iOS 16 or earlier

Start by understanding the codebase structure, then implement the changes.
```

The file path is available as `{prompt_file}` for use in the launch script.

---

## Directory Structure

```
~/.sprout/
├── config.toml          # Main config
└── templates/           # Optional: prompt templates
    ├── ios.md
    └── backend.md
```

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ sprout IOS-1234                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Load config from ~/.sprout/config.toml                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Parse input, detect source type (Jira pattern matched)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Fetch ticket from Jira API                                   │
│    → title: "Fix login button alignment"                        │
│    → description: "The login button is misaligned..."           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Compute variables                                            │
│    → branch: "IOS-1234"                                         │
│    → worktree: "/Users/gage/dev/worktrees/IOS-1234"            │
│    → slug: "fix-login-button-alignment"                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Compose prompt from template, write to temp file             │
│    → prompt_file: "/tmp/sprout-a1b2c3.md"                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Interpolate all variables into launch script                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. Execute script via /bin/sh                                   │
│    → git worktree add ...                                       │
│    → tmux new-window ...                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. Exit 0                                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Milestones

### Milestone 1: Skeleton
- [ ] Swift package with swift-argument-parser
- [ ] Basic CLI parsing (just accept a string argument)
- [ ] Load config file from `~/.sprout/config.toml`
- [ ] Execute hardcoded shell command
- [ ] Prove end-to-end flow works

### Milestone 2: Config + Interpolation
- [ ] Define config schema as Codable structs
- [ ] Parse TOML with TOMLDecoder
- [ ] Build variable interpolation system
- [ ] Script execution with interpolated values

### Milestone 3: Raw Prompt Source
- [ ] Accept plain string as input
- [ ] Generate branch name (slugify or hash)
- [ ] Write prompt to temp file
- [ ] Full end-to-end with raw prompts

### Milestone 4: Jira Source
- [ ] Jira API client
- [ ] Auth via env var (JIRA_API_TOKEN)
- [ ] Fetch ticket by ID
- [ ] Parse relevant fields
- [ ] Compose prompt from template

### Milestone 5: GitHub Source
- [ ] GitHub API client
- [ ] Auth via env var (GITHUB_TOKEN)
- [ ] Fetch issue by number
- [ ] Parse relevant fields

### Milestone 6: Polish
- [ ] Input auto-detection (regex patterns)
- [ ] `--dry-run` flag
- [ ] Friendly error messages
- [ ] `--verbose` output
- [ ] README with example configs

---

## Future Considerations (Out of Scope for v1)

- Linear, Shortcut, Asana sources
- Worktree cleanup command (`sprout clean`)
- List active worktrees (`sprout list`)
- Config validation command (`sprout check`)
- Shell completions
