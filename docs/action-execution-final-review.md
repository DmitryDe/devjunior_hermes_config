# Action Execution — заключительный раунд ревью

## Вердикт

**Статус: CONDITIONAL APPROVE.**

Версия `0.4.0` уже архитектурно целостна. Предыдущие критичные замечания закрыты: `FAIL` работает как anti-loop label; retry опирается на trusted `before_sha`; Outcome branch создаётся и публикуется; Outcome drift блокируется; orphan-commit reconciliation предотвращает повторный Cursor; Action↔commit имеет обязательный marker; evidence machine-readable; Cursor permissions признаны механической границей; Verification больше не должна быть произвольной shell-строкой; merge остаётся вне ответственности `devJunior`.

До включения cron остаются **3 обязательных интерфейсных исправления** и **2 hardening-пункта**. После них я бы считал skill готовым и следующий review делал уже по реальному trace первой Task, а не по тексту skill.

---

# BLOCKER 1 — передача prompt в Cursor CLI

Сейчас workflow показывает:

```bash
agent -p --force --model auto < /tmp/aidesklab-actions/<task-id>/<action-id>.md
```

Не следует предполагать, что stdin-redirection является prompt API Cursor CLI. Контракт skill должен использовать подтверждённый интерфейс: полный Action + execution envelope передаются как **один явный prompt value** через поддерживаемый CLI-механизм.

Временный файл можно оставить в `/tmp`, но оркестратор должен прочитать его содержимое и передать Cursor как единый prompt argument либо использовать другой подтверждённый локальным `agent --help` интерфейс.

Инвариант:

```text
Cursor receives exact complete prompt as one prompt value.
stdin redirection is not assumed to be the prompt API.
```

---

# BLOCKER 2 — Verification пока argv только на уровне текста skill

Skill правильно требует structured Verification, например:

```yaml
Verification:
  runner: pytest
  args:
    - -q
    - tests/auth/test_login.py::test_invalid_token
```

Но Task Gate вызывается через:

```text
--acceptance-cmd "<argv-safe Verification>"
```

Если `task_gate.sh` внутри снова использует `bash -lc`, `eval` или другую shell interpretation, защита исчезает.

## Требуемое исправление

Сделать interface Task Gate структурированным end-to-end. Например:

```text
--acceptance-runner pytest
--acceptance-arg -q
--acceptance-arg tests/auth/test_login.py::test_invalid_token
```

или:

```text
--acceptance-json '["pytest","-q","tests/..."]'
```

Gate обязан запускать Verification как argv, а не как shell program.

Инвариант:

```text
Kaneo structured argv
→ mechanical validation
→ task_gate structured argv
→ process execution without shell interpretation
```

`make verify-fast` может оставаться отдельной фиксированной repository command.

---

# BLOCKER 3 — fake-progress contract не определяет новые acceptance tests

Текущий контракт требует:

```text
Task branch acceptance PASS
Outcome baseline acceptance assertion FAIL
```

и правильно не считает `test file missing` валидным красным тестом.

Но текущая фабрика допускает Action, который **создаёт новый test file**. Тогда на Outcome baseline теста закономерно нет, и любой корректный Task с новым тестом будет заблокирован.

## Рекомендуемый контракт

Разрешить Task создавать acceptance tests и расширить Verification:

```yaml
Verification:
  runner: pytest
  args:
    - -q
    - tests/auth/test_login.py::test_invalid_token
  test_files:
    - tests/auth/test_login.py
```

Baseline-check должен:

1. создать temporary worktree на `outcome_base_sha`;
2. взять **только** `test_files` из Task branch;
3. не переносить production implementation;
4. запустить structured Verification;
5. потребовать настоящий assertion/test failure;
6. затем запустить тот же Verification на Task branch и потребовать PASS.

Контракт:

```text
Task test state + Outcome production state → test RUNS and FAILS
Task test state + Task production state    → test RUNS and PASSES
```

Если нужны новые fixtures/helpers, они также должны быть перечислены явно, например в `support_files`.

Альтернатива — запретить новые acceptance tests и требовать, чтобы Verification ссылалась только на тест, уже существующий в Outcome branch. Для текущей модели это менее удобно, поэтому рекомендован вариант выше.

---

# HARDENING 1 — orphan commit должен быть HEAD либо gate должен принимать target SHA

Сейчас orphan reconciliation допускает один matching commit, который просто является ancestor Task HEAD.

Но текущий Action Gate интерфейс:

```bash
action_gate.sh --before <sha> --file <file>
```

обычно проверяет диапазон `before_sha..current HEAD`. Если matching orphan commit не является HEAD, в gate попадут последующие commits.

Для текущего sequential workflow достаточно потребовать:

```text
matching orphan commit == current Task HEAD
```

Если matching commit не HEAD:

```text
Action FAIL / state conflict
```

В будущем Action Gate можно расширить explicit `--commit <sha>`, но сейчас это необязательно.

---

# HARDENING 2 — перед Task Gate доказать полный commit provenance

Каждый Action отдельно имеет evidence, но перед PR нужно доказать ещё один глобальный инвариант:

```text
в Task branch нет неизвестных implementation commits
```

Перед Task Gate механически получить commits диапазона:

```text
outcome_base_sha..Task HEAD
```

И доказать:

- каждый commit non-merge;
- каждый commit соответствует ровно одному Done Action;
- subject соответствует `action(<ACTION_ID>):`;
- `commit_sha` совпадает с evidence;
- Action ID уникален;
- нет commits без валидного Action evidence;
- каждый Done Action представлен ровно одним commit.

