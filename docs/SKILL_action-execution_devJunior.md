---
name: action-execution
description: >
  Оркестрация выполнения Task через Cursor. Используется devJunior для
  последовательного исполнения дочерних Action, проверки commit через
  mechanical gates, создания PR Task → Outcome и перевода Task в In review.
---

# Action Execution

## Роль

`devJunior` — оркестратор выполнения.

`Cursor` — единственный реализатор production-кода.

`devJunior` не должен самостоятельно:

- писать или исправлять production-код;
- заменять Cursor при реализации Action;
- объединять несколько Action в одну реализацию;
- создавать commit вместо Cursor;
- выполнять merge Task → Outcome;
- пропускать mechanical gates;
- менять статус задачи в Kaneo без успешного `transition_guard.py`.

Главный workflow:

```text
Task
↓
Task branch
↓
Action
↓
Cursor
↓
commit
↓
Action Gate
↓
Action Done
↓
next Action
↓
Task Gate
↓
push
↓
PR Task → Outcome
↓
Task In review
```

---

## 1. Входные данные

Skill применяется к задаче Kaneo:

```text
label: Task
status: To Do
assigned: devJunior
```

Перед началом получить:

- Task;
- полный текст Task;
- `Verification` Task;
- родительский Outcome;
- Outcome branch;
- Task branch;
- все дочерние Action;
- статус каждого Action;
- `Target file` каждого Action.

Структура должна быть строго:

```text
Outcome
└── Task
    ├── Action
    ├── Action
    └── ...
```

Если Action находится непосредственно под Outcome или структура нарушена — Task не выполнять.

---

## 2. Предварительная проверка

Перед выполнением Task убедиться:

1. существует production repository;
2. подключён `.pipe`;
3. доступны:
   - `.pipe/aidesklab-factory-gates/action_gate.sh`
   - `.pipe/aidesklab-factory-gates/task_gate.sh`
   - `.pipe/aidesklab-factory-gates/transition_guard.py`
4. команда `make verify-fast` существует и запускается;
5. каждый незавершённый Action содержит ровно один `Target file`;
6. Task содержит машинно-исполняемый `Verification`;
7. Outcome branch определена.

Если обязательное условие не выполнено — остановить Task и зафиксировать конкретную причину. Не пытаться самостоятельно восстанавливать недостающие требования.

---

## 3. Работа с ветками

### Outcome branch

Убедиться, что ветка родительского Outcome существует.

Не создавать Outcome branch от произвольного состояния репозитория, если невозможно однозначно определить её базу.

### Task branch

Каждый Task выполняется в отдельной ветке.

Если Task branch отсутствует — создать её от Outcome branch.

Если Task branch уже существует:

- использовать существующую ветку;
- не создавать новую;
- убедиться, что она относится к текущему Task.

Перед началом исполнения:

```bash
git switch <task-branch>
git status --porcelain
```

Working tree должен быть чистым.

Запрещено выполнять Action непосредственно в:

- `main`;
- `master`;
- Outcome branch;
- ветке другого Task.

---

## 4. Порядок выполнения Action

Action выполняются строго последовательно.

```text
Action 1
↓
Gate
↓
Action 2
↓
Gate
↓
Action 3
```

Не запускать следующий Action до успешного завершения предыдущего.

Не выполнять несколько Action параллельно.

Action со статусом `Done` повторно не выполнять.

---

## 5. Запуск одного Action

Для каждого незавершённого Action выполнить следующий алгоритм.

### 5.1 Проверить Target file

Action обязан содержать:

```text
Target file:
<repo-relative-path>
```

Должен быть указан ровно один файл.

Если `Target file` отсутствует, неоднозначен или содержит несколько файлов — Action не выполнять.

### 5.2 Зафиксировать baseline

Непосредственно перед запуском Cursor:

```bash
BEFORE_SHA="$(git rev-parse HEAD)"
```

Этот SHA используется mechanical gate для доказательства результата текущего Action.

### 5.3 Передать Action в Cursor

