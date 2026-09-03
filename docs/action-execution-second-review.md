# Action Execution — второй раунд ревью

## Вердикт

**Статус: APPROVE WITH CHANGES.**

После первого раунда skill стал существенно целостнее: роли разделены правильно, `FAIL` оформлен как label, появился anti-loop, `BEFORE_SHA` больше не зависит от shell-session, prompt вынесен из production repo, зафиксированы execution evidence и разделение mechanical verification / semantic review.

Перед включением cron остаются **4 блокирующих** и несколько важных замечаний.

---

# Блокирующие замечания

## 1. `FAIL` останавливает цикл, но recovery state не определён

Сейчас при Action failure:

```text
Cursor
→ invalid commit / dirty tree / wrong file
→ Action To Do + FAIL
→ stop
```

Это правильно для остановки, но branch уже может содержать **невалидный commit или незакоммиченные изменения Cursor**.

После явного снятия `FAIL` workflow говорит:

```text
continue from confirmed state
```

но не определяет, что именно является confirmed state и кто обязан вернуть branch к нему.

Опасный сценарий:

```text
BEFORE_SHA = A
Cursor создаёт плохой commit B
Action Gate FAIL
Action = To Do + FAIL

FAIL снимают
cron запускается снова
BEFORE_SHA теперь = B
Cursor создаёт C
Action Gate проверяет только B..C
```

В результате плохой commit `B` может остаться в Task branch и попасть в PR.

### Требуемое исправление

При Action FAIL сохранять:

```text
before_sha
failed_head_sha
```

и считать `before_sha` последним подтверждённым состоянием branch.

Перед повторным execution после снятия `FAIL` разрешать retry только если:

```text
HEAD == recorded before_sha
```

или отдельная recovery-operation явно установила новый trusted baseline.

Failed HEAD нельзя автоматически считать новым baseline.

Не выполнять слепой `git reset --hard` внутри skill без отдельной recovery policy: failed branch полезно сохранить для диагностики.

---

## 2. Не все deterministic stop переводятся в `FAIL`

Anti-loop в `invariants.md` хороший:

```text
To Do + FAIL = auto-execution forbidden
```

Но workflow всё ещё содержит случаи `stop` без `FAIL`, например:

- Task без child Actions;
- broken hierarchy;
- отсутствует `Target file`;
- `Target file` неоднозначен;
- отсутствует `Verification`;
- отсутствуют `.pipe` gates;
- отсутствует `make verify-fast`;
- Outcome branch не найдена.

Такая Task останется обычной `To Do` и следующий cron-run снова её подберёт.

### Требуемое исправление

Классифицировать preflight failures:

```text
Task-level structural/config failure
→ Task To Do + FAIL

Action-specific malformed input
→ Action To Do + FAIL
→ Task To Do
```

Рекомендуемое соответствие:

| Failure | FAIL owner |
|---|---|
| zero Actions | Task |
| broken Outcome→Task→Action hierarchy | Task |
| missing Verification | Task |
| missing `.pipe` gates | Task |
| missing `make verify-fast` | Task |
| Outcome branch cannot be resolved/created safely | Task |
| missing/ambiguous/multiple Target file | Action |
| malformed Action execution metadata | Action |

Общий инвариант:

```text
если следующий cron-run при неизменном состоянии гарантированно получит тот же failure,
обязательно ставить FAIL
```

---

## 3. Создание Outcome branch всё ещё не определено

Исходная ответственность `devJunior` — **создавать ветки**.

Текущий skill говорит:

```text
Outcome branch must exist
```

и при отсутствии фактически останавливается.

Для первого Task нового Outcome это может означать, что pipeline никогда не стартует.

### Требуемое исправление

Определить детерминированную branch policy:

1. `git fetch <remote>`;
2. определить remote default branch;
3. если Outcome branch существует — использовать;
4. если отсутствует — создать от актуального remote default branch;
5. Task branch отсутствует → создать от Outcome branch;
6. branch names получать из Kaneo metadata, если они уже зафиксированы;
7. если metadata отсутствует и repo не задаёт convention — использовать стабильный fallback:
   - `outcome/<kaneo-outcome-id>`
   - `task/<kaneo-task-id>`;
8. после создания записать фактическое имя branch обратно в Kaneo metadata/evidence.

Не использовать title как единственный идентификатор branch: title изменяем и может коллидировать.

---

## 4. `task_gate.sh` нельзя считать проверенным по этим трём файлам

Workflow теперь правильно требует:

```text
acceptance test EXISTS
AND
without implementation → FAIL
AND
with implementation → PASS
```

и отдельно запрещает считать `file not found`, missing dependency или failure запуска тест-раннера ожидаемым красным тестом.

Но в текущем раунде предоставлены только:

