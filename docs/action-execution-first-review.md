Обнови существующий Hermes skill `action-execution` для `devJunior`.

Работай с текущими файлами skill:

* `SKILL.md`
* `references/workflow.md`
* `references/invariants.md`

Также проверь связанные механические инструменты из подключённого `.pipe`:

* `.pipe/aidesklab-factory-gates/action_gate.sh`
* `.pipe/aidesklab-factory-gates/task_gate.sh`
* `.pipe/aidesklab-factory-gates/transition_guard.py`

Не переписывай архитектуру с нуля. Сохрани базовую модель:

```text
devMaster = decomposition + semantic Task review + merge
devJunior = execution orchestrator
Cursor = единственный writer production-кода
mechanical gates = технический verdict
Kaneo = состояние workflow
```

Главный execution flow:

```text
Task To Do
→ Task branch
→ Action
→ Cursor
→ commit
→ Action Gate
→ Action Done
→ следующий Action
→ Task Gate
→ push
→ PR Task → Outcome
→ Task In review
```

Внести следующие изменения и исправления.

## 1. Task без Action

Удалить правило вроде:

```text
Tasks with no child Actions — handle those yourself
```

`devJunior` никогда не реализует production-код самостоятельно.

Если Task не содержит Action:

```text
stop
```

Зафиксировать причину как некорректную декомпозицию.

---

## 2. Cursor CLI

Использовать headless Cursor CLI в режиме записи:

```bash
agent -p --force --model auto ...
```

Не использовать устаревшую/неподходящую комбинацию:

```text
cursor agent ... --trust
```

Если конкретная установленная версия Cursor CLI имеет иной синтаксис — определить его локально через `agent --help` и использовать эквивалентный non-interactive режим с разрешением записи.

---

## 3. Action prompt

Cursor получает **полный исходный текст Action без сокращения или пересказа**.

Action prompt нельзя создавать внутри production repository, чтобы временный файл не делал git working tree dirty.

Использовать временный путь вне repo, например:

```text
/tmp/aidesklab-actions/<task-id>/<action-id>.md
```

После execution временный файл удалить.

К исходному Action разрешается добавить только execution envelope, не изменяющий технические требования:

```text
- выполнить только этот Action;
- изменить только Target file;
- не изменять .pipe;
- не switch/rebase/merge ветки;
- не push;
- не создавать PR;
- не менять Kaneo;
- создать ровно один commit.
```

`devJunior` не добавляет собственной реализации или архитектурного решения.

---

## 4. BEFORE_SHA

Не рассчитывать на сохранение shell variables между отдельными вызовами terminal.

Перед Cursor выполнить:

```bash
git rev-parse HEAD
```

Полученный SHA сохранить в состоянии текущего execution и затем передавать в Action Gate как literal value:

```bash
action_gate.sh \
  --before "<actual-before-sha>" \
  --file "<Target file>"
```

---

## 5. Инвариант Action

Строго:

```text
1 Action = 1 Target file = 1 commit
```

Action обязан содержать ровно один:

```text
Target file:
<repo-relative-path>
```

Если Target file:

* отсутствует;
* неоднозначен;
* содержит несколько файлов;

Action не выполнять.

---

## 6. Action Gate

После Cursor `devJunior` проверяет только фактическое состояние Git.

Текст Cursor `done`, `implemented`, `completed` не является доказательством выполнения.

`action_gate.sh` должен подтверждать:

* появился новый commit;
* появился ровно один commit после BEFORE_SHA;
* commit не merge commit;
* изменён ровно один файл;
* это именно Target file;
* working tree clean;
* отсутствуют запрещённые suppress-конструкции.

Verdict определяется исключительно:

```text
exit code
```

`exit 0` = PASS.

Любой non-zero = FAIL.

---

## 7. Execution evidence для Action

После успешного Action Gate получить:

```bash
git rev-parse HEAD
```

и сохранить в Kaneo comment или metadata Action execution evidence:

```text
branch
before_sha
commit_sha
target_file
gate=passed
```

Эти данные являются доказательством соответствия:

```text
Action ↔ commit
```

При последующих cron-runs использовать их для idempotence check.

Action со статусом `Done`, для которого соответствующий commit отсутствует в Task branch, является state conflict.

Не угадывать состояние — stop.

---

# 8. FAIL label

Внедрить системный Kaneo label:

```text
FAIL
```

`FAIL` — не status.

Он означает:

> автоматическое выполнение остановлено из-за технического или механического failure; повторный запуск запрещён до устранения причины.

Основной инвариант:

```text
To Do без FAIL = можно автоматически исполнять
To Do + FAIL   = автоматическое исполнение запрещено
```

Не создавать дополнительный status `Failed`.

