---
name: action-execution
description: "Run Kaneo Task Actions via Cursor and gates."
version: 0.5.1
author: AIDeskLab, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Kaneo, Cursor, Action, Task, Gates, PR]
    related_skills: []
---

# Action Execution

`devJunior` orchestrates Kaneo Task execution: **publish Outcome on remote**, create Task branch, sequence Actions. `Cursor` is the only writer of production code. `1 Action = 1 Target file = 1 commit` with MUST marker `action(<ACTION_ID>):`. Merge and `Task Done` belong to `devMaster`.

Full algorithm: [references/workflow.md](references/workflow.md). FAIL, recovery, DoD: [references/invariants.md](references/invariants.md).

```text
Task To Do → remote Outcome → Task branch → orphan-reconcile → Cursor
→ Action Gate → Done → provenance → Task Gate → push Task → PR Task→Outcome → In review
```

## When to Use

- Kaneo Task: `label: Task`, `status: To Do`, `assigned: devJunior`, **no `FAIL`** on Task or child Actions.
- Tree `Outcome → Task → Action[]`. Rework: `In review → To Do` with new Actions (not `FAIL`).

Don't use: any `FAIL` (skip); Outcome execution, semantic review, merge, rescue, adversary, decomposition.

Preflight misses are **FAIL**. Same state → same cron failure ⇒ `FAIL`.

After Action `FAIL` is cleared, retry only if `HEAD == recorded before_sha` **and** `git status --porcelain` is empty.

## Prerequisites

- Production git repo; bash/git Unix (`platforms: linux`).
- Product repo consumes a pinned revision of the external `.pipe` repository at `.pipe/`. The attachment mechanism is outside this skill. Gates: `.pipe/aidesklab-factory-gates/{action_gate.sh,task_gate.sh,transition_guard.py}`.
- `make verify-fast`; Kaneo `Verification` as structured argv (`runner` + `args` + `test_files`; optional `support_files`). Overlay paths have the same mechanical security boundary as Target file (see workflow).
- Production `task_gate.sh` accepts structured argv (`--acceptance-runner` / repeated `--acceptance-arg`, or `--acceptance-json`) and executes **without** `bash -lc` / `eval` / shell interpretation.
- Approved Cursor CLI **effective** deny policy (not mere file existence). Permissions and sandbox are separate layers.
- Kaneo MCP. Cursor: confirmed CLI prompt API (`agent -p "<prompt>" --force --model auto`). stdin redirection is **not** the prompt API.
- **Cron must not run** until production `.pipe/aidesklab-factory-gates/task_gate.sh` implements this contract **and** is proven on the expanded 10-case gate suite (see workflow). This config repo does not ship `.pipe`.

Missing any of these, or a gate still using `--acceptance-cmd` + shell interpretation → Task `FAIL`.

## How to Run

Do not rely on shell variables across `terminal` calls. Validate branch / remote / Action ID / Target file / `test_files` / `support_files` **before** subprocesses (see workflow).

```
terminal(command="git fetch <validated-remote>")
# 4-state Outcome: verify/track/push-u/create-from-default; then verify remote SHA
# persist outcome_remote, outcome_branch, outcome_base_sha
# Task branch only AFTER remote Outcome exists
# Before each unfinished Action: search commits ^action(<ID>):
#   0 → Cursor; 1 AND commit==HEAD → reconstruct (no Cursor); else Action FAIL
terminal(command="git rev-parse HEAD && git status --porcelain")  # FAIL-retry: SHA + empty
# write Action+envelope to /tmp (outside repo); read file; pass as ONE prompt value:
terminal(command="agent -p --force --model auto \"$(cat /tmp/aidesklab-actions/<task-id>/<action-id>.md)\"", workdir="<repo>")
# NEVER: agent -p ... < prompt.md   (stdin is not the prompt API)
# after Cursor PASS or FAIL: rm /tmp/aidesklab-actions/<task-id>/<action-id>.md if created
# action_gate.sh --before <literal> --file <Target>; local MUST check HEAD ^action(<ID>):
# preferred production flag --action-id (external .pipe dependency)
# before provenance / Task Gate: fetch again; compare fresh remote Outcome tip
terminal(command="git fetch <validated-remote>")
# refs/remotes/<remote>/<outcome_branch> != outcome_base_sha → Task FAIL (no rebase/merge)
# provenance: commits(outcome_base_sha..HEAD) == Done Action commit_sha set
# overlay paths: same security as Target; production Target file cannot be an overlay file
terminal(command=".pipe/aidesklab-factory-gates/task_gate.sh --base \"<Outcome>\" --verify-cmd \"make verify-fast\" --acceptance-runner <runner> --acceptance-arg <arg> ... --test-file <path> ...")
```

