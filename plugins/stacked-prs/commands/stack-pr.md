---
description: "Implement issues as a stack of dependent PRs: plan, implement, review until clean, open PR, monitor CI, report"
argument-hint: "[issue numbers/URLs or gh filter]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Write", "Edit", "Task"]
---
# Stacked PR Workflow

Work through a list of issues as a stack of dependent PRs, one PR per
issue, in order. This is a strict protocol — follow the phases exactly,
respect every STOP, and never improvise the order.

**Input:** "$ARGUMENTS" — issue numbers (`#12 #13`), URLs, or a filter for
`gh issue list` (e.g. `--label bug`). If empty, run `gh issue list` and ask
the user which issues to include.

**State directory:** `.git/stack-pr/` in the repo. It is never committed
and survives interruptions — if this session restarts mid-stack, read
`plan.md` and `state.md` there and resume from the first incomplete item.

---

## Hard rules (never violate)

1. One issue = one branch = one PR. No scope creep. Anything noticed but
   out of scope goes to `.git/stack-pr/deferred.md`, not into the diff.
2. **Sequential only.** Finish each phase fully before starting the next.
   Never run reviews in parallel. Never start issue N+1 before PR N is
   opened and its CI is green or explicitly waived by the user.
3. **Never force-push.** To update a stack branch after its base changed,
   merge the base branch into it (`git merge <base>`), never rebase -i or
   `push --force`. Rebase only if the user explicitly asks.
4. **Never merge, close, or mark PRs ready-for-review/draft.** You open
   PRs; humans merge them.
5. **Never commit secrets, .env files, or credentials.** Check `git diff
   --cached` before every commit.
6. **Every STOP below is mandatory.** Ask the user and wait for an answer.
7. If `gh` is missing, unauthenticated, or an issue can't be fetched —
   stop immediately and report; do not guess issue contents.
8. Commits must pass the project's own checks (lint/typecheck/tests) run
   locally before opening each PR. Find them in AGENTS.md/README/CI config;
   if you can't determine them, ask once at the start.

## Severity rubric (used by the review loop)

- **CRITICAL** — breaks production, data loss, security hole, silent
  failure (swallowed error), broken build/tests.
- **HIGH** — real bug, missing error handling on a failure path, wrong
  contract/edge case, missing test for new behavior.
- **MEDIUM** ("yellow") — incomplete error context, unclear naming that
  hides intent, missing edge-case test, comment that contradicts code.
- **LOW** — style nits, optional simplifications, nice-to-have docs.
- **INFO** — observations, suggestions for future work.

A PR may only ship when a review round reports **zero CRITICAL, HIGH, and
MEDIUM** findings. Remaining LOW/INFO items are appended to
`.git/stack-pr/deferred.md` under the PR's heading — do not fix them
unless they are one-line trivial (then fix and note it).

---

## Phase 0 — Setup

1. `git status` must be clean and on the default branch; `git pull`.
   If dirty or on a branch → STOP and ask whether to stash/continue.
2. Verify `gh auth status`. Fail → stop.
3. Create `.git/stack-pr/` and write `state.md` with a checklist of the
   issues and columns: branch, PR #, review rounds, CI, status.

## Phase 1 — Plan the stack

1. Fetch every issue: `gh issue view <n>`. Record title + acceptance
   criteria. If any fetch fails → stop.
2. Order issues so each PR builds only on earlier ones. If issues are
   independent, keep the user's order. If ordering is ambiguous → present
   options and STOP for a decision.
3. Write `.git/stack-pr/plan.md`: numbered table — issue, title, branch
   name `stack/<NN>-<slug>`, base branch, one-line approach.
4. Present the plan to the user and **STOP for approval**. Do not write
   code before approval.

## Phase 2 — Per-issue loop (repeat in stack order)

For each issue:

1. **Branch:** `git checkout -b stack/<NN>-<slug> <base>` where `<base>`
   is the previous stack branch, or the default branch for the first.
2. **Implement** only what the issue requires.
3. **Local checks:** run the project's lint/typecheck/tests. Fix failures
   before proceeding.
4. **Review loop** (max 3 rounds, sequential):
   - If the `pr-review-toolkit` agents are installed (bare names or
     `pr-review-toolkit:*` — whatever the tool exposes), delegate one
     review round to `code-reviewer`, then `silent-failure-hunter`, then
     `pr-test-analyzer` (and `comment-analyzer`/`type-design-analyzer`
     when relevant), each with the diff as scope.
   - Otherwise review the diff yourself against the rubric above, in
     this order: correctness → error handling/silent failures → tests →
     comments → types → simplicity.
   - Fix every CRITICAL/HIGH/MEDIUM. Trivial LOWs may be fixed inline;
     the rest go to `deferred.md` under `## PR <N> — <title>`.
   - Re-run the review until a round reports no CRITICAL/HIGH/MEDIUM.
   - After 3 dirty rounds → STOP, summarize remaining findings, ask the
     user how to proceed.
5. **Commit & push:** conventional commit message referencing the issue
   (`Fixes #<n>` in the PR body, not the commit). `git push -u origin`.
6. **Open PR:** `gh pr create --base <base-branch>` — base is the previous
   stack branch (or default branch for the first). Body: summary, `Fixes
   #<n>`, and a `Stack: <i> of <N>, depends on #<prev-pr>` line.
7. **CI:** `gh pr checks <pr> --watch` (or poll `gh pr checks` every 60s,
   up to ~30 min). Failure → inspect logs, fix, push, re-watch — max 2
   fix attempts, then STOP and report. Pending too long → ask the user
   whether to wait or continue.
8. **Record:** update `state.md` (PR number, status), then continue to the
   next issue.

## Phase 3 — Report

When the last PR is open and green:

```markdown
## Stack complete — <N> PRs

| # | PR | Issue | Status | Deferred lows |
|---|----|-------|--------|---------------|
| 1 | #101 | #12 | CI green | 2 |

### Deferred findings (.git/stack-pr/deferred.md)
- PR #101: <item> [file:line]
...

Recommended merge order: #101 → #102 → #103 (bottom-up).
```

Then ask: **"File the deferred LOW items as follow-up GitHub issues?"**
Only on an explicit yes, `gh issue create` one issue per PR's deferred
group (title: `Follow-up: <pr title> — review leftovers`, body from
deferred.md), and link them in the report. Anything but clear yes → skip.
