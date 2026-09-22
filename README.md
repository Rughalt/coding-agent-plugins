# coding-agent-plugins

Reusable agent plugins that work across Devin CLI, zcode (Windsurf), Claude Code, Cursor, OpenCode, and Codex.

## Plugins

| Plugin | Contents |
|--------|----------|
| [`plugins/pr-review-toolkit`](plugins/pr-review-toolkit) | 6 PR-review agents + `review-pr` command/skill. Repackaged from [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) with a fixed `silent-failure-hunter` agent (upstream has invalid YAML that strict parsers drop). |
| [`plugins/stacked-prs`](plugins/stacked-prs) | `stack-pr` command/skill — works a list of issues as a stack of dependent PRs: plans the stack, implements each issue, runs sequential reviews until no medium+ findings remain, opens each PR, monitors CI, and offers to file deferred low-severity findings as follow-up tickets. Uses pr-review-toolkit's agents when installed; has a built-in rubric otherwise. |

## Install

### Devin CLI / Devin Cloud

```bash
# A single plugin (from its subfolder)
devin plugins install Rughalt/coding-agent-plugins#plugins/pr-review-toolkit
devin plugins install Rughalt/coding-agent-plugins#plugins/stacked-prs

# Or the meta-plugin at the repo root (pulls in every plugin listed in
# .devin-plugin/plugin.json requiredPlugins)
devin plugins install Rughalt/coding-agent-plugins
```

Gives you the `pr-review-toolkit:*` subagents plus the
`/pr-review-toolkit:review-pr` and `/stacked-prs:stack-pr` skills. Synced
through your personal manifest to other machines and cloud sessions.

### zcode / Claude Code (marketplace)

The repo root has a `.claude-plugin/marketplace.json`, so the repo itself is a marketplace:

```bash
/plugin marketplace add Rughalt/coding-agent-plugins
/plugin install pr-review-toolkit@coding-agent-plugins
/plugin install stacked-prs@coding-agent-plugins
```

Gives you the agents and the `/pr-review-toolkit:review-pr` and
`/stacked-prs:stack-pr` commands.

### Cursor, OpenCode, Codex, Vibe, and others

These tools don't load git plugins — copy the agents and skills into
their user-level directories instead:

```bash
# Linux / macOS / WSL
./scripts/install.sh                          # all tools
./scripts/install.sh --tools cursor codex     # pick a subset
./scripts/install.sh --dry-run                # preview

# Windows (PowerShell)
.\scripts\install.ps1
.\scripts\install.ps1 -Tools cursor, codex
.\scripts\install.ps1 -DryRun
```

**Agents:**

| Target | Directory | Format |
|--------|-----------|--------|
| `claude` | `~/.claude/agents/` | markdown (verbatim) |
| `cursor` | `~/.cursor/agents/` | markdown (verbatim) |
| `devin` | `~/.config/devin/agents/` | markdown (verbatim) |
| `agents` | `~/.agents/agents/` | markdown (generic shared dir) |
| `opencode` | `~/.config/opencode/agents/` | markdown, rewritten frontmatter (`mode: subagent`) |
| `codex` | `~/.codex/agents/` | generated TOML |
| `vibe` | `~/.vibe/agents/` + `~/.vibe/prompts/` | generated TOML config + markdown prompt |

**Skills (`review-pr`, `stack-pr`):** copied verbatim to
`~/.claude/skills/`, `~/.cursor/skills/`, `~/.codeium/windsurf/skills/`,
`~/.agents/skills/` (read by Codex — invoke directly with `$review-pr` —
and OpenCode), and `~/.vibe/skills/`. Devin and OpenCode are intentionally
not given their own copy: Devin's plugin ships the skills itself, and
OpenCode reads `~/.agents/skills/` — so no tool sees a skill twice.
Install a specific plugin's skills with `--plugin <name>`.

Canonical definitions live in `plugins/*/agents/` and `plugins/*/skills/`;
the script generates each tool's native format. The `review-pr` and
`stack-pr` workflows run their reviews **sequentially** unless you
explicitly ask for parallel (e.g. `review-pr all parallel`).

## Layout

```
.
├── .claude-plugin/marketplace.json   # zcode/Claude marketplace catalog
├── .devin-plugin/plugin.json         # Devin meta-plugin (requiredPlugins)
├── plugins/pr-review-toolkit/
│   ├── .claude-plugin/plugin.json    # Claude/zcode manifest
│   ├── .devin-plugin/plugin.json     # Devin manifest (takes precedence)
│   ├── agents/                       # 6 review agents (canonical)
│   ├── commands/review-pr.md         # Claude/zcode slash command
│   └── skills/review-pr/SKILL.md     # Devin slash command
├── plugins/stacked-prs/
│   ├── .claude-plugin/plugin.json
│   ├── .devin-plugin/plugin.json
│   ├── commands/stack-pr.md          # Claude/zcode slash command
│   └── skills/stack-pr/SKILL.md      # canonical workflow skill
└── scripts/
    ├── install.sh                  # per-tool installer (Linux/macOS/WSL)
    └── install.ps1                 # per-tool installer (Windows)
```
