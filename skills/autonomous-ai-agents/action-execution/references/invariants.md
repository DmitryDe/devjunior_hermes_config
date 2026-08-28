# Action Execution — invariants

## FAIL semantics

`FAIL` is a Kaneo **label**, not a status. Do not create a `Failed` status.

```text
To Do without FAIL = may auto-execute
To Do + FAIL       = auto-execution forbidden
```

If the next cron-run on unchanged state is guaranteed to hit the same failure, **must set FAIL**. There is no bare deterministic `stop` that leaves a runnable `To Do`.

### Anti-loop

Every run starts with: Task has `FAIL`? Any child Action has `FAIL`? If yes: no Cursor, no gate retry, no new commits, no PR, skip.

### Deterministic-stop → FAIL

| Failure | FAIL owner |
|---|---|
| zero Actions | Task |
| broken Outcome→Task→Action hierarchy | Task |
| missing / invalid Verification (not structured allowlisted argv; missing `test_files` when tests are new) | Task |
| invalid overlay `test_files` / `support_files` (traversal, absolute, symlink escape, `.pipe/**`, `.git/**`, secrets, outside test/fixture boundary, or current Target file) | Task |
| production Task Gate interprets Verification as a shell string (`--acceptance-cmd` / `bash -lc` / `eval`) | Task |
| missing `.pipe/aidesklab-factory-gates` gates | Task |
| missing `make verify-fast` | Task |
| missing Cursor CLI policy **or** required effective deny / sandbox mismatch | Task |
| invalid branch name (`git check-ref-format`) or remote not configured | Task |
| Outcome remote publish / verify failure | Task |
| Outcome tip != pinned `outcome_base_sha` (fresh remote ref after `git fetch`) | Task |
| Task commit provenance mismatch (`commits(base..HEAD)` != Done Action evidence set) | Task |
| push / PR API / PR wrong base / transition_guard conflict | Task |
| missing / ambiguous / multiple Target file | Action |
| malformed Action execution metadata / invalid Action ID format | Action |
| Target file outside security boundary or path traversal | Action |
| Cursor / Action Gate / dirty tree / wrong files | Action |
| Action ↔ Git state conflict / >1 `action(<ID>):` commits / matching commit != Task HEAD | Action |
| FAIL-cleared retry with dirty worktree or HEAD != before_sha | Action |

### Recovery after Action FAIL

Failure evidence always includes `before_sha` and `failed_head_sha`. `before_sha` is the last **trusted baseline**. Failed HEAD is diagnostic only.

After `FAIL` is cleared, retry Cursor **only if all** of:

```text
HEAD == recorded before_sha
AND git status --porcelain is empty
```

(or a **separate** recovery operation out of this skill recorded a new trusted baseline **and** the worktree is clean).

HEAD == `before_sha` but worktree/index/untracked dirty → Action `To Do` + `FAIL` again. Do not auto-delete failed artifacts. Cron must **not** `git reset --hard`.

```text
trusted baseline A
→ Cursor produces invalid B or dirty tree
→ Action To Do + FAIL  (before_sha=A, failed_head_sha=...)
→ FAIL cleared
→ retry only if HEAD==A AND porcelain empty
```

### Orphan-commit reconciliation

Before **every** Cursor launch on an unfinished Action (including after Kaneo evidence/status write failure):

```text
search Task branch for commits whose subject matches ^action\(<ACTION_ID>\):
```

Action Gate currently checks `before_sha..HEAD`. A matching commit that is not HEAD would include later commits. Until the gate supports explicit `--commit <sha>`, only HEAD is acceptable.

| Matches | Action |
|---|---|
| 0 | normal Cursor path |
| 1 **and** commit == Task HEAD | **do not** launch Cursor; verify non-merge, exactly Target file; parent = `before_sha`; Action Gate parent→HEAD; local subject MUST match `action(<ID>):`; PASS → reconstruct `AIDESKLAB_EXEC_EVIDENCE_V1` → `transition_guard` → Done |
| 1 and commit != HEAD, or >1 | Action `FAIL` (state conflict) |

Commit marker `action(<ACTION_ID>):` is **MUST**. Prefer production `action_gate.sh --action-id <ACTION_ID>` (external `.pipe` dependency). Regardless of gate version, this skill **must** check HEAD subject locally before accepting PASS.