Итоговый инвариант:

```text
Task commit set == validated Done Action commit set
```

Расхождение → `Task To Do + FAIL`.

Эту проверку можно добавить в `task_gate.sh` или вынести в отдельный provenance gate.

---

# Дополнительный security hardening

Динамические значения Kaneo должны обрабатываться как данные, не shell syntax:

- branch names → валидировать через `git check-ref-format`;
- remote → только реально настроенный git remote;
- Action ID → валидировать фиксированным ID-format;
- Target file → canonical repo-relative path, no traversal;
- subprocess предпочтительно запускать argv, а не shell interpolation.

Невалидное значение → соответствующий `FAIL`.

---

# Cursor permission policy

Текущий skill правильно перестал считать execution envelope security boundary. Но preflight должен проверять не только существование `.cursor/cli.json`, а наличие требуемой effective deny policy.

Минимально обеспечить:

```text
deny Write(.pipe/**)
deny secrets / .env / keys
deny gh / PR operations
deny git push, но не весь git — Cursor обязан сделать local commit
deny ненужные MCP / WebFetch
```

Permissions и sandbox — разные слои. Если фабрика требует sandbox policy, проверять соответствующий sandbox config отдельно.

---

# Финальный DoD для включения cron

```text
[ ] Cursor prompt передаётся через подтверждённый CLI prompt interface
[ ] Verification structured argv проходит end-to-end без shell interpretation
[ ] реализован baseline-контракт для новых acceptance tests
[ ] orphan reconciliation принимает только HEAD либо gate умеет explicit target SHA
[ ] Task commit provenance == Done Action evidence set
[ ] task_gate.sh проходит расширенный fake-progress test suite
[ ] Cursor effective permission policy механически валидируется
[ ] один ручной Task проходит весь путь до In review
```

После выполнения этих пунктов **Action Execution skill можно считать завершённым**. Следующий review следует проводить уже по логам/trace реального пилотного Task.

---

# Итоговый промт агенту

Обнови `action-execution` финальным точечным патчем. Архитектуру и scope не менять.

Работай с:

- `SKILL.md`
- `references/workflow.md`
- `references/invariants.md`
- production `.pipe/aidesklab-factory-gates/task_gate.sh`
- при необходимости `action_gate.sh`

Исправь только следующее.

## 1. Cursor prompt transport

Не предполагать, что:

```bash
agent -p ... < prompt.md
```

является prompt API.

Cursor должен получать полный Action + envelope как один явный prompt value через подтверждённый интерфейс установленного `agent`.

Временный prompt file остаётся вне repo.

## 2. Structured Verification end-to-end

Убрать строковой контракт `--acceptance-cmd "<argv>"`, если он приводит к shell interpretation.

Сделать Task Gate interface structured: `runner + repeated args` либо JSON argv.

Task Gate обязан запускать Verification без `bash -lc`, `eval` или другого shell interpretation.

## 3. Новые acceptance tests

Использовать модель, где Task может создавать новый acceptance test.

Расширить Verification metadata, например:

```yaml
Verification:
  runner: pytest
  args: [...]
  test_files:
    - tests/...
```

Baseline fake-progress:

```text
Task test files + Outcome production → RUNS + FAILS
Task test files + Task production    → RUNS + PASSES
```

Missing runner/setup/test-execution остаётся gate failure, а не expected red.

Новые fixtures/support files перечислять явно.

## 4. Orphan reconciliation

Для текущего Action Gate API при одном marker commit требовать:

```text
matching commit == Task HEAD
```

Иначе Action FAIL.

Не принимать обычный ancestor как достаточный, пока Action Gate не поддерживает explicit target commit SHA.

## 5. Task commit provenance

Перед Task Gate механически доказать:

```text
commits(outcome_base_sha..Task HEAD)
==
commit_sha всех Done Actions
```

Все commits:

- non-merge;
- имеют валидный `action(<ID>):`;
- соответствуют evidence;
- Action ID уникален.

Unknown/missing/extra commit → Task FAIL.

## 6. Dynamic input validation

Перед subprocess/git operations:

- branch → `git check-ref-format`;
- remote → только configured remote;
- Action ID → валидировать установленным ID format;
- Target file → canonical repo-relative, no traversal, security policy.

Невалидное → соответствующий FAIL.

## 7. Cursor policy validation

Не проверять только существование `.cursor/cli.json`.

Механически проверить required effective deny policy.

Permissions и sandbox считать разными слоями конфигурации.

## 8. Gate tests

Перед разрешением cron прогнать минимум:

```text
Task PASS / baseline assertion FAIL → PASS
baseline test missing unexpectedly → FAIL
baseline runner missing → FAIL
baseline setup failure → FAIL
baseline test PASS → fake progress FAIL
Task test FAIL → FAIL
new Task test overlaid onto Outcome production → real assertion FAIL
unknown Task commit without Action evidence → FAIL
```

Не расширять scope на merge, review, rescue, Outcome execution или decomposition.

После патча:

1. покажи изменённые файлы;
2. покажи новый Verification schema;
3. покажи fake-progress baseline algorithm;
4. покажи Task provenance algorithm;
5. подтверди отсутствие shell interpretation Verification;
6. подтверди, что orphan reconciliation согласован с реальным Action Gate API;
7. покажи результаты gate test cases.
