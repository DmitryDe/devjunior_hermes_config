# Action Execution — full workflow

Source of rules: `docs/action-execution-final-review.md`.

## Role

`devMaster` = decomposition + semantic Task review + merge.

`devJunior` = execution orchestrator (create **and publish** Outcome branch; create Task branch).

`Cursor` = only production-code writer. Mechanical gates = technical verdict. Kaneo = workflow state. `FAIL` = anti-loop label.

`devJunior` must not: write/fix production code; replace Cursor; merge Actions; commit instead of Cursor; merge Task→Outcome; skip gates; change Kaneo status without `transition_guard.py`; auto-clear `FAIL`; destructive-reset; auto-rebase/merge Outcome into Task.

Main workflow:

```text
Task To Do
→ remote Outcome confirmed
→ Task branch
→ orphan-commit reconcile (per Action)
→ Cursor (if 0 marker commits)
→ commit
→ Action Gate + local action(<ID>): check
→ evidence → Done
→ Task commit provenance
→ Task Gate (structured argv + test overlay)
→ push Task
→ PR Task → Outcome
→ In review
```

## 1. Inputs

Kaneo: `label: Task`, `status: To Do`, `assigned: devJunior`. Load Task, `Verification`, Outcome, branch metadata, child Actions, `Target file`, `FAIL` labels. Tree must be `Outcome → Task → Action[]`.

### 1a. Dynamic input validation (before any subprocess / git write)

Treat Kaneo values as **data**, not shell syntax. Invalid → corresponding `FAIL`. Prefer argv subprocesses; do not interpolate untrusted strings into a shell program.

| Input | Rule | FAIL owner |
|---|---|---|
| branch names | `git check-ref-format --allow-onelevel` (or equivalent) succeeds | Task |
| remote | must be a configured git remote (`git remote`) | Task |
| Action ID | match the factory ID format (stable token; no spaces/metacharacters) | Action |
| Target file | canonical repo-relative path; no `..` traversal; not outside the repo; security policy | Action |
| `test_files` / `support_files` | same overlay security boundary as below; not the current production Target file | Task |

### 1b. FAIL gate

Task or child `FAIL` → skip (no Cursor, no gate retry, no PR).

After Action `FAIL` cleared: retry Cursor only if `HEAD == recorded before_sha` **and** `git status --porcelain` is empty. Else Action `FAIL` again. Failed HEAD is never the new baseline. Review return is not `FAIL`.

## 2. Preflight — every miss is FAIL

**Task FAIL:** zero Actions; broken hierarchy; missing/invalid Verification; invalid overlay `test_files`/`support_files`; missing `.pipe/aidesklab-factory-gates` gates; missing `make verify-fast`; Cursor CLI policy missing **or** required effective deny not present; Outcome cannot be published/verified on remote; invalid branch/remote; production Task Gate still interprets Verification as a shell string.

**Action FAIL:** missing/ambiguous/multiple Target file; malformed metadata; invalid Action ID; Target outside security boundary (`.pipe/**`, `.git/**`, secrets, repo-forbidden paths, path traversal).

Do not restore missing requirements.

### Cursor mechanical permissions

Prerequisite: approved Cursor CLI policy in the production repo (`.cursor/cli.json` or version-equivalent). **Existence of the file is not enough** — mechanically verify the **effective** deny policy.

Minimum required deny:

```text
deny Write(.pipe/**)
deny secrets / .env / keys
deny gh / PR operations
deny git push   (do not deny all git — Cursor must make a local commit)
deny unneeded MCP / WebFetch
```

Allow: edit Target file, read needed context, allowed tests/tools, **local** commit.

Permissions and sandbox are **different layers**. If the factory requires a sandbox policy, check that sandbox config separately. Absence or mismatch → Task `FAIL`. Envelope is semantic only, not the security boundary.

### Verification schema (Kaneo)

Required structured shape. Tasks **may create new acceptance tests**.

```yaml
Verification:
  runner: <allowlisted>
  args:
    - -q
    - tests/auth/test_login.py::test_invalid_token
  test_files:
    - tests/auth/test_login.py
  support_files:
    - tests/conftest.py
```