---

## 9. Action-level FAIL

Добавить `FAIL` к Action, если:

* Cursor завершился ошибкой;
* Cursor не создал commit;
* создано несколько commit;
* изменено несколько файлов;
* изменён неправильный файл;
* working tree dirty;
* `action_gate.sh != 0`;
* обнаружен Action ↔ Git state conflict;
* execution невозможно безопасно продолжить.

Состояние:

```text
Action:
status = To Do
label = FAIL

Task:
status = To Do
```

После этого:

```text
не запускать следующий Action
не создавать PR
stop current Task execution
```

Сохранить failure evidence:

```text
failure_stage
gate_exit_code
branch
before_sha
head_sha
target_file
error
```

---

## 10. Task-level FAIL

Добавлять `FAIL` непосредственно к Task, если failure относится ко всему Task workflow:

* `task_gate.sh != 0`;
* `make verify-fast` failed;
* Task Verification failed;
* fake progress detected;
* Task/Outcome branch state conflict;
* PR state conflict;
* невозможно безопасно продолжить Task workflow.

Состояние:

```text
Task:
status = To Do
label = FAIL
```

---

## 11. FAIL anti-loop

Каждый cron-run начинать с проверки:

```text
Task has FAIL?
Any child Action has FAIL?
```

Если да:

```text
не запускать Cursor
не запускать повторно failed gate
не создавать новые commits
не создавать PR
stop / skip Task
```

`FAIL` нельзя автоматически снимать следующим cron-run.

Повторное выполнение разрешено только после:

1. устранения причины failure;
2. явного снятия `FAIL`.

После снятия FAIL продолжать с текущего подтверждённого состояния:

* Done Action повторно не выполнять;
* использовать существующую Task branch;
* использовать существующий PR;
* выполнять только unfinished Action.

---

## 12. Review failure ≠ FAIL

Нормальные замечания `devMaster` во время semantic review не являются техническим FAIL.

Обычный workflow:

```text
Task In review
→ review changes requested
→ devMaster создаёт новые Action
→ Task To Do
→ devJunior выполняет новые Action
```

Без label `FAIL`.

`FAIL` использовать только для технической невозможности штатно продолжить автоматический execution workflow.

---

## 13. Ветки

Перед работой получить актуальное состояние remote:

```bash
git fetch
```

Outcome branch должна существовать.

Task branch:

* отсутствует → создать от актуальной Outcome branch;
* существует → использовать существующую.

Не создавать дубликаты branch.

Перед execution убедиться:

```text
HEAD = Task branch
working tree = clean
```

Запрещено выполнять Cursor на:

```text
main
master
Outcome branch
another Task branch
```

Если существующая Task branch больше не содержит ожидаемую Outcome base и состояние невозможно безопасно синхронизировать детерминированно — ставить Task `FAIL` и stop.

Cursor не использовать для решения git branch conflicts.

---

## 14. Порядок Action

Action выполнять строго последовательно.

Порядок должен быть детерминированным и сохраняться между cron-runs.

Использовать порядок Kaneo. Если отдельное order-поле отсутствует — использовать стабильное существующее поле/ID.

Не менять порядок произвольно.

Не выполнять несколько Action параллельно.

Action со статусом `Done` повторно не выполнять.

---

## 15. Mechanical Task Verification

Чётко разделить ответственность:

```text
devJunior:
mechanical Task Verification

devMaster:
semantic / functional acceptance review
```

`devJunior` запускает:

```bash
task_gate.sh \
  --base "<Outcome branch>" \
  --verify-cmd "make verify-fast" \
  --acceptance-cmd "<Task Verification>"
```

Task должен содержать machine-executable `Verification`.

---

## 16. Безопасность Verification

Не выполнять произвольную shell-строку из Kaneo без проверки.

Verification должна соответствовать разрешённым repository test commands / `AGENTS.md` policy.

Опасные конструкции вроде произвольного:

```text
;
&& destructive-command
>
>>
|
curl ...
rm ...
```

должны приводить к stop/FAIL, если они явно не разрешены repository policy.

Verification предназначена для запуска тестов, а не выполнения произвольной shell automation.

---

## 17. Исправить fake-progress verification

Проверь реализацию:

```text
.pipe/aidesklab-factory-gates/task_gate.sh
```

Fake-progress проверка должна доказать именно:

```text
acceptance test EXISTS
AND
без production implementation → FAIL
AND
с implementation → PASS
```

Нельзя считать корректным доказательством failure ситуацию:

```text
test file отсутствует
test command не существует
dependency/setup отсутствует
test runner не запустился
```

То есть:

```text
"тест не смог запуститься"
```

не равно:

```text
"тест запустился и корректно обнаружил отсутствие реализации"
```