Confirm the installed `agent --help` / docs before cron. If the confirmed interface differs, still pass **one explicit prompt value** — never assume stdin redirection.

## Quick Reference

| Step | Rule | Success |
|---|---|---|
| FAIL / recovery | skip if `FAIL`; retry Cursor only HEAD==`before_sha` AND porcelain empty | else FAIL again |
| Preflight | gates, verify-fast, structured Verification, effective Cursor deny | else Task `FAIL` |
| Inputs | `git check-ref-format`; configured remote only; Action ID format; canonical Target; overlay `test_files`/`support_files` | else matching `FAIL` |
| Outcome | 4-state local/remote; `git push -u` if remote missing | remote SHA matches; pin metadata |
| Drift | fresh remote Outcome tip != `outcome_base_sha` | Task `FAIL` (no auto-sync) |
| Orphan | 0 / 1==HEAD / else `action(<ID>):` commits | 0 Cursor; 1==HEAD reconstruct; else FAIL |
| Target | one file; not `.pipe/**` `.git/**` secrets; no traversal | else Action `FAIL` |
| Overlay | canonical; no traversal/absolute/symlink escape; not `.pipe/**` `.git/**` secrets; test/fixture only; not current Target | else Task `FAIL` |
| Cursor | one prompt value via confirmed CLI; deny push/gh/.pipe; delete `/tmp` prompt after | 1 commit `action(<ID>):` |
| Gate PASS | local marker MUST; then evidence → guard → Done | no second Cursor on Kaneo write fail |
| Provenance | `git fetch` then `commits(base..HEAD) == Done Action commit_sha set` | else Task `FAIL` |
| Task Gate | structured argv + overlay baseline; expanded 10-case; cron blocked until proven | exit 0 |
| Push/PR/guard | any technical fail | Task `FAIL` |

## Procedure

### 1. Intake + preflight

Skip if `FAIL`. Zero Actions / broken tree / invalid Verification / invalid overlay paths / missing gates / missing `make verify-fast` / Cursor policy missing or not effective / Outcome remote fail / invalid branch-remote-ID-path → **Task `FAIL`**. Bad Target → **Action `FAIL`**.

### 2. Branches

`git fetch`. Outcome 4-state (verify/track/push/create+push). Confirm remote Outcome SHA. Persist `outcome_remote`, `outcome_branch`, `outcome_base_sha`. Then Task branch. Later: re-fetch and compare fresh remote Outcome tip; drift → Task `FAIL`.

### 3. Action loop

For each unfinished Action: orphan-reconcile first. 0 commits → Target check → trusted baseline (after FAIL clear: SHA + clean WT) → `/tmp` prompt read as one value → Cursor → delete `/tmp` prompt if created (PASS or FAIL) → Action Gate + **local** `action(<ID>):` check.

- 1 matching commit **and** it is Task HEAD → reconstruct evidence (no Cursor). Matching commit that is not HEAD → Action `FAIL`.
- PASS: evidence JSON → guard → `Done`. Kaneo write fail → next run starts at orphan-reconcile.
- FAIL: `AIDESKLAB_EXEC_FAILURE_V1` (`before_sha`, `failed_head_sha`); stop cycle.

### 4. Provenance → Task Gate → PR → In review

`git fetch` then fresh remote Outcome tip != pin → Task `FAIL`. Provenance mismatch → Task `FAIL`. Invalid overlay path → Task `FAIL`. Gate/push/PR/guard fail → Task `FAIL`. Never merge.

### 5. Rework

Same branches/PR; new Actions; each starts with orphan-reconcile.

## Pitfalls

- Envelope is not a security boundary; effective deny policy is.
- Do not assume `agent ... < file` is the Cursor prompt API.
- Delete the `/tmp` Action prompt after Cursor, PASS or FAIL; Git recovery evidence is independent.
- Do not overlay `test_files`/`support_files` by trusting Task text; invalid overlay path → Task `FAIL`.
- `--acceptance-cmd` + `bash -lc` is not this skill's contract. Do not invent a shell-safe string workaround.
- Verification blacklist of `;|&` is insufficient — structured allowlisted argv only.
- Dirty worktree with HEAD==`before_sha` is **not** trusted retry.
- Orphan matching commit that is only an ancestor (not HEAD) is **FAIL**.
- Compare fresh remote Outcome tip, not a stale local tip; do not auto-sync Outcome; do not `reset --hard`.
- `action_gate.sh --action-id` is a production-gate dependency; still check subject locally.

## Verification (DoD)

```text
all Actions = Done
AND every Action has machine-readable commit evidence
AND every Action passed Action Gate
AND Task commit set == validated Done Action commit set
AND Task Gate = 0
AND Task branch pushed
AND correct PR Task → Outcome exists
AND transition_guard allowed the transition
AND Task = In review
AND no FAIL labels remain on Task or child Actions
```