- `runner` + `args`: allowlisted executable + argv. Never a shell program.
- `test_files`: required when the Task creates or extends acceptance tests; used for baseline overlay. Validate **before Task Gate** with the overlay security boundary below.
- `support_files`: optional; fixtures/helpers that the new tests need; also overlaid onto Outcome production (never production implementation). Same overlay security boundary.

**Overlay security (each `test_files` / `support_files` path, before Task Gate):**

```text
canonical repo-relative
no ..
not absolute
no symlink escape outside repo
not .pipe/**
not .git/**
not secret / credential path
inside repo-defined test / fixture boundaries
current production Action Target file cannot also be a baseline overlay file
```

A path that cannot be mechanically classified as a test/support artifact → Task `FAIL`. Do not overlay by trusting Task text.

Allowlist from repo/`AGENTS.md` (`pytest`, `pnpm`, `npm`, `cargo`, `make`, …).

If the Task still stores a string: mechanical parser (not LLM) — no metacharacters/substitution/newlines; first token allowlisted; forbid `sh`/`bash`/`zsh`/`python -c`; parse to argv **and** require `test_files` when tests are new. Fail → Task `FAIL`.

### task_gate deployment (external `.pipe` contract)

Product repo consumes a pinned revision of the external `.pipe` repository at `.pipe/`. The attachment mechanism is outside this skill.

```text
.pipe/aidesklab-factory-gates/{task_gate.sh,action_gate.sh,transition_guard.py}
```

This skill does **not** implement those scripts. Cron **must not** be enabled until production `task_gate.sh`:

1. accepts structured argv (`--acceptance-runner` + repeated `--acceptance-arg`, or `--acceptance-json`);
2. executes Verification **without** `bash -lc`, `eval`, or other shell interpretation;
3. implements the test-file overlay baseline algorithm below;
4. proves (or is accompanied by a provenance gate that proves) Task commit provenance;
5. is proven against the expanded 10-case gate suite below.

Describing the contract is not proof. A gate that still takes `--acceptance-cmd` and runs it via shell → Task `FAIL` / cron blocked. Do not work around that with a "safe string".

`make verify-fast` remains a **fixed** repository command (`--verify-cmd`). It is not Kaneo-dynamic Verification.

## 3. Branch policy (local vs remote)

After `git fetch <validated-remote>`. Names from Kaneo metadata / repo convention; fallback `outcome/<outcome-id>`, `task/<task-id>`. Never title-only. Validate names with `git check-ref-format` first.

| Remote Outcome | Local Outcome | Action |
|---|---|---|
| yes | yes | verify tracking relationship, reuse |
| yes | no | create local tracking remote |
| no | yes | verify expected origin, `git push -u <remote> <outcome-branch>` |
| no | no | create from remote default, then `git push -u` |

After any Outcome create/push:

```text
remote/<outcome-branch> resolves to expected SHA
```

Persist `outcome_remote`, `outcome_branch`, `outcome_base_sha`. Ambiguity or push/verify failure → Task `FAIL`.

**Create Task branch only after remote Outcome is confirmed.** Task missing → create from local Outcome; exists → reuse.

```text
fresh remote Outcome tip != pinned outcome_base_sha → Task FAIL
```

No auto-rebase. No auto-merge. A stale local Outcome tip is not this check. Re-fetch immediately before provenance / Task Gate.

Never Cursor on `main` / `master` / Outcome / another Task branch.

## 4. Action order

Sequential Kaneo order (or stable ID). No parallelism. Do not re-run `Done` Actions.

## 5. Running a single Action

`1 Action = 1 Target file = 1 commit`.

### 5.0 Orphan-commit reconciliation (before Cursor)

Search Task branch for `^action\(<ACTION_ID>\):`.

Current Action Gate API is `--before <sha> --file <file>` and checks `before_sha..HEAD`. Therefore a matching orphan commit that is **not** HEAD would pull later commits into the gate. Do **not** treat a mere ancestor as sufficient until the gate supports explicit `--commit <sha>` (future; not a usable path in this skill).

- **0 commits** → continue to Cursor.
- **1 commit AND that commit == current Task HEAD** → do **not** launch Cursor. Verify: non-merge; changes exactly Target file; parent as `before_sha`; Action Gate parent→HEAD; local subject MUST match. PASS → persist/reconstruct `AIDESKLAB_EXEC_EVIDENCE_V1` → `transition_guard` → Done. Fail checks → Action `FAIL`.
- **1 commit that is not HEAD**, or **>1** → Action `FAIL` (state conflict).

