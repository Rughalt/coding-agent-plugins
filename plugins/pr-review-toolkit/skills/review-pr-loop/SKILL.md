---
name: review-pr-loop
description: Review and fix an authorized local change with the PR Review Toolkit agents in sequential rounds until no verified medium-or-higher findings remain. Use for a pre-PR quality gate; use review-pr for a one-pass or read-only review.
---

# PR review loop

Review the current change, fix verified findings, and review the resulting change again. Do not open, push, merge, or comment on a PR as part of this skill.

**Input:** "$ARGUMENTS" may name a base branch, PR number, or files to focus on. If omitted, review the current local change. The user may request a stricter scope or severity floor; otherwise use the rules below.

## Scope

1. Check the repository instructions and status. Identify the base and the complete change under review before launching agents. Include committed branch changes, staged and unstaged changes, and relevant untracked files; plain `git diff` alone misses some of these. For an existing PR, obtain its current diff and verify the local checkout corresponds to the change being reviewed. If the target or base is ambiguous, ask before editing.
2. Keep work outside this change out of scope. Never overwrite unrelated user changes. If the requested review is read-only, use `review-pr` instead.
3. Record the scope and the revision being reviewed. Refresh the diff after every fix so each round examines the latest code.

## One review round

Run all five review agents **sequentially**, passing each the same scope and current diff. A specialist with no relevant material should report "not applicable" rather than invent a finding:

1. `code-reviewer`
2. `silent-failure-hunter`
3. `pr-test-analyzer`
4. `comment-analyzer`
5. `type-design-analyzer`

Agents may be exposed as bare names or `pr-review-toolkit:<name>`. If an agent is unavailable, stop and report which review is missing; do not label the round clean. `code-simplifier` can edit code, so it is not a review gate. Do not substitute a self-review for a missing specialist.

Collect findings in one ledger with source agent, location, concrete failure mode, severity, and status. Deduplicate overlapping reports without requiring two agents to agree. Verify each medium-or-higher claim against the code before changing it. Translate agents' different scoring systems into this shared rubric:

- **CRITICAL:** production breakage, data loss, exploitable security defect, broken build/tests.
- **HIGH:** demonstrated bug, broken contract or important missing failure handling.
- **MEDIUM:** concrete, consequential edge case, misleading comment that could cause a wrong change, or missing test for a risky behavior.
- **LOW/INFO:** optional polish or speculative observation.

Confidence and severity are separate: a high confidence score does not by itself make an issue HIGH. Explain any severity translation that affects the gate. Treat an agent failure or inconclusive output as an incomplete round.

## Fix and repeat

1. Fix every verified CRITICAL, HIGH, and MEDIUM finding within the authorized change. Preserve lower-severity findings for the final report; do not expand scope just to clear them.
2. Run the project's relevant checks after fixes. A failed check is a blocker until resolved or explicitly reported as unrelated and confirmed by the user.
3. Start a fresh sequential round on the updated change. Explicitly verify each earlier blocker; disappearance from an agent's new report is not proof of a fix. Add any new verified findings to the ledger.
4. Stop successfully only when a complete round has zero verified CRITICAL/HIGH/MEDIUM findings, earlier blockers are verified resolved, and relevant checks pass.

Allow at most **three review rounds**. After the third round with blockers, or when a required agent/check cannot complete, stop and report the remaining findings and what prevented completion. Never claim a clean review from a partial round or silently lower a severity to pass the gate.

Report the reviewed scope/revision, agents that ran, rounds used, fixes made, checks and results, remaining LOW/INFO notes, and any unresolved blockers. Do not create follow-up issues or PR comments without a separate request.
