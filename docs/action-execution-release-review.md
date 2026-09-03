# Action Execution — release review

## Вердикт

**APPROVE AFTER SMALL PATCH.**

Версия `0.5.0` архитектурно завершена. Новый раунд архитектурного проектирования `action-execution` больше не нужен.

Основные инварианты согласованы во всех трёх файлах:

- `devJunior` — orchestrator, не writer;
- Cursor — единственный writer production-кода;
- `1 Action = 1 Target file = 1 commit`;
- `action(<ACTION_ID>):` — обязательная Git identity;
- `FAIL` закрывает deterministic retry loops;
- Action FAIL имеет trusted `before_sha`;
- orphan reconciliation не запускает второй Cursor;
- Outcome создаётся и публикуется до Task branch;
- Outcome drift запрещает silent sync;
- Task provenance обязателен;
- Verification structured, а не shell program;
- baseline overlay поддерживает новые acceptance tests;
- Cursor permissions являются mechanical boundary;
- PR создаёт `devJunior`, merge остаётся у `devMaster`.

Перед freeze нужны только следующие точечные исправления.

---

# 1. Убрать жёсткое утверждение, что `.pipe` подключён именно как git submodule

В текущих файлах встречается формулировка:

```text
product consumes source .pipe as a submodule
```

Это не соответствует принятому контракту.

Фабрика гарантирует только:

```text
<product-repo>/.pipe/aidesklab-factory-gates/
```

`.pipe` является отдельным repository/subrepo с зафиксированной ревизией.

Способ подключения:

```text
git submodule
git subtree
другой механизм pinned subrepo
```

не относится к `action-execution`.

### Исправить во всех трёх файлах

Использовать формулировку:

```text
Product repo consumes a pinned revision of the external `.pipe` repository
at `.pipe/`. The attachment mechanism is outside this skill.
```

Не использовать слово `submodule` как обязательный механизм.

---

# 2. Довести baseline-overlay security до уже утверждённого контракта

Текущий skill валидирует `Target file`, но `test_files` / `support_files` ещё не имеют такого же полного security boundary.

Это важно, потому что именно эти файлы `task_gate.sh` должен копировать из Task branch в baseline Outcome worktree.

Без отдельной проверки можно ошибочно overlay'ить production implementation и получить ложный fake-progress verdict.

## Обязательная validation для `test_files` и `support_files`

До Task Gate каждый путь должен быть:

```text
canonical repo-relative
no ..
not absolute
no symlink escape outside repo
not .pipe/**
not .git/**
not secret / credential path
inside repo-defined test / fixture boundaries
```

Дополнительно:

```text
Target file текущего production Action
не может одновременно использоваться как baseline overlay file
```

Если путь нельзя механически классифицировать как test/support artifact:

```text
Task FAIL
```

Не выполнять overlay «по доверию к тексту задачи».

## Dynamic input validation

В `workflow.md` и `invariants.md` добавить `test_files` / `support_files` рядом с `Target file`.

---

# 3. Вернуть expanded gate suite: 10 проверок, а не 8

В утверждённом patch-plan suite был расширен до 10 случаев.

Текущая версия снова указывает `8-case suite`.

Production cron должен оставаться blocked до следующего контракта:

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

Во всех трёх skill-файлах заменить `8-case` на **expanded 10-case gate suite**.

---

# 4. Перед Task Gate обновлять remote Outcome ref

Сейчас skill правильно требует:

```text
current Outcome tip != pinned outcome_base_sha → Task FAIL
```

Но для реальной проверки remote drift перед Task Gate нужен свежий remote ref.

Добавить в workflow непосредственно перед provenance / Task Gate:

```text
git fetch <validated-remote>
```

После fetch сравнить:

```text
refs/remotes/<remote>/<outcome_branch>
```

с сохранённым:

```text
outcome_base_sha
```

Если SHA отличается:

```text
Task To Do + FAIL
```

Без auto-rebase / auto-merge.

