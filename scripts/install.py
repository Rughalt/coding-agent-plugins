#!/usr/bin/env python3
"""Install pr-review-toolkit agents into per-tool user directories.

Canonical agent definitions live in plugins/<plugin>/agents/*.md
(Claude Code format: YAML frontmatter + markdown body). This script
copies or converts them for tools that don't have a plugin system:

  claude    ~/.claude/agents/          verbatim markdown
  cursor    ~/.cursor/agents/          verbatim markdown
  devin     ~/.config/devin/agents/    verbatim markdown
  agents    ~/.agents/agents/          verbatim markdown (generic shared dir)
  opencode  ~/.config/opencode/agents/ markdown, frontmatter -> description + mode: subagent
  codex     ~/.codex/agents/           TOML (name/description/developer_instructions)
  vibe      ~/.vibe/agents/*.toml +    TOML config referencing a prompt file
            ~/.vibe/prompts/*.md

It also copies skills/ verbatim into each tool's skills dir
(~/.claude, ~/.cursor, ~/.agents, ~/.codeium/windsurf, ~/.vibe).
Devin and OpenCode are intentionally skipped for skills — Devin's plugin
ships them natively and OpenCode reads ~/.agents/skills already.

Usage:
  python3 scripts/install.py                 # install for all tools
  python3 scripts/install.py --tools cursor opencode
  python3 scripts/install.py --plugin pr-review-toolkit  # default
"""

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

TARGETS = {
    "claude": ("md", Path("~/.claude/agents")),
    "cursor": ("md", Path("~/.cursor/agents")),
    "devin": ("md", Path("~/.config/devin/agents")),
    "agents": ("md", Path("~/.agents/agents")),
    "opencode": ("opencode_md", Path("~/.config/opencode/agents")),
    "codex": ("toml", Path("~/.codex/agents")),
    "vibe": ("vibe", Path("~/.vibe")),
}

# Skills are plain SKILL.md directories — copied verbatim per tool.
# Deliberately omitted to avoid duplicates:
#   devin    — the plugin itself ships skills/ (use `devin plugins install`)
#   opencode — reads ~/.agents/skills as a compat path already
SKILL_TARGETS = {
    "claude": Path("~/.claude/skills"),
    "cursor": Path("~/.cursor/skills"),
    "agents": Path("~/.agents/skills"),   # also read by Codex and OpenCode
    "codex": Path("~/.agents/skills"),
    "windsurf": Path("~/.codeium/windsurf/skills"),
    "vibe": Path("~/.vibe/skills"),
}


def parse_agent(path: Path) -> dict:
    """Extract name, description, and body from a Claude-format agent file."""
    text = path.read_text()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
    if not m:
        raise ValueError(f"{path.name}: missing YAML frontmatter")
    fm, body = m.group(1), m.group(2)

    name = path.stem
    description = ""
    lines = fm.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip().strip('"').strip("'")
        elif line.startswith("description:"):
            rest = line.split(":", 1)[1].strip()
            if rest in ("|", ">", "|-", ">-", "|+", ">+"):
                block = []
                i += 1
                while i < len(lines) and (lines[i].startswith(" ") or not lines[i]):
                    block.append(lines[i].strip())
                    i += 1
                description = "\n".join(block).strip()
                continue
            else:
                description = rest.strip('"').strip("'")
        i += 1
    return {"name": name, "description": description, "body": body}


def render_opencode_md(agent: dict) -> str:
    desc_lines = "\n".join("  " + l for l in agent["description"].split("\n"))
    return (
        "---\n"
        "description: |\n"
        f"{desc_lines}\n"
        "mode: subagent\n"
        "---\n"
        f"{agent['body']}"
    )


def render_codex_toml(agent: dict) -> str:
    def tq(s: str) -> str:
        # TOML triple-quoted basic string: escape backslashes and """ sequences
        return '"""' + s.replace("\\", "\\\\").replace('"""', '""\\"') + '"""'

    desc = " ".join(agent["description"].split())
    return (
        f'name = "{agent["name"]}"\n'
        f'description = {tq(desc)}\n'
        f'developer_instructions = {tq(agent["body"].strip())}\n'
    )


def render_vibe(agent: dict) -> tuple[str, str]:
    """Return (agents/<name>.toml, prompts/<name>.md) for Mistral Vibe."""
    def tq(s: str) -> str:
        return '"""' + s.replace("\\", "\\\\").replace('"""', '""\\"') + '"""'

    desc = " ".join(agent["description"].split())
    toml = (
        'agent_type = "subagent"\n'
        f'display_name = "{agent["name"]}"\n'
        f'description = {tq(desc)}\n'
        f'system_prompt_id = "{agent["name"]}"\n'
    )
    return toml, agent["body"].strip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plugin", default="pr-review-toolkit", help="plugin folder under plugins/ (default: pr-review-toolkit)")
    all_tools = sorted(set(TARGETS) | set(SKILL_TARGETS))
    ap.add_argument("--tools", nargs="*", default=all_tools, choices=all_tools, help="tools to install for (default: all)")
    ap.add_argument("--dry-run", action="store_true", help="print what would be written")
    args = ap.parse_args()

    agents_dir = REPO_ROOT / "plugins" / args.plugin / "agents"
    if not agents_dir.is_dir():
        sys.exit(f"error: {agents_dir} not found")

    agents = [parse_agent(p) for p in sorted(agents_dir.glob("*.md"))]
    if not agents:
        sys.exit(f"error: no agent .md files in {agents_dir}")

    skills_dir = REPO_ROOT / "plugins" / args.plugin / "skills"
    skill_dirs = sorted(p for p in skills_dir.iterdir() if (p / "SKILL.md").is_file()) if skills_dir.is_dir() else []

    renderers = {
        "md": lambda a, p: p.read_text(),
        "opencode_md": lambda a, p: render_opencode_md(a),
        "toml": lambda a, p: render_codex_toml(a),
    }

    def write(out: Path, content: str, tool: str) -> None:
        if args.dry_run:
            print(f"[{tool}] would write {out}")
        else:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(content)
            print(f"[{tool}] wrote {out}")

    for tool in args.tools:
        if tool not in TARGETS:
            continue
        kind, dest = TARGETS[tool]
        dest = dest.expanduser()
        for agent, src in zip(agents, sorted(agents_dir.glob("*.md"))):
            if kind == "vibe":
                toml, prompt = render_vibe(agent)
                write(dest / "agents" / f"{agent['name']}.toml", toml, tool)
                write(dest / "prompts" / f"{agent['name']}.md", prompt, tool)
            else:
                ext = "toml" if kind == "toml" else "md"
                write(dest / f"{agent['name']}.{ext}", renderers[kind](agent, src), tool)

    written_skills = set()
    for tool in args.tools:
        if tool not in SKILL_TARGETS:
            continue
        dest = SKILL_TARGETS[tool].expanduser()
        if dest in written_skills:
            continue
        written_skills.add(dest)
        for skill in skill_dirs:
            for f in sorted(skill.rglob("*")):
                if f.is_file():
                    write(dest / skill.name / f.relative_to(skill), f.read_text(), tool)
    return 0


if __name__ == "__main__":
    sys.exit(main())
