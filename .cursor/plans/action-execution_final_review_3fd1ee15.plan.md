---
name: action-execution final review
overview: "Пятый точечный патч skill `action-execution` (v0.5.0) по final-review: закрыть 3 блокера и hardening в трёх skill-файлах; production `.pipe` гейты не трогать — зафиксировать как обязательный внешний контракт по пути `.pipe/aidesklab-factory-gates/`."
todos:
  - id: prompt-transport
    content: "Cursor: explicit prompt value; forbid stdin-as-API assumption"
    status: completed
  - id: verification-schema
    content: Verification runner/args/test_files/support_files + structured task_gate CLI contract
    status: completed
  - id: baseline-orphan-prov
    content: Baseline overlay algorithm; orphan==HEAD; Task provenance; 8-case suite
    status: completed
  - id: validation-cursor-policy
    content: Dynamic input validation + Cursor effective deny policy preflight
    status: completed
  - id: version-report
    content: Bump 0.5.0; consistency; report per final-review prompt
    status: completed
isProject: false
---

# Доработка action-execution (final review)

Источник: [docs/action-execution-final-review.md](docs/action-execution-final-review.md).

## Scope

Только:

- [skills/autonomous-ai-agents/action-execution/SKILL.md](skills/autonomous-ai-agents/action-execution/SKILL.md)
- [skills/autonomous-ai-agents/action-execution/references/workflow.md](skills/autonomous-ai-agents/action-execution/references/workflow.md)
- [skills/autonomous-ai-agents/action-execution/references/invariants.md](skills/autonomous-ai-agents/action-execution/references/invariants.md)

Язык: English. Архитектуру/роли не менять. Bump `version: 0.5.0`.

**Вне scope:** любой поиск/clone/правка `.pipe`, `task_gate.sh`, `action_gate.sh`, product repos, SOUL, config, merge/review/rescue/decomposition.

Путь гейтов в skill — только repo-relative:

```text
.pipe/aidesklab-factory-gates/{task_gate.sh,action_gate.sh,transition_guard.py}
```

Все требования к реализации гейтов — **обязательный внешний контракт / prerequisite**: cron запрещён, пока production `.pipe` не реализует и не докажет контракт. Факт правки `.pipe` — отдельная задача.

---

## 1. Cursor prompt transport (blocker)

Убрать из How to Run / workflow пример stdin-редиректа:

```bash
agent -p --force --model auto < /tmp/.../action.md
```

Зафиксировать:

1. Полный Action + envelope пишутся во временный файл вне repo (`/tmp/aidesklab-actions/...`).
2. Оркестратор читает файл и передаёт содержимое как **один явный prompt value** через подтверждённый CLI интерфейс установленного `agent` (документированный print-mode: `agent -p "<prompt>" --force --model auto`).
3. Инвариант: `stdin redirection is not assumed to be the prompt API`.
4. Перед cron: локально подтвердить `agent --help` / docs; если интерфейс другой — использовать тот подтверждённый механизм, но всегда один prompt value.

---

## 2. Structured Verification end-to-end (blocker)

Убрать skill-контракт `--acceptance-cmd "<argv-safe string>"` как достаточный.

**Kaneo Verification schema:**

```yaml
Verification:
  runner: <allowlisted>   # pytest, pnpm, npm, cargo, make, …
  args: [<arg>, ...]
  test_files: [<repo-relative path>, ...]   # required when Task creates/extends tests
  support_files: [<path>, ...]              # optional fixtures/helpers
```

**Вызов Task Gate (целевой внешний контракт):**

```bash
.pipe/aidesklab-factory-gates/task_gate.sh \
  --base "<Outcome>" \
  --verify-cmd "make verify-fast" \
  --acceptance-runner <runner> \
  --acceptance-arg <arg> ... \
  --test-file <path> ... \
  [--support-file <path> ...]
```

Альтернатива в том же контракте: `--acceptance-json '["runner","arg",...]'` — допустима, если gate запускает argv без shell.

Инвариант цепочки:

```text
Kaneo structured argv → mechanical validation → task_gate structured argv
→ process exec without bash -lc / eval / shell interpretation
```

`make verify-fast` остаётся отдельной фиксированной repository command (может остаться как `--verify-cmd`, т.к. это не Kaneo-динамическая Verification).

В skill: если production gate ещё на старом `--acceptance-cmd` + `bash -lc` — **Task FAIL / cron blocked**; не эмулировать shell-safe string.

