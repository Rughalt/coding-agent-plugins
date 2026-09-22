---
description: "Review, fix, and repeat sequential specialist reviews until no verified medium-or-higher findings remain"
argument-hint: "[base branch, PR number, or files]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Write", "Edit", "Task"]
---

# PR review loop

For "$ARGUMENTS", review the current change, fix verified findings, and review again. The arguments may specify a base branch, PR number, or files. This command allows local fixes within that change; do not push, open, merge, or comment on a PR.

1. Read repository instructions and inspect status. Establish the complete scope, including committed branch changes, staged and unstaged changes, and relevant untracked files. Plain `git diff` alone is insufficient. If reviewing an existing PR, verify that the local checkout matches its current change. Ask before editing if the target or base is ambiguous. Preserve unrelated user changes.
2. Run these five installed agents **one at a time** against the same current diff: `code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`, `comment-analyzer`, `type-design-analyzer`. Names may be prefixed with `pr-review-toolkit:`. A specialist with no relevant material may report "not applicable". If an agent is unavailable or fails, the round is incomplete. `code-simplifier` is not part of the gate because it can edit code.
3. Merge duplicate findings into a ledger with agent, location, concrete failure mode, severity, and status. Verify every medium-or-higher claim against the code. Normalize agent scales to CRITICAL (production breakage/data loss/security/broken build), HIGH (demonstrated bug, broken contract or important failure handling), MEDIUM (consequential edge case, materially misleading comment or missing test for risky behavior), and LOW/INFO (optional or speculative). Confidence is not severity. Agreement between agents is not required.
4. Fix verified CRITICAL/HIGH/MEDIUM findings within scope. Keep LOW/INFO for the final report. Run relevant project checks, refresh the diff, and start a new sequential round. Explicitly verify that each earlier blocker is resolved; its absence from a new report is insufficient.
5. Succeed only after a complete round has no verified CRITICAL/HIGH/MEDIUM findings, earlier blockers are resolved, and checks pass. Stop after **three review rounds** with blockers, or if an agent/check cannot complete. Report the scope/revision, agents, rounds, fixes, checks, remaining LOW/INFO and unresolved blockers. Never describe an incomplete round as clean or create follow-up issues without a separate request.