### Task commit provenance

Before Task Gate / PR:

```text
commits(outcome_base_sha..Task HEAD) == commit_sha of all Done Actions
```

Every commit: non-merge; `^action\(<ID>\):`; unique Action ID; SHA matches evidence; no unknown commits; every Done Action exactly once.

Mismatch → Task `To Do` + `FAIL`.

### Action-level FAIL / Task-level FAIL

Action: `To Do` + `FAIL`; Task stays `To Do`. Stop cycle. No next Action. No PR.

Task: `To Do` + `FAIL`.

Review return (`In review → To Do` + new Actions) is **not** `FAIL`. `transition_guard.py` authorizes status only.

## Evidence format

Prefer Kaneo structured metadata. Comments must be versioned JSON. Prose is not idempotence evidence.

```text
AIDESKLAB_EXEC_EVIDENCE_V1
{"action_id":"...","branch":"...","before_sha":"...","commit_sha":"...","target_file":"...","gate":"passed"}

AIDESKLAB_EXEC_FAILURE_V1
{"action_id":"...","branch":"...","before_sha":"...","failed_head_sha":"...","target_file":"...","failure_stage":"...","gate_exit_code":"...","error":"..."}
```

Also persist Outcome pin: `outcome_remote`, `outcome_branch`, `outcome_base_sha`.

Git identity MUST: `action(<ACTION_ID>): <short title>`.

## Idempotence

Reconcile Kaneo and Git first. After Action Gate PASS + Kaneo write failure: next run **must** run orphan-commit reconciliation first; never re-Cursor while a matching confirmable **HEAD** commit exists.

State conflicts → `FAIL`: Done without commit; commit not on Task branch; matching orphan commit != HEAD; In review without PR; PR wrong base; missing expected commits; unknown commits without Action evidence; HEAD/worktree not trusted after FAIL clear; >1 marker commits.

## Verification contract

`Verification` is **not** an unrestricted shell string. Blacklisting `; | rm curl` is **not** a security model. `--acceptance-cmd` is **not** this skill's interface.

Required:

```yaml
Verification:
  runner: <allowlisted>
  args: [<arg>, ...]
  test_files: [<repo-relative path>, ...]
  support_files: [<path>, ...]
```

`test_files` required when the Task creates or extends acceptance tests. `support_files` lists fixtures/helpers to overlay with those tests. Every overlay path must pass the same mechanical security boundary as Target file **and** must not be the current production Action Target file. Unclassifiable path → Task `FAIL`. Do not overlay by trusting Task text.

Runners from repo / `AGENTS.md` allowlist (`pytest`, `pnpm`, `npm`, `cargo`, `make`, …). Pass as **argv** through Task Gate (`--acceptance-runner` + `--acceptance-arg`, or `--acceptance-json`). **Never** `bash -lc`, `eval`, or other shell interpretation of Kaneo Verification.

Transitional string: mechanical parser only (not LLM). Forbid metacharacters, substitution, newlines; first token allowlisted executable; forbid `sh`/`bash`/`zsh`/`python -c` escape hatches; parse to argv. Validation failure → Task `FAIL`.

Fake-progress baseline:

```text
Task test files (+ support_files) + Outcome production → RUNS + FAILS
Task test files (+ support_files) + Task production    → RUNS + PASSES
```

Missing runner / missing test / setup failure is a gate failure, not expected red.

## Cursor prompt transport

```text
Cursor receives exact complete prompt as one prompt value.
stdin redirection is not assumed to be the prompt API.
```

Temp prompt files stay outside the production repo. Orchestrator reads the file and passes contents via the confirmed `agent` CLI (`agent -p "<prompt>"` or equivalent explicit mechanism). After Cursor execution, delete `/tmp/aidesklab-actions/<task-id>/<action-id>.md` if created, independently of PASS/FAIL. Cleanup must not affect Git recovery evidence.

## Cursor permission prerequisite

Execution envelope is semantic only, not a security boundary. Production repo **must** have an approved Cursor CLI permission policy **and** the required **effective** deny set (`.cursor/cli.json` or version-equivalent). File presence alone is insufficient. Absence or mismatch → Task `FAIL`.

Deny at least: write `.pipe/**`, secrets/credentials/`.env`/keys, `git push`, `gh`/PR, unneeded network/MCP/WebFetch. Allow: edit Target file, read needed context, allowed tests/tools, **local** git commit. Do not ban all `git`.