```text
SKILL.md
references/workflow.md
references/invariants.md
```

Сам `.pipe/aidesklab-factory-gates/task_gate.sh` не предоставлен.

Поэтому невозможно подтвердить, что **реальная механическая реализация gate соответствует новому контракту**.

### Обязательные test cases для `task_gate.sh`

```text
1. Task branch: acceptance PASS; baseline: acceptance ASSERTION FAIL
   → gate PASS

2. baseline: test file missing
   → gate FAIL

3. baseline: test runner missing
   → gate FAIL

4. baseline: dependency/setup failure
   → gate FAIL

5. acceptance passes и на baseline
   → gate FAIL (fake progress)

6. acceptance fails и на Task branch
   → gate FAIL
```

---

# Важные замечания

## 5. Execution evidence должно быть machine-readable

Сейчас разрешено:

```text
Kaneo comment or Action metadata
```

Для idempotence это слишком неоднозначно. Свободный комментарий трудно надёжно парсить.

### Рекомендация

Приоритет:

```text
structured Kaneo metadata
```

Если metadata API недостаточно — canonical JSON comment с фиксированным marker:

```text
AIDESKLAB_EXEC_EVIDENCE_V1
{"action_id":"...","branch":"...","before_sha":"...","commit_sha":"...","target_file":"...","gate":"passed"}
```

Failure evidence — аналогично:

```text
AIDESKLAB_EXEC_FAILURE_V1
{...}
```

---

## 6. Commit должен содержать Action ID

Сейчас идемпотентность зависит почти полностью от Kaneo evidence.

Если commit создан и gate прошёл, но запись evidence/status в Kaneo оборвалась, следующий cron может увидеть Action всё ещё `To Do`.

Добавить вторичную связь непосредственно в Git:

```text
action(<KANEO_ACTION_ID>): <short title>
```

или иной стабильный marker Action ID в commit message.

Action Gate желательно дополнительно проверять marker текущего Action ID в HEAD commit.

---

## 7. Частичный failure после Action Gate PASS

Нужно явно описать последовательность:

```text
Action Gate PASS
→ obtain HEAD_SHA
→ persist execution evidence
→ transition_guard
→ Kaneo Done
```

Если evidence/status update не удался:

- Cursor повторно не запускать;
- не создавать второй implementation commit;
- следующий run сначала reconciles Git/evidence/Kaneo;
- при конфликте → `FAIL`.

---

## 8. Push/PR/transition failures тоже требуют anti-loop policy

Нужно унифицировать:

```text
Task Gate PASS
→ push failure       → Task FAIL
→ PR API failure     → Task FAIL
→ PR wrong base      → Task FAIL
→ transition_guard state conflict → Task FAIL
```

На текущем этапе безопаснее считать любой технический failure после Task Gate причиной `FAIL`, чем вводить бесконечный retry.

---

## 9. Target file должен иметь security boundary

Сейчас правило проверяет только:

```text
exactly one Target file
```

Но Action теоретически может содержать:

```text
Target file: .pipe/aidesklab-factory-gates/task_gate.sh
```

Нужно запретить Action execution для:

```text
.pipe/**
.git/**
credential/secret files
repo-defined forbidden paths
```

`Target file` должен проходить repository policy / `AGENTS.md`.

---

## 10. Outcome base лучше фиксировать SHA

Branch name может сдвинуться во время выполнения Task.

После `git fetch` полезно фиксировать:

```text
outcome_base_ref
outcome_base_sha
```

Перед Task Gate сверять сохранённый SHA с актуальной Outcome branch.

Если Outcome изменилась — не продолжать молча: deterministic sync либо Task `FAIL`.

---

# Отдельное замечание по platforms

`SKILL.md` заявляет:

```yaml
platforms: [linux, macos]
```

Это корректно только если текущие gate scripts реально совместимы с macOS environment.

Если используемый `action_gate.sh` требует Bash 4+ constructs, стандартный macOS Bash 3.2 его не выполнит. Перед сохранением `macos` в metadata gates нужно проверить на чистом macOS runner либо явно потребовать современный Bash.

---

# Что уже сделано хорошо

Второй раунд подтверждает:

- `devJunior` больше не может самостоятельно реализовать Task без Actions;
- `FAIL` — label, а не status;
- cron проверяет `FAIL` до Cursor;
- review return отделён от technical FAIL;
- `BEFORE_SHA` вынесен из shell variable lifecycle;
- Action prompt вынесен из production repo;
- Cursor execution отделён от branch/PR/Kaneo управления;
- появился Action execution evidence;
- mechanical Task Verification отделена от semantic review;
- fake-progress contract описан правильно на уровне skill;
- duplicate PR запрещён;
- merge исключён из scope `devJunior`;
- `related_skills: [codex]` удалён;
- Windows native support удалён.