Передать Cursor **полный текст Action без сокращения и пересказа**.

Cursor получает именно Action как готовый prompt исполнения.

`devJunior` не должен:

- переписывать требования;
- заменять Action собственной интерпретацией;
- удалять контекст;
- добавлять самостоятельное техническое решение вместо требований Action.

Если Cursor требует контекст, которого нет в Action, это дефект Action. Не компенсировать его самостоятельной реализацией.

---

## 6. Ответственность Cursor

Cursor должен:

1. выполнить требования Action;
2. изменить только требуемый файл;
3. создать один commit;
4. завершить работу.

Инвариант:

```text
1 Action = 1 file = 1 commit
```

Текстовый ответ Cursor вида `done`, `implemented`, `completed` не является доказательством выполнения.

Источник истины — фактическое состояние Git.

---

## 7. Action Gate

После завершения Cursor запустить:

```bash
.pipe/aidesklab-factory-gates/action_gate.sh \
  --before "$BEFORE_SHA" \
  --file "<Target file>"
```

Успешным считается только:

```text
exit code = 0
```

Action Gate механически проверяет, что:

- новый commit существует;
- создан ровно один commit;
- commit не является merge commit;
- изменён ровно один файл;
- изменён именно `Target file`;
- working tree чистый;
- в изменении не появились запрещённые suppress-конструкции.

Не интерпретировать текст вывода gate как замену exit code.

---

## 8. Action Gate failed

Если `action_gate.sh` возвращает ненулевой exit code:

- Action не переводить в `Done`;
- Task оставить `To Do`;
- следующий Action не запускать;
- не создавать PR;
- зафиксировать точную причину отказа gate;
- завершить текущий execution cycle Task.

Не исправлять результат Cursor вручную.

Не создавать фиктивный commit для прохождения gate.

---

## 9. Action → Done

После успешного Action Gate выполнить:

```bash
.pipe/aidesklab-factory-gates/transition_guard.py \
  --entity Action \
  --from-status "To Do" \
  --to-status "Done" \
  --event action_gate_pass \
  --gate-exit 0
```

Только если `transition_guard.py` возвращает `exit code = 0`, перевести Action в Kaneo:

```text
Done
```

После этого перейти к следующему незавершённому Action.

---

## 10. Завершение всех Action

После выполнения последнего Action проверить:

- все дочерние Action имеют статус `Done`;
- каждому выполненному Action соответствует commit;
- все commits находятся в Task branch;
- working tree чистый.

Если хотя бы один Action не `Done`, Task Gate не запускать.

---

## 11. Task Gate

После завершения всех Action запустить:

```bash
.pipe/aidesklab-factory-gates/task_gate.sh \
  --base "<Outcome branch>" \
  --verify-cmd "make verify-fast" \
  --acceptance-cmd "<Verification Task>"
```

Если проект требует подготовки временного baseline worktree, дополнительно использовать:

```bash
--base-setup-cmd "<deterministic setup command>"
```

Успех:

```text
exit code = 0
```

Task Gate должен доказать:

- Task working tree чистый;
- Outcome branch является ancestor текущей Task branch;
- Task содержит реальный diff;
- Task diff не вводит запрещённые suppress-конструкции;
- `make verify-fast` проходит;
- `Verification` проходит на Task branch;
- `Verification` не проходит на Outcome branch.

Критический инвариант:

```text
Outcome branch → Verification FAIL
Task branch    → Verification PASS
```

Если Verification проходит на Outcome branch, это fake progress: Task не готов к review.

---

## 12. Task Gate failed

Если Task Gate возвращает ненулевой exit code:

- Task оставить `To Do`;
- PR не создавать;
- `In review` не устанавливать;
- зафиксировать причину gate failure;
- завершить текущий execution cycle.

Не исправлять production-код самостоятельно.

---

## 13. Push Task branch

После успешного Task Gate:

```bash
git push <remote> <task-branch>
```

Убедиться, что push завершился успешно.

Не переходить к созданию PR при ошибке push.

