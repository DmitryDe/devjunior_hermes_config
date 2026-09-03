---
name: action-execution third review
overview: "Четвёртый проход skill `action-execution` по third-review: remote Outcome, orphan-commit reconcile, trusted recovery (HEAD+clean WT), allowlisted Verification, Cursor permission policy, Outcome drift = FAIL only. Без смены архитектуры; `task_gate.sh` не правим."
todos:
  - id: remote-outcome
    content: Remote Outcome 4-state + push before Task; pin outcome_remote/branch/sha
    status: completed
  - id: orphan-reconcile
    content: Orphan-commit reconcile before Cursor; marker MUST; local gate check
    status: completed
  - id: recovery-drift
    content: Recovery = HEAD==before_sha AND clean porcelain; Outcome drift=FAIL only
    status: completed
  - id: verify-cursor-prereq
    content: Allowlisted Verification argv + Cursor cli.json prerequisite + cron/task_gate note
    status: completed
  - id: version-report
    content: Bump 0.4.0; consistency check; report per third-review prompt
    status: completed
isProject: false
---

# Доработка action-execution (third review)

Источник: [docs/action-execution-third-review.md](docs/action-execution-third-review.md).

Scope — только:

- [skills/autonomous-ai-agents/action-execution/SKILL.md](skills/autonomous-ai-agents/action-execution/SKILL.md)
- [skills/autonomous-ai-agents/action-execution/references/workflow.md](skills/autonomous-ai-agents/action-execution/references/workflow.md)
- [skills/autonomous-ai-agents/action-execution/references/invariants.md](skills/autonomous-ai-agents/action-execution/references/invariants.md)

Язык: English. Роли не менять. Bump `version: 0.4.0`.

Не трогать: SOUL, config, semantic review/merge/rescue/decomposition/branch recovery.

**`task_gate.sh` / `action_gate.sh`:** в этом репо нет `.pipe`. Скрипты не правим. В skill: (a) `--action-id` как required dependency на production gate + **local MUST check** commit marker before PASS; (b) 6-case contract + explicit prerequisite «cron запрещён, пока 6 cases не подтверждены на production `task_gate.sh`».

---

## 1. Remote Outcome before Task (blocker)

В `workflow.md` / SKILL заменить «Outcome exists → reuse» на 4-state machine:

| Remote | Local | Action |
|---|---|---|
| yes | yes | verify relationship, reuse |
| yes | no | create local tracking remote |
| no | yes | verify expected origin, `git push -u` |
| no | no | create from remote default, then `git push -u` |

После push Outcome: remote ref must resolve to expected SHA. Persist `outcome_remote`, `outcome_branch`, `outcome_base_sha`. **Task branch only after remote Outcome confirmed.** Create/push/verify failure → Task `FAIL`.

## 2. Orphan-commit reconciliation before Cursor (blocker)

Перед каждым Cursor на unfinished Action (и после partial Kaneo write):

```text
search Task branch for commits matching action(<ACTION_ID>):
```

- **0** → normal Cursor path  
- **1** → no Cursor; verify ancestor of HEAD, non-merge, exactly Target file; `before_sha` = parent; Action Gate parent→commit; PASS → reconstruct `AIDESKLAB_EXEC_EVIDENCE_V1` → guard → Done  
- **>1** → Action `FAIL` (state conflict)

Commit marker `action(<ACTION_ID>):` = **MUST**. Skill: local subject check before accepting PASS. Document preferred `action_gate.sh --action-id` as external dependency.

## 3. Trusted recovery = HEAD + clean WT (blocker)

После снятия Action FAIL:

```text
HEAD == recorded before_sha
AND git status --porcelain is empty
```

Else → Action `FAIL` again (including dirty WT with HEAD==before_sha). No auto cleanup. Update SKILL When to Use / Procedure + invariants recovery section.

## 4. Verification: no unrestricted shell (blocker)

Remove «blacklist `;|&` enough» as security model.

**Preferred contract** in skill:

```yaml
Verification:
  runner: <allowlisted>
  args: [...]
```

Runners from repo/`AGENTS.md` allowlist; argv, **no** `bash -lc`.

**Transitional string format:** mechanical parser — forbid metacharacters/substitution/newlines; first token allowlisted executable; forbid `sh`/`bash`/`zsh`/`python -c` escape hatches; parse to argv. Validation fail → Task `FAIL`. Validation is mechanical, not LLM judgment.

## 5. Cursor mechanical permissions (blocker)

Prerequisite: production repo has approved Cursor CLI permission/sandbox policy (e.g. `.cursor/cli.json` or version-equivalent). Absence → Task `FAIL`.

Policy must deny at least: write `.pipe/**`, secrets, `git push`, `gh`/PR, unneeded network/MCP. Must allow: edit Target file, read needed context, allowed tests/tools, **local** commit. Envelope remains semantic only, not the security boundary.

## 6. Outcome drift = FAIL only (important)

Replace «deterministic sync OR FAIL» with:

```text
current Outcome tip != pinned outcome_base_sha → Task FAIL
```

No auto-rebase/merge. Sync = future separate workflow. Update invariants FAIL table (remove «without deterministic sync» wording).

## 7. Partial Kaneo write (explicit next-run)

After Gate PASS + Kaneo write fail: next cron **must** run orphan-commit reconciliation (§2) first; never re-Cursor while matching commit exists and can be gate-confirmed.

## 8. File split

**SKILL.md:** prerequisites (Cursor policy, task_gate cron gate, Verification contract); branch remote machine; recovery HEAD+clean; orphan-reconcile before Cursor; Outcome drift FAIL; version 0.4.0.

**workflow.md:** full branch 4-state + push Outcome; orphan algorithm; recovery; Verification; Cursor policy; drift; post-gate FAIL list unchanged; 6-case + cron blocker note.

**invariants.md:** recovery trusted state; orphan reconcile; Verification prohibitions; no Outcome auto-sync; evidence/marker MUST; Cursor policy prerequisite.

## Отчёт после реализации

1. Изменённые файлы  
2. Local/remote branch state machine  
3. Orphan-commit reconciliation  
4. Trusted recovery condition  
5. Verification contract  
6. Cursor permission prerequisite  
7. Outcome drift always FAIL (no auto-sync)  
8. `task_gate.sh` / `action_gate.sh` не менялись; cron blocked until 6-case proof on production gate
