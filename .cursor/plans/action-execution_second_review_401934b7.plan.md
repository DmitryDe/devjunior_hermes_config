---
name: action-execution second review
overview: "Третий проход по skill `action-execution`: закрыть 4 блокера second-review (recovery после FAIL, FAIL на все deterministic stops, Outcome branch creation, контракт task_gate) плюс важные пункты 5–10 — точечно в трёх файлах skill, без смены архитектуры."
todos:
  - id: recovery-fail
    content: "Recovery after Action FAIL: before_sha/failed_head_sha + retry gate in invariants + SKILL/workflow"
    status: completed
  - id: preflight-fail
    content: Map all deterministic stops to Task/Action FAIL; remove bare stop loops
    status: completed
  - id: branch-policy
    content: Outcome/Task branch create+naming+pin outcome_base_sha
    status: completed
  - id: evidence-commit-boundary
    content: JSON evidence markers, commit action(ID), Target boundary, post-gate FAIL, partial write reconcile
    status: completed
  - id: task-gate-contract-platforms
    content: Document 6 task_gate test cases; platforms [linux]; bump 0.3.0; final consistency + report
    status: completed
isProject: false
---

# Доработка action-execution (second review)

Источник: [docs/action-execution-second-review.md](docs/action-execution-second-review.md). Scope — только skill:

- [skills/autonomous-ai-agents/action-execution/SKILL.md](skills/autonomous-ai-agents/action-execution/SKILL.md)
- [skills/autonomous-ai-agents/action-execution/references/workflow.md](skills/autonomous-ai-agents/action-execution/references/workflow.md)
- [skills/autonomous-ai-agents/action-execution/references/invariants.md](skills/autonomous-ai-agents/action-execution/references/invariants.md)

Язык: English. Архитектуру ролей не менять. Bump `version: 0.3.0`.

**`task_gate.sh`:** в этом репо `.pipe` нет — скрипт не правим. В skill зафиксировать 6 обязательных test cases (§4 review) как контракт для production repos; в отчёте явно: gate не верифицирован здесь.

**platforms:** убрать `macos` → `platforms: [linux]` (совместимость gates с Bash 3.2/macOS не подтверждена).

---

## 1. Recovery after Action FAIL (blocker)

В failure evidence всегда:

```text
before_sha
failed_head_sha
```

`before_sha` = last trusted baseline. После снятия `FAIL`:

- retry **запрещён**, пока `HEAD != recorded before_sha` (и нет отдельной recovery operation с новым trusted baseline);
- failed HEAD нельзя брать как новый baseline;
- cron **не** делает `git reset --hard` без отдельной recovery policy (failed branch оставлять для диагностики).

Описать state machine в `invariants.md` + кратко в Procedure SKILL.

## 2. FAIL на все deterministic stops (blocker)

Убрать «обычный stop» без FAIL там, где следующий cron повторит тот же failure.

| Failure | FAIL owner |
|---|---|
| zero Actions | Task |
| broken Outcome→Task→Action | Task |
| missing Verification | Task |
| missing `.pipe` gates | Task |
| missing `make verify-fast` | Task |
| Outcome branch unresolved/unsafe | Task |
| missing/ambiguous/multiple Target file | Action |
| malformed Action execution metadata | Action |
| Target file outside security boundary | Action |

Инвариант: *same state → same failure on next cron ⇒ must set FAIL*.

Обновить When to Use / preflight / Pitfalls — никаких «stop» без FAIL для этих кейсов.

## 3. Outcome / Task branch creation (blocker)

После `git fetch <remote>`:

1. Resolve remote default branch.
2. Outcome exists → reuse; missing → create from remote default.
3. Task missing → create from Outcome.
4. Names from Kaneo metadata / repo convention; fallback: `outcome/<outcome-id>`, `task/<task-id>`.
5. Persist actual branch names to Kaneo evidence/metadata.
6. Never use mutable title as sole branch id.

Pin after fetch: `outcome_base_ref`, `outcome_base_sha`. Before Task Gate: compare with current Outcome tip; drift → deterministic sync or Task `FAIL` (не молчать).

## 4. task_gate contract (blocker, docs-only here)

В `workflow.md` секция Mechanical Verification — явный checklist из 6 cases (PASS only when Task PASS + baseline ASSERTION FAIL; missing test/runner/deps → gate FAIL; fake progress / Task still red → gate FAIL).

## 5. Machine-readable evidence

Предпочитать Kaneo structured metadata. Иначе canonical comments:

```text
AIDESKLAB_EXEC_EVIDENCE_V1
{"action_id":"...","branch":"...","before_sha":"...","commit_sha":"...","target_file":"...","gate":"passed"}

AIDESKLAB_EXEC_FAILURE_V1
{"action_id":"...","before_sha":"...","failed_head_sha":"...",...}
```

Prose comments не достаточны для idempotence.

## 6. Commit marker Action ID

В execution envelope: commit message must include `action(<ACTION_ID>): <short title>`. Secondary reconciliation key. Если Action Gate умеет — проверять marker в HEAD (skill requirement; без правки скриптов в этом репо).

## 7. Partial Kaneo write after Gate PASS

Порядок:

```text
Action Gate PASS → HEAD_SHA → persist evidence → transition_guard → Kaneo Done
```

Если evidence/status update failed: не запускать Cursor снова; не создавать второй commit; next run reconciles Git/evidence/Kaneo; conflict → `FAIL`.

## 8. Post–Task Gate technical FAIL

Явно Task `FAIL` для: push failure, PR create/API failure, PR wrong base, `transition_guard` state conflict. Без бесконечного retry.

## 9. Target file security boundary

Перед Cursor reject:

```text
.pipe/**
.git/**
credential/secret files
repo-defined forbidden paths (AGENTS.md / policy)
```

→ Action `FAIL`.

## 10. Распределение по файлам

**SKILL.md:** FAIL-on-preflight, branch create/naming, recovery retry gate, evidence markers, commit marker, Target boundary, push/PR FAIL, pin Outcome SHA, platforms/linux, version 0.3.0.

**workflow.md:** полный алгоритм §§1–3 + recovery, branch policy, evidence formats, partial write reconcile, post-gate FAIL, Target boundary, Outcome pin, task_gate 6 cases.

**invariants.md:** recovery state machine, deterministic-stop→FAIL table, evidence format, prohibitions (no blind reset, no prose-only evidence), updated DoD if needed.

## Отчёт после реализации (по промпту review)

1. Изменённые файлы  
2. Failure/recovery state machine  
3. Подтверждение: нет deterministic stop без FAIL  
4. Branch creation policy  
5. Canonical evidence format  

(и отдельно: `task_gate.sh` не менялся / не верифицирован в этом репо)