---

## 14. Создание PR

Создать Pull Request:

```text
Task branch → Outcome branch
```

PR должен относиться только к текущему Task.

Получить фактический URL созданного PR.

Если PR для этой Task branch уже существует:

- не создавать дубликат;
- использовать существующий PR;
- убедиться, что его base — правильная Outcome branch.

`devJunior` не выполняет merge.

---

## 15. Task → In review

После успешного Task Gate, push и существования корректного PR выполнить:

```bash
.pipe/aidesklab-factory-gates/transition_guard.py \
  --entity Task \
  --from-status "To Do" \
  --to-status "In review" \
  --event task_gate_pass \
  --gate-exit 0 \
  --pr-url "<actual PR URL>"
```

Только если guard возвращает `exit code = 0`, перевести Task в Kaneo:

```text
In review
```

На этом выполнение Task со стороны `devJunior` завершено.

Дальнейшая ответственность принадлежит `devMaster` Task Review.

---

## 16. Повторное выполнение после review changes

Если `devMaster` вернул Task `In review → To Do` и создал новые Action:

- использовать существующую Task branch;
- использовать существующий PR;
- не выполнять заново Action со статусом `Done`;
- выполнить только новые незавершённые Action;
- каждый новый Action прогнать через Action Gate;
- после завершения всех Action повторно выполнить Task Gate;
- push новых commits;
- не создавать второй PR;
- существующий PR должен обновиться новыми commits;
- после успешных gates снова перевести Task в `In review` через `transition_guard.py`.

---

## 17. Идемпотентность

При каждом запуске сначала проверять фактическое состояние.

Не создавать повторно:

- существующую Task branch;
- уже существующий commit для Done Action;
- существующий PR.

Не выполнять повторно Action со статусом `Done`.

Если Kaneo и Git расходятся, не угадывать правильное состояние.

Остановить Task и зафиксировать конфликт состояния.

Примеры конфликтов:

```text
Action = Done, но соответствующего commit нет
Task = In review, но PR отсутствует
PR существует с неправильной base branch
Task branch не содержит ожидаемых commits
```

---

## 18. Запрещённые действия

`devJunior` запрещено:

- писать production-код;
- редактировать результат Cursor вручную;
- выполнять Action без Cursor;
- запускать несколько Action параллельно;
- изменять больше одного файла в рамках Action;
- объединять несколько Action в один commit;
- разделять один Action на несколько commit;
- считать текстовый ответ Cursor подтверждением выполнения;
- игнорировать ненулевой exit code gate;
- переводить Action в `Done` без Action Gate;
- создавать PR без Task Gate;
- переводить Task в `In review` без существующего PR;
- merge'ить Task PR;
- выполнять код в Outcome branch или `main`;
- создавать дублирующий PR;
- самостоятельно менять Goal, Verification или содержание Task;
- самостоятельно менять требования Action для удобства реализации.

---

## 19. Failure policy

Любая неоднозначность или mechanical failure приводит к безопасной остановке текущего Task.

Принцип:

```text
не доказано механически = не выполнено
```

При failure:

1. не переходить к следующему уровню workflow;
2. сохранить текущие корректные commits;
3. не менять подтверждённые статусы назад без причины;
4. зафиксировать конкретную ошибку;
5. завершить текущий run.

---

## 20. Definition of Done для devJunior

Работа devJunior по Task завершена только когда одновременно истинны все условия:

```text
все Action = Done
AND
каждый Action прошёл Action Gate
AND
Task Gate = 0
AND
Task branch успешно pushed
AND
существует PR Task → Outcome
AND
transition_guard разрешил переход
AND
Task = In review
```

`Task Done` не является ответственностью devJunior.

---

## 21. Главный инвариант

```text
Cursor пишет код.

devJunior управляет последовательностью.

Git доказывает наличие commit.

Action Gate доказывает атомарность Action.

Task Gate доказывает техническую готовность Task.

PR передаёт Task на review.

devMaster принимает или возвращает Task.
```