Permissions and sandbox are separate layers; if the factory requires sandbox policy, validate that config separately.

## Outcome drift

Immediately before provenance / Task Gate: `git fetch <validated-remote>`, then compare `refs/remotes/<remote>/<outcome_branch>` with pinned `outcome_base_sha`.

```text
fresh remote Outcome tip == pinned outcome_base_sha
```

If the SHA differs → Task `To Do` + `FAIL`. No auto-rebase. No auto-merge. A stale local Outcome tip is not this check. Synchronization is a future separate workflow.

## Dynamic input validation

Before subprocess/git operations:

- branch → `git check-ref-format`;
- remote → only a configured git remote;
- Action ID → factory ID format;
- Target file → canonical repo-relative path, no traversal, security policy;
- `test_files` / `support_files` → canonical repo-relative; no `..` / absolute / symlink escape; not `.pipe/**` / `.git/**` / secrets; inside repo-defined test/fixture boundaries; not the current production Target file.

Invalid → corresponding `FAIL`. Prefer argv over shell interpolation.

## External `.pipe` contract

Product repo consumes a pinned revision of the external `.pipe` repository at `.pipe/`. The attachment mechanism is outside this skill. Gates live at `.pipe/aidesklab-factory-gates/`. This skill documents the required gate behaviour; it does not ship or patch those scripts.

Cron stays blocked until production `task_gate.sh` (and Action Gate as needed) implements structured argv, overlay baseline, provenance, and the expanded 10-case gate suite.

## Prohibitions

`devJunior` must not: write production code; edit Cursor output; skip Cursor when 0 marker commits; re-Cursor when 1 valid **HEAD** marker commit exists; treat a non-HEAD ancestor marker as reconciled; parallel Actions; multi-file/multi-commit Actions; trust Cursor text; ignore gate exit codes; Done without gate + evidence; PR without provenance + Task Gate; merge; Cursor on Outcome/`main`; duplicate PR; change Goal/Verification/Action text; auto-clear `FAIL`; treat failed HEAD as baseline; destructive reset; shell-var `BEFORE_SHA`; prompt files in production repo; leave `/tmp` Action prompts after Cursor; assume stdin redirection is the Cursor prompt API; `cursor agent ... --trust`; prose-only evidence; Target under `.pipe/**` / `.git/**` / secrets / traversal; overlay `test_files`/`support_files` by trusting Task text; overlay production Target file; Outcome auto-sync; treat a stale local Outcome tip as the drift check; execute Verification via shell interpretation; pass `--acceptance-cmd` as the Verification interface; treat envelope as the only Cursor control; enable cron before production `.pipe` proves the expanded 10-case + structured-argv contract.

## Failure policy

```text
not proven mechanically = not done
same state → same failure on next cron ⇒ FAIL
```

Keep valid gate-passed commits. Persist machine-readable failure evidence. No destructive reset.

## Definition of Done for devJunior

```text
all Actions = Done
AND every Action has valid machine-readable commit evidence
AND every Action passed Action Gate
AND Task commit set == validated Done Action commit set
AND Task Gate = 0
AND Task branch pushed
AND correct PR Task → Outcome exists
AND transition_guard allowed the transition
AND Task = In review
AND no FAIL labels remain on Task or child Actions
```

`Task Done` is not `devJunior`'s responsibility.

## Core invariant

```text
Cursor writes code.
devJunior orchestrates.
Cursor prompt = one explicit prompt value (not stdin-as-API).
Git proves commits (action(<ID>): MUST; matching orphan == HEAD).
Action Gate proves Action atomicity (before..HEAD = that one commit).
Task provenance: commit set == Done Action evidence set.
Task Gate proves mechanical Task readiness (structured argv, overlay baseline).
Verification never goes through shell interpretation.
FAIL prevents automatic retry loops.
Trusted retry = HEAD==before_sha AND clean worktree.
Remote Outcome exists before Task execution.
Outcome drift → Task FAIL (fresh remote tip; no auto-sync).
Effective Cursor deny policy is the security boundary.
Overlay paths have a mechanical security boundary (not Task-text trust).
PR hands the Task to devMaster.
devMaster performs semantic review and merge.
```