---

## 3. Новые acceptance tests / baseline overlay (blocker)

Разрешить Task создавать новые acceptance tests.

**Baseline algorithm (контракт для `task_gate.sh`):**

1. Temporary worktree на `outcome_base_sha` / `--base`.
2. Overlay **только** `test_files` (+ `support_files`) из Task branch — не production implementation.
3. Запуск structured Verification → must **RUN and assertion/test FAIL**.
4. Missing test / missing runner / setup failure → gate FAIL (не «ожидаемый red»).
5. Тот же Verification на Task branch → must PASS.
6. Baseline PASS → fake-progress FAIL.

Контракт:

```text
Task test state + Outcome production → RUNS + FAILS
Task test state + Task production    → RUNS + PASSES
```

Расширить fake-progress suite в skill (cron blocked until proven on production gate):

```text
1. Task PASS / baseline assertion FAIL → PASS
2. baseline test missing unexpectedly → FAIL
3. baseline runner missing → FAIL
4. baseline setup failure → FAIL
5. baseline test PASS → fake progress FAIL
6. Task test FAIL → FAIL
7. new Task test overlaid onto Outcome production → real assertion FAIL
8. unknown Task commit without Action evidence → FAIL
```

---

## 4. Orphan reconciliation = HEAD only (hardening)

Заменить «ancestor of Task HEAD» на:

```text
exactly 1 matching action(<ID>): commit AND commit == Task HEAD
```

Иначе Action `FAIL` (state conflict). Не принимать обычный ancestor, пока Action Gate не поддерживает explicit `--commit <sha>` (будущее; сейчас не требуется в skill как usable path).

Action Gate вызов остаётся `--before` + `--file`; local MUST subject check. Preferred external: `--action-id` (dependency).

---

## 5. Task commit provenance (hardening)

Перед Task Gate (оркестратор + контракт gate):

```text
commits(outcome_base_sha..Task HEAD) == commit_sha всех Done Actions
```

Механически:

- каждый commit non-merge;
- subject `^action\(<ID>\):`;
- ID уникален;
- `commit_sha` совпадает с evidence;
- нет unknown commits;
- каждый Done Action ровно один commit.

Расхождение → Task `To Do` + `FAIL`. Можно жить в `task_gate.sh` или отдельном provenance gate — в skill описать как обязательную проверку перед PR.

---

## 6. Dynamic input validation

Перед subprocess/git:

- branch → `git check-ref-format`;
- remote → только configured remote;
- Action ID → fixed ID-format;
- Target file → canonical repo-relative, no traversal, security boundary.

Invalid → соответствующий FAIL. Subprocess предпочтительно argv, не shell interpolation.

---

## 7. Cursor effective permission policy

Preflight: не только existence `.cursor/cli.json`.

Механически проверить required effective deny (минимум):

- deny Write(`.pipe/**`);
- deny secrets / `.env` / keys;
- deny `gh` / PR;
- deny `git push` (не весь git — local commit allowed);
- deny ненужные MCP / WebFetch.

Permissions и sandbox — разные слои; если фабрика требует sandbox — проверять sandbox config отдельно. Absence/mismatch → Task `FAIL`.

---

## 8. File split

**SKILL.md:** version 0.5.0; prompt transport; Verification schema + structured gate CLI; orphan=HEAD; provenance; input validation; Cursor effective policy; cron blocked until 8-case + structured argv proven on production `.pipe`; paths `.pipe/aidesklab-factory-gates/...`.

**workflow.md:** source = final-review; полные алгоритмы §§1–7; убрать `--acceptance-cmd`; baseline overlay; expanded suite; external `.pipe` contract note («implement in source `.pipe` repo; product consumes submodule»).

**invariants.md:** FAIL rows для invalid Verification/provenance/orphan-not-HEAD/bad inputs/Cursor policy mismatch; Verification schema; provenance invariant; orphan HEAD-only; no stdin-as-prompt-API; gate shell-interpretation prohibition.

---

## Отчёт после реализации (в ответе агенту)

1. Изменённые файлы  
2. Новый Verification schema  
3. Fake-progress baseline algorithm  
4. Task provenance algorithm  
5. Подтверждение: Verification без shell interpretation (контракт)  
6. Orphan = HEAD согласован с Action Gate `--before`/`--file` (без `--commit`)  
7. Gate test cases (контракт; `.pipe` не менялся / не прогонялся здесь)