After Gate PASS + Kaneo write failure, the next cron **starts here** — never a second implementation commit.

### 5.1 Target file

Missing/ambiguous/multiple/forbidden/traversal → Action `FAIL`. Canonicalize to a repo-relative path inside the worktree.

### 5.2 Baseline SHA

`git rev-parse HEAD` → literal `before_sha`. After FAIL clear: HEAD must equal recorded `before_sha` **and** porcelain empty.

### 5.3 Prompt file (not the prompt API)

Write the full Action text plus envelope to `/tmp/aidesklab-actions/<task-id>/<action-id>.md` (**outside** the production repo). Envelope (semantic, not security): this Action only; Target file only; no `.pipe`/switch/rebase/merge/push/PR/Kaneo; exactly one commit; message **MUST** be `action(<ACTION_ID>): <short title>`.

### 5.4 Cursor prompt transport

Read the temp file and pass its **entire contents as one explicit prompt value** through the confirmed CLI interface of the installed `agent`. Documented print-mode:

```bash
agent -p --force --model auto "<entire Action + envelope>"
```

Invariant:

```text
Cursor receives exact complete prompt as one prompt value.
stdin redirection is not assumed to be the prompt API.
```

Do **not** use:

```bash
agent -p --force --model auto < /tmp/aidesklab-actions/.../action.md
```

Before enabling cron, confirm `agent --help` / vendor docs on the runner. If the confirmed interface is a different explicit-prompt flag or argv form, use that — still one prompt value, never stdin-as-API.

Do not use `cursor agent ... --trust`. `--force` makes project deny policy mandatory.

### 5.5 Temp prompt cleanup

After Cursor execution, delete `/tmp/aidesklab-actions/<task-id>/<action-id>.md` if it was created. Delete **independently of PASS/FAIL**. Cleanup must not affect Git recovery evidence (`before_sha`, `failed_head_sha`, commits). Do not leave Action prompt files on the runner indefinitely.

## 6. Action Gate

```bash
.pipe/aidesklab-factory-gates/action_gate.sh \
  --before "<actual-before-sha>" \
  --file "<Target file>"
```

Preferred extra (production gate dependency, implemented in source `.pipe`): `--action-id "<ACTION_ID>"` checking `^action\(<ACTION_ID>\):`. **This skill always checks HEAD subject locally before PASS.**

Exit code only. Then local marker check. Because orphan reconcile requires matching commit == HEAD, `--before..HEAD` contains exactly that one commit.

## 7. Action Gate PASS

```text
Action Gate PASS
→ local action(<ID>): MUST
→ HEAD_SHA
→ persist AIDESKLAB_EXEC_EVIDENCE_V1
→ transition_guard
→ Kaneo Done
```

Kaneo write fail: do not re-Cursor; next run = §5.0.

## 8. Action-level FAIL

Persist `AIDESKLAB_EXEC_FAILURE_V1` with `before_sha` + `failed_head_sha`. No hand-fix, no fake commit, no `reset --hard`.

## 9. Completing all Actions

All `Done`, valid evidence, clean tree, no Action `FAIL`. Else no Task Gate.

## 9a. Fresh remote Outcome before provenance / Task Gate

Immediately before provenance and Task Gate:

```text
git fetch <validated-remote>
```

Then compare:

```text
refs/remotes/<remote>/<outcome_branch>
```

with the pinned:

```text
outcome_base_sha
```

Invariant:

```text
fresh remote Outcome tip == pinned outcome_base_sha
```

If the SHA differs → Task `To Do` + `FAIL`. No auto-rebase. No auto-merge. A stale local Outcome branch is not sufficient: another Task may already have merged into remote Outcome.

## 9b. Task commit provenance (before Task Gate)

Mechanically list commits in `outcome_base_sha..Task HEAD` and prove:

```text
commits(outcome_base_sha..Task HEAD)
==
commit_sha of every Done Action
```

Required of every commit in the range:

- non-merge;
- subject matches `^action\(<ACTION_ID>\):`;
- Action ID unique in the range;
- `commit_sha` equals the Action's evidence;
- no commit without valid Action evidence;
- every Done Action is represented by exactly one commit.

Unknown / missing / extra commit → Task `To Do` + `FAIL`.

This check is an **external `.pipe` contract**: `task_gate.sh` may perform it, or a separate provenance gate may run immediately before Task Gate. The orchestrator must still refuse PR if provenance is not proven.

## 10. Mechanical Task Verification

If fresh remote Outcome tip != `outcome_base_sha` → Task `FAIL` (no sync). Provenance must already have passed. Overlay paths must already have passed the security boundary.

### Structured Task Gate CLI (external contract)

```bash
.pipe/aidesklab-factory-gates/task_gate.sh \
  --base "<Outcome branch>" \
  --verify-cmd "make verify-fast" \
  --acceptance-runner <runner> \
  --acceptance-arg <arg> \
  --acceptance-arg <arg> \
  --test-file <repo-relative-path> \
  [--support-file <repo-relative-path> ...]
```

Equivalent if the gate prefers JSON argv (still no shell interpretation):

```bash
.pipe/aidesklab-factory-gates/task_gate.sh \
  --base "<Outcome branch>" \
  --verify-cmd "make verify-fast" \
  --acceptance-json '["pytest","-q","tests/..."]' \
  --test-file <path>
```

Do **not** pass `--acceptance-cmd "<string>"` as the Verification interface.

Invariant:

```text
Kaneo structured argv
→ mechanical validation
→ task_gate structured argv
→ process execution without shell interpretation
```

### Fake-progress baseline algorithm (external contract for `task_gate.sh`)

Task may introduce new acceptance tests. Baseline must overlay **tests**, not production implementation:

0. Validate every overlay path with the overlay security boundary (canonical repo-relative; no `..` / absolute / symlink escape; not `.pipe/**` / `.git/**` / secrets; inside repo-defined test/fixture boundaries; not the current production Target file). Unclassifiable path → Task `FAIL`. Do not overlay by trusting Task text.
1. Create a temporary worktree on `outcome_base_sha` / `--base`.
2. Copy **only** `test_files` (and listed `support_files`) from the Task branch into that worktree. Do **not** copy production implementation.
3. Run structured Verification (argv) in the overlay worktree.
4. Require the test **runs** and ends in a real assertion/test failure.
5. Missing runner, missing test file (when it should have been overlaid), or setup/dependency failure → gate **FAIL** (not an expected red).
6. Run the same structured Verification on the Task branch and require **PASS**.
7. If baseline Verification **PASSES**, that is fake progress → gate **FAIL**.

Contract:

```text
Task test state + Outcome production state → test RUNS and FAILS
Task test state + Task production state    → test RUNS and PASSES
```

### Expanded 10-case gate suite (must be proven on production `task_gate.sh` before cron)

```text
1. Task PASS / baseline assertion FAIL
   → gate PASS

2. baseline test missing unexpectedly
   → gate FAIL

3. baseline runner missing
   → gate FAIL

4. baseline setup/dependency failure
   → gate FAIL

5. baseline test PASS
   → fake progress → gate FAIL

6. Task test FAIL
   → gate FAIL

7. new Task test overlaid onto Outcome production
   → test RUNS + real assertion FAIL on baseline
   → Task PASS
   → gate PASS

8. unknown Task commit without Action evidence
   → gate FAIL

9. overlay path points to production code, `.pipe`, secret,
   traversal, symlink escape or outside repo
   → gate FAIL

10. production Task Gate exposes only legacy
    shell-interpreted `--acceptance-cmd`
    → deployment preflight BLOCK
```

## 11–13. Task Gate / PR / In review

Gate fail → Task `FAIL`. Push fail / PR API fail / wrong base / `transition_guard` conflict → Task `FAIL`. PR: Task → Outcome; never merge.

## 14. Rework after review

Existing Task branch and PR; new Actions only; start each with §5.0. Review ≠ `FAIL`.

## Out of scope

Outcome execution/Review, semantic review, merge, rescue, adversary, decomposition, branch recovery, Outcome auto-sync. Implementing or patching `.pipe` scripts (separate repository / separate task).