Причина: локальная Outcome branch может оставаться неизменной, пока другой Task уже был merged в remote Outcome.

Итоговый drift invariant:

```text
fresh remote Outcome tip == pinned outcome_base_sha
```

а не просто:

```text
stale local Outcome tip == pinned outcome_base_sha
```

---

# Housekeeping — temp prompt cleanup

После завершения Cursor process удалить:

```text
/tmp/aidesklab-actions/<task-id>/<action-id>.md
```

Удаление выполняется независимо от PASS/FAIL Cursor, если файл был создан.

Это не должно влиять на Git recovery evidence.

В prompt-файле может находиться полный контекст Action, поэтому не оставлять такие файлы на runner бессрочно.

---

# Что НЕ менять

Не менять больше:

- роли `devMaster` / `devJunior` / Cursor;
- Action → commit модель;
- `FAIL` semantics;
- trusted baseline recovery;
- orphan reconciliation;
- branch naming architecture;
- Outcome publication;
- provenance model;
- structured Verification model;
- Cursor permission architecture;
- review / merge ownership;
- scope skill.

Не искать и не clone'ить `.pipe` из repo конфигурации `devJunior`.

Production gate implementation остаётся отдельной задачей в исходном repo `.pipe`.

---

# Definition of Freeze для skill

После этих изменений `action-execution` считается **FROZEN / READY FOR PILOT** если:

```text
SKILL.md
workflow.md
invariants.md
```

согласованы и одновременно выполняется:

```text
[ ] .pipe описан как external pinned subrepo, без обязательного "submodule"
[ ] test_files/support_files имеют overlay security boundary
[ ] documented gate suite = 10 cases
[ ] remote Outcome re-fetch выполняется перед drift check / Task Gate
[ ] temp Action prompt очищается после Cursor execution
[ ] cron всё ещё blocked до доказательства production gate contract
```

После этого **не проводить ещё один текстовый архитектурный review skill**.

Следующий review должен анализировать:

```text
реальный pilot Task trace
Git history
Kaneo transitions/evidence
Action Gate logs
Task Gate logs
PR
```

---

# Промт агенту для последнего patch

Внеси последний точечный patch в `action-execution` v0.5.x.

Работай только с:

- `SKILL.md`
- `references/workflow.md`
- `references/invariants.md`

`.pipe` в текущем workspace не искать, не clone'ить, не создавать и не изменять.

Исправить только 5 пунктов:

1. Убрать утверждение, что `.pipe` обязательно подключён как `submodule`.
   Контракт:
   `Product repo consumes a pinned revision of external .pipe at .pipe/; attachment mechanism is outside this skill.`

2. Добавить mechanical security validation для `Verification.test_files` и `support_files`:
   canonical repo-relative; no traversal/absolute/symlink escape; no `.pipe/**`, `.git/**`, secrets; только repo-defined test/fixture boundaries; production Target file нельзя использовать как baseline overlay artifact.
   Invalid overlay path → Task `FAIL`.

3. Везде заменить `8-case` на expanded **10-case gate suite**, добавив:
   - forbidden/production/outside-repo overlay path → gate FAIL;
   - legacy shell-interpreted Task Gate API → deployment preflight BLOCK.

4. Непосредственно перед Task provenance / Task Gate выполнить fresh:
   `git fetch <validated-remote>`
   и сравнивать pinned `outcome_base_sha` именно с fresh remote Outcome ref.
   Remote drift → Task `FAIL`; no auto-sync.

5. После любого Cursor execution удалять временный Action prompt из `/tmp`, независимо от PASS/FAIL.

Архитектуру больше не менять.

После patch:
- bump только patch version при необходимости;
- проверить согласованность трёх файлов;
- подтвердить пять изменений;
- не предлагать дополнительные архитектурные изменения этого skill;
- оставить cron blocked до отдельной реализации/проверки production `.pipe` gate contract.

После выполнения этот skill считаем frozen и переходим к pilot execution.