Если текущий `task_gate.sh` просто запускает Verification на чистой Outcome branch и любой non-zero принимает за ожидаемый FAIL — исправить скрипт.

При необходимости использовать temporary baseline worktree и `--base-setup-cmd`.

---

## 18. Task Gate failure

Если Task Gate failed:

```text
Task = To Do + FAIL
```

Не:

* создавать PR;
* переводить Task в In review;
* самостоятельно исправлять production-код.

Сохранить failure evidence и stop.

---

## 19. PR

После Task Gate PASS:

```text
git push
```

Перед `gh pr create` сначала проверить, существует ли уже PR для Task branch.

Если существует корректный open PR:

```text
использовать его
```

Не создавать дубликат.

Обязательно проверить:

```text
head = Task branch
base = Outcome branch
```

Если PR существует с неправильным base:

```text
Task = To Do + FAIL
stop
```

Если PR отсутствует — создать:

```text
Task branch → Outcome branch
```

Получить фактический PR URL.

`devJunior` никогда не выполняет merge.

---

## 20. Task → In review

Только после:

```text
all Actions Done
AND Action evidence valid
AND Task Gate = 0
AND push succeeded
AND correct PR exists
```

запустить:

```bash
transition_guard.py \
  --entity Task \
  --from-status "To Do" \
  --to-status "In review" \
  --event task_gate_pass \
  --gate-exit 0 \
  --pr-url "<actual PR URL>"
```

Только при:

```text
exit 0
```

перевести Kaneo Task:

```text
In review
```

---

## 21. Rework после devMaster review

Если devMaster:

```text
In review → To Do
```

и создал новые Action:

* использовать существующую Task branch;
* использовать существующий PR;
* не выполнять Done Actions;
* выполнить только новые Action;
* каждый новый Action → Cursor → Action Gate → Done;
* затем снова Task Gate;
* push новых commits;
* не создавать второй PR;
* существующий PR автоматически получает commits;
* Task снова → In review через transition_guard.

Review changes сами по себе label `FAIL` не получают.

---

## 22. Idempotence

При каждом cron-run сначала сверять Kaneo и Git.

Не создавать повторно:

* существующую Task branch;
* commit для уже Done Action;
* существующий PR.

Проверять execution evidence Done Action.

State conflicts:

```text
Action Done, commit missing
Action Done, commit not in Task branch
Task In review, PR missing
PR wrong base
Task branch missing expected commits
```

→ не угадывать и не ремонтировать состояние вслепую.

Использовать:

```text
FAIL
stop
```

---

## 23. transition_guard

`transition_guard.py` продолжает отвечать только за разрешение status transitions.

`FAIL` является отдельным execution-control label.

Не превращать FAIL в новый Kaneo status.

---

## 24. Metadata skill

Убрать:

```yaml
related_skills: [codex]
```

если Codex реально не используется этим skill.

Не заявлять Windows native support, если gates требуют bash/git Unix environment.

Оставить только реально поддерживаемые platforms.

---

## 25. Структура skill

Сохранить разделение:

```text
SKILL.md
```

короткий entrypoint:

* когда использовать;
* prerequisites;
* основной workflow;
* quick reference.

```text
references/workflow.md
```

полный алгоритм выполнения.

```text
references/invariants.md
```

* idempotence;
* FAIL semantics;
* prohibitions;
* failure policy;
* Definition of Done;
* core invariants.

Не дублировать весь workflow во всех файлах.

---

## 26. Scope

Не расширять skill на:

* Outcome execution;
* Outcome Review;
* Task semantic review;
* merge;
* rescue;
* adversary;
* декомпозицию.

---

## Definition of Done

После изменений проверить отсутствие противоречий между:

```text
SKILL.md
references/workflow.md
references/invariants.md
```

Итоговый DoD `devJunior`:

```text
all Actions = Done
AND
every Action has valid commit evidence
AND
every Action passed Action Gate
AND
Task Gate = 0
AND
Task branch pushed
AND
correct PR Task → Outcome exists
AND
transition_guard allowed transition
AND
Task = In review
AND
no FAIL labels remain on Task or child Actions
```

Главный инвариант:

```text
Cursor writes code.

devJunior orchestrates.

Git proves commits.

Action Gate proves Action atomicity.

Task Gate proves mechanical Task readiness.

FAIL prevents automatic retry loops.

PR hands the Task to devMaster.

devMaster performs semantic review and merge.
```

После выполнения покажи краткий отчёт:

1. какие файлы изменены;
2. какие противоречия исправлены;
3. как теперь работает `FAIL`;
4. изменялся ли `task_gate.sh` и почему;
5. итоговый execution flow одной строкой.
