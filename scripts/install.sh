#!/usr/bin/env bash
# Install pr-review-toolkit agents/skills into per-tool user directories.
#
# Canonical agent definitions live in plugins/<plugin>/agents/*.md
# (Claude Code format: YAML frontmatter + markdown body). This script
# copies or converts them for tools that don't have a plugin system:
#
#   claude    ~/.claude/agents/          verbatim markdown
#   cursor    ~/.cursor/agents/          verbatim markdown
#   devin     ~/.config/devin/agents/    verbatim markdown
#   agents    ~/.agents/agents/          verbatim markdown (generic shared dir)
#   opencode  ~/.config/opencode/agents/ markdown, frontmatter -> description + mode: subagent
#   codex     ~/.codex/agents/           TOML (name/description/developer_instructions)
#   vibe      ~/.vibe/agents/*.toml +    TOML config referencing a prompt file
#             ~/.vibe/prompts/*.md
#
# It also copies skills/ verbatim into each tool's skills dir
# (~/.claude, ~/.cursor, ~/.agents, ~/.codeium/windsurf, ~/.vibe).
# Devin and OpenCode are intentionally skipped for skills — Devin's plugin
# ships them natively and OpenCode reads ~/.agents/skills already.
#
# Usage:
#   ./scripts/install.sh                       # install for all tools
#   ./scripts/install.sh --tools cursor codex  # pick a subset
#   ./scripts/install.sh --plugin <name>       # default: pr-review-toolkit
#   ./scripts/install.sh --dry-run             # preview
#   ./scripts/install.sh --project <dir>       # write project-scoped dirs
#                                              # (.cursor/, .agents/, ...) into
#                                              # a repo checkout to commit —
#                                              # this is how cloud agents
#                                              # (Cursor, Codex) get them

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="pr-review-toolkit"
DRY_RUN=0
PROJECT=""
TOOLS=()

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plugin) PLUGIN="$2"; shift 2 ;;
        --tools) shift; while [[ $# -gt 0 && "$1" != --* ]]; do TOOLS+=("$1"); shift; done ;;
        --project) PROJECT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -n $PROJECT ]]; then
    [[ -d $PROJECT ]] || { echo "error: project dir '$PROJECT' not found" >&2; exit 1; }
fi

# tool -> agents destination (vibe is the parent dir; gets agents/ + prompts/)
declare -A AGENT_TARGETS=(
    [claude]="$HOME/.claude/agents"
    [cursor]="$HOME/.cursor/agents"
    [devin]="$HOME/.config/devin/agents"
    [agents]="$HOME/.agents/agents"
    [opencode]="$HOME/.config/opencode/agents"
    [codex]="$HOME/.codex/agents"
    [vibe]="$HOME/.vibe"
)
declare -A AGENT_KIND=(
    [claude]=md [cursor]=md [devin]=md [agents]=md
    [opencode]=opencode_md [codex]=toml [vibe]=vibe
)
# Deliberately omitted to avoid duplicates:
#   devin    — the plugin itself ships skills/ (use `devin plugins install`)
#   opencode — reads ~/.agents/skills as a compat path already
declare -A SKILL_TARGETS=(
    [claude]="$HOME/.claude/skills"
    [cursor]="$HOME/.cursor/skills"
    [agents]="$HOME/.agents/skills"
    [codex]="$HOME/.agents/skills"
    [windsurf]="$HOME/.codeium/windsurf/skills"
    [vibe]="$HOME/.vibe/skills"
)

# --project <dir>: same fan-out rooted at committed project dirs instead
# of the user home. devin gets .devin/skills here (repo-committed skills
# are an alternative to installing the plugin); opencode stays on the
# shared .agents/skills compat path it already reads.
if [[ -n $PROJECT ]]; then
    AGENT_TARGETS=(
        [claude]="$PROJECT/.claude/agents"
        [cursor]="$PROJECT/.cursor/agents"
        [devin]="$PROJECT/.devin/agents"
        [agents]="$PROJECT/.agents/agents"
        [opencode]="$PROJECT/.opencode/agents"
        [codex]="$PROJECT/.codex/agents"
        [vibe]="$PROJECT/.vibe"
    )
    SKILL_TARGETS=(
        [claude]="$PROJECT/.claude/skills"
        [cursor]="$PROJECT/.cursor/skills"
        [devin]="$PROJECT/.devin/skills"
        [agents]="$PROJECT/.agents/skills"
        [codex]="$PROJECT/.agents/skills"
        [windsurf]="$PROJECT/.windsurf/skills"
        [vibe]="$PROJECT/.vibe/skills"
    )