---

# Итоговая оценка

После текущего раунда архитектура skill правильная, но cron пока лучше **не включать**.

Минимальный набор перед включением:

```text
1. Закрыть recovery-after-FAIL hole.
2. Ставить FAIL на все deterministic preflight stops.
3. Определить создание/naming Outcome branch.
4. Проверить реальный task_gate.sh на 6 fake-progress сценариях.
```

После этих четырёх исправлений можно делать пилотный ручной прогон одной Task, затем 2–3 cron-run под наблюдением.

---

# Промт агенту на третий проход

Обнови существующий `action-execution` skill точечно, не меняя архитектуру.

Исправь только следующие оставшиеся проблемы второго review.

## 1. Recovery после Action FAIL

При Action execution сохранять `before_sha`.

Если Cursor/action gate failed и branch содержит invalid commit/changes:

- сохранить `before_sha` и `failed_head_sha` в failure evidence;
- `before_sha` остаётся последним trusted baseline;
- после снятия `FAIL` запрещено использовать failed HEAD как новый baseline;
- retry разрешён только если branch восстановлена к recorded `before_sha` либо отдельная recovery operation явно установила новый trusted baseline;
- cron не должен выполнять destructive reset самостоятельно без отдельной recovery policy.

## 2. FAIL для всех deterministic stops

Устранить обычные `stop`, которые следующий cron повторит без изменения результата.

Применять:

```text
zero Actions → Task FAIL
broken hierarchy → Task FAIL
missing Verification → Task FAIL
missing .pipe gates → Task FAIL
missing make verify-fast → Task FAIL
Outcome branch unresolved → Task FAIL
missing/ambiguous/multiple Target file → Action FAIL
```

Общий инвариант:

```text
если следующий cron-run при неизменном состоянии гарантированно получит тот же failure,
должен быть установлен FAIL
```

## 3. Outcome branch creation

`devJunior` отвечает за создание веток.

После `git fetch`:

- если Outcome branch существует — reuse;
- если отсутствует — создать от актуальной remote default branch;
- branch name брать из Kaneo metadata/repo convention;
- если convention отсутствует — fallback `outcome/<outcome-id>`;
- Task branch fallback `task/<task-id>`;
- после создания сохранить фактические branch names в Kaneo evidence/metadata;
- не использовать mutable title как единственный branch identifier.

## 4. Machine-readable evidence

Execution/failure evidence должны быть структурированными.

Предпочитать Kaneo metadata.

Если используется comment — фиксированный versioned JSON marker:

```text
AIDESKLAB_EXEC_EVIDENCE_V1
AIDESKLAB_EXEC_FAILURE_V1
```

Свободный prose comment не считать достаточным источником для idempotence.

## 5. Git identity Action ↔ commit

Добавить в execution envelope обязательный commit marker с Kaneo Action ID, например:

```text
action(<ACTION_ID>): <title>
```

Использовать Action ID как вторичный reconciliation key.

Если возможно без изменения scope, Action Gate должен проверять marker текущего Action в HEAD commit.

## 6. Partial Kaneo write failure

После Action Gate PASS порядок:

```text
HEAD_SHA
→ persist evidence
→ transition_guard
→ Action Done
```

Если evidence/status update не удался:

- Cursor повторно не запускать;
- не создавать второй implementation commit;
- следующий run сначала reconciles Git/evidence/Kaneo;
- при конфликте → FAIL.

## 7. Post-Task-Gate technical failures

Явно добавить Task FAIL для:

```text
push failure
PR creation/API failure
PR wrong base
transition_guard state conflict
```

Без бесконечного cron retry.

## 8. Target file boundary

Перед Cursor валидировать Target file против repo policy / AGENTS.md.

Запретить как минимум:

```text
.pipe/**
.git/**
credential/secret files
repo-defined forbidden paths
```

## 9. Pin Outcome base

После fetch сохранять:

```text
outcome_base_ref
outcome_base_sha
```

Перед Task Gate сверять с актуальной Outcome branch.

Если Outcome изменилась — не продолжать молча: deterministic sync либо Task FAIL.

## 10. macOS metadata

Проверить реальную совместимость gate scripts с macOS.

Если gates требуют Bash 4+ и это не гарантировано, убрать `macos` из `platforms` либо явно задокументировать dependency на современный Bash.

Не расширять scope на review, merge, rescue, Outcome execution или decomposition.

После изменений:
1. перечисли изменённые файлы;
2. покажи финальную failure/recovery state machine;
3. отдельно подтверди, что обычного deterministic `stop` без FAIL больше нет;
4. покажи branch creation policy;
5. покажи canonical evidence format.
