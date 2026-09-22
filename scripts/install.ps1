# Install pr-review-toolkit agents/skills into per-tool user directories (Windows).
#
# Canonical agent definitions live in plugins/<plugin>/agents/*.md
# (Claude Code format: YAML frontmatter + markdown body). This script
# copies or converts them for tools that don't have a plugin system:
#
#   claude    ~\.claude\agents\           verbatim markdown
#   cursor    ~\.cursor\agents\           verbatim markdown
#   devin     %APPDATA%\devin\agents\     verbatim markdown
#   agents    ~\.agents\agents\           verbatim markdown (generic shared dir)
#   opencode  ~\.config\opencode\agents\  markdown, frontmatter -> description + mode: subagent
#   codex     ~\.codex\agents\            TOML (name/description/developer_instructions)
#   vibe      ~\.vibe\agents\*.toml +     TOML config referencing a prompt file
#             ~\.vibe\prompts\*.md
#
# It also copies skills\ verbatim into each tool's skills dir
# (~\.claude, ~\.cursor, ~\.agents, ~\.codeium\windsurf, ~\.vibe).
# Devin and OpenCode are intentionally skipped for skills — Devin's plugin
# ships them natively and OpenCode reads ~\.agents\skills already.
#
# Usage:
#   .\scripts\install.ps1                          # install for all tools
#   .\scripts\install.ps1 -Tools cursor, codex     # pick a subset
#   .\scripts\install.ps1 -Plugin <name>           # default: pr-review-toolkit
#   .\scripts\install.ps1 -DryRun                  # preview

[CmdletBinding()]
param(
    [string]$Plugin = "pr-review-toolkit",
    [string[]]$Tools = @(),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# tool -> agents destination (vibe is the parent dir; gets agents\ + prompts\)
$AgentTargets = @{
    claude   = "$HOME\.claude\agents"
    cursor   = "$HOME\.cursor\agents"
    devin    = "$env:APPDATA\devin\agents"
    agents   = "$HOME\.agents\agents"
    opencode = "$HOME\.config\opencode\agents"
    codex    = "$HOME\.codex\agents"
    vibe     = "$HOME\.vibe"
}
$AgentKind = @{
    claude = "md"; cursor = "md"; devin = "md"; agents = "md"
    opencode = "opencode_md"; codex = "toml"; vibe = "vibe"
}
$SkillTargets = @{
    claude   = "$HOME\.claude\skills"
    cursor   = "$HOME\.cursor\skills"
    agents   = "$HOME\.agents\skills"
    codex    = "$HOME\.agents\skills"
    windsurf = "$HOME\.codeium\windsurf\skills"
    vibe     = "$HOME\.vibe\skills"
}

if (-not $Tools) {
    $Tools = ($AgentTargets.Keys + $SkillTargets.Keys | Sort-Object -Unique)
}
foreach ($t in $Tools) {
    if (-not $AgentTargets.ContainsKey($t) -and -not $SkillTargets.ContainsKey($t)) {
        throw "unknown tool: $t"
    }
}

$AgentsDir = Join-Path $RepoRoot "plugins\$Plugin\agents"
$SkillsDir = Join-Path $RepoRoot "plugins\$Plugin\skills"
if (-not (Test-Path $AgentsDir)) { throw "error: $AgentsDir not found" }

function Write-Out([string]$Path, [string]$Tool, [string]$Content) {
    if ($DryRun) {
        Write-Host "[$Tool] would write $Path"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [IO.File]::WriteAllText($Path, $Content)
        Write-Host "[$Tool] wrote $Path"
    }
}

function Split-Agent([string]$File) {
    $lines = [IO.File]::ReadAllLines($File)
    $fmEnd = -1; $dashes = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "---") { $dashes++; if ($dashes -eq 2) { $fmEnd = $i; break } }
    }
    if ($fmEnd -lt 0) { throw "$File: missing YAML frontmatter" }

    $name = [IO.Path]::GetFileNameWithoutExtension($File)
    $desc = New-Object System.Text.StringBuilder
    $inDesc = $false
    for ($i = 1; $i -lt $fmEnd; $i++) {
        $line = $lines[$i]
        if ($inDesc) {
            if ($line -match '^\s') { [void]$desc.AppendLine($line.Trim()); continue }
            $inDesc = $false
        }
        if ($line -match '^name:\s*(.+)$') { $name = $Matches[1].Trim().Trim('"', "'") }
        elseif ($line -match '^description:\s*[|>]\s*$') { $inDesc = $true }
        elseif ($line -match '^description:\s*(.+)$') { [void]$desc.Append($Matches[1].Trim().Trim('"', "'")) }
    }
    $body = if ($fmEnd + 1 -lt $lines.Count) { $lines[($fmEnd + 1)..($lines.Count - 1)] -join "`n" } else { "" }
    return @{ Name = $name; Desc = $desc.ToString().Trim(); Body = $body }
}

function Toml-Escape([string]$s) { $s -replace '\\', '\\' -replace '"""', '""\"' }
function Toml-EscapeLine([string]$s) { (($s -replace '\s+', ' ').Trim() -replace '\\', '\\') -replace '"', '\"' }

function Render-Opencode($a) {
    $desc = ($a.Desc -split "`n" | ForEach-Object { "  $_" }) -join "`n"
    return "---`ndescription: |`n$desc`nmode: subagent`n---`n$($a.Body)"
}

function Render-Codex($a) {
    $desc = Toml-EscapeLine $a.Desc
    $body = Toml-Escape $a.Body.Trim()
    return "name = `"$($a.Name)`"`ndescription = `"$desc`"`ndeveloper_instructions = `"`"`"$body`"`"`"`n"
}

function Render-VibeToml($a) {
    $desc = Toml-EscapeLine $a.Desc
    return "agent_type = `"subagent`"`ndisplay_name = `"$($a.Name)`"`ndescription = `"$desc`"`nsystem_prompt_id = `"$($a.Name)`"`n"
}

Get-ChildItem "$AgentsDir\*.md" | ForEach-Object {
    $a = Split-Agent $_.FullName
    foreach ($tool in $Tools) {
        if (-not $AgentTargets.ContainsKey($tool)) { continue }
        $dest = $AgentTargets[$tool]
        switch ($AgentKind[$tool]) {
            "md"          { Write-Out "$dest\$($a.Name).md" $tool ([IO.File]::ReadAllText($_.FullName)) }
            "opencode_md" { Write-Out "$dest\$($a.Name).md" $tool (Render-Opencode $a) }
            "toml"        { Write-Out "$dest\$($a.Name).toml" $tool (Render-Codex $a) }
            "vibe" {
                Write-Out "$dest\agents\$($a.Name).toml" $tool (Render-VibeToml $a)
                Write-Out "$dest\prompts\$($a.Name).md" $tool ($a.Body.Trim() + "`n")
            }
        }
    }
}

if (Test-Path $SkillsDir) {
    $seen = @{}
    foreach ($tool in $Tools) {
        $dest = $SkillTargets[$tool]
        if (-not $dest -or $seen.ContainsKey($dest)) { continue }
        $seen[$dest] = $true
        Get-ChildItem $SkillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object {
            $skillDir = $_.FullName; $sname = $_.Name
            Get-ChildItem $skillDir -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($skillDir.Length).TrimStart('\', '/')
                Write-Out "$dest\$sname\$rel" $tool ([IO.File]::ReadAllText($_.FullName))
            }
        }
    }
}