fi

if [[ ${#TOOLS[@]} -eq 0 ]]; then
    mapfile -t TOOLS < <(printf '%s\n' "${!AGENT_TARGETS[@]}" "${!SKILL_TARGETS[@]}" | sort -u)
fi
for t in "${TOOLS[@]}"; do
    if [[ -z "${AGENT_TARGETS[$t]:-}" && -z "${SKILL_TARGETS[$t]:-}" ]]; then
        echo "unknown tool: $t" >&2; exit 1
    fi
done

AGENTS_DIR="$REPO_ROOT/plugins/$PLUGIN/agents"
SKILLS_DIR="$REPO_ROOT/plugins/$PLUGIN/skills"
[[ -d $AGENTS_DIR || -d $SKILLS_DIR ]] || { echo "error: plugin '$PLUGIN' has no agents/ or skills/ dir" >&2; exit 1; }

write() { # write <file> <tool> ; content on stdin
    local out="$1" tool="$2"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[$tool] would write $out" >&2; cat >/dev/null
    else
        mkdir -p "$(dirname "$out")"
        cat >"$out"
        echo "[$tool] wrote $out"
    fi
}

agent_name()  { awk -F': *' '/^name:/ {print $2; exit}' "$1"; }
agent_body()  { awk 'BEGIN{c=0} /^---$/{c++; if(c==2){f=1; next}} f' "$1"; }
agent_desc() {
    awk '
        /^description:[[:space:]]*[|>]/ {blk=1; next}
        blk && /^[[:space:]]/ {sub(/^[[:space:]]+/,""); print; next}
        blk {exit}
        /^description:/ {sub(/^description:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}
    ' "$1"
}

toml_escape() { sed 's/\\/\\\\/g; s/"""/""\\"/g'; }
toml_escape_line() { tr '\n' ' ' | tr -s ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

render_opencode() {
    printf -- '---\ndescription: |\n'
    agent_desc "$1" | sed 's/^/  /'
    printf 'mode: subagent\n---\n'
    agent_body "$1"
}

render_codex() {
    local name desc
    name="$(agent_name "$1")"
    desc="$(agent_desc "$1" | toml_escape_line)"
    printf 'name = "%s"\n' "$name"
    printf 'description = "%s"\n' "$desc"
    printf 'developer_instructions = """'
    agent_body "$1" | toml_escape
    printf '"""\n'
}

render_vibe_toml() {
    local name desc
    name="$(agent_name "$1")"
    desc="$(agent_desc "$1" | toml_escape_line)"
    printf 'agent_type = "subagent"\n'
    printf 'display_name = "%s"\n' "$name"
    printf 'description = "%s"\n' "$desc"
    printf 'system_prompt_id = "%s"\n' "$name"
}

if [[ -d $AGENTS_DIR ]]; then
for f in "$AGENTS_DIR"/*.md; do
    [[ -e $f ]] || break
    name="$(agent_name "$f")"
    for tool in "${TOOLS[@]}"; do
        [[ -n "${AGENT_TARGETS[$tool]:-}" ]] || continue
        dest="${AGENT_TARGETS[$tool]}"
        case "${AGENT_KIND[$tool]}" in
            md)         cat "$f"        | write "$dest/$name.md" "$tool" ;;
            opencode_md) render_opencode "$f" | write "$dest/$name.md" "$tool" ;;
            toml)       render_codex "$f"   | write "$dest/$name.toml" "$tool" ;;
            vibe)
                render_vibe_toml "$f" | write "$dest/agents/$name.toml" "$tool"
                agent_body "$f"       | write "$dest/prompts/$name.md" "$tool"
                ;;
        esac
    done
done
fi

if [[ -d $SKILLS_DIR ]]; then
    declare -A seen=()
    for tool in "${TOOLS[@]}"; do
        dest="${SKILL_TARGETS[$tool]:-}"
        [[ -n $dest && -z ${seen[$dest]:-} ]] || continue
        seen[$dest]=1
        for skill in "$SKILLS_DIR"/*/; do
            [[ -f $skill/SKILL.md ]] || continue
            sname="$(basename "$skill")"
            find "$skill" -type f | while read -r sf; do
                cat "$sf" | write "$dest/$sname/${sf#"$skill"}" "$tool"
            done
        done
    done
fi
