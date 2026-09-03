# Action Execution — третий раунд ревью

## Вердикт

**Статус: APPROVE WITH CHANGES / cron пока не включать.**

Третий вариант skill уже хорошо закрывает предыдущие архитектурные дыры: `FAIL` стал полноценным anti-loop marker, recovery привязан к trusted `before_sha`, deterministic stops классифицированы, Outcome/Task branch creation введён, evidence стал machine-readable, Action ID появился в commit identity, Outcome base pinning описан. Основная логика `devJunior → Cursor → gates → PR → devMaster` теперь согласована.

Остались **5 блокирующих моментов**, из которых четыре относятся к самому skill/workflow, один — к внешнему `task_gate.sh`.

---

# 1. BLOCKER — Outcome branch создаётся локально, но не гарантируется remote branch

Сейчас workflow говорит:

```text
Outcome branch missing → create from remote default branch
Task branch missing → create from Outcome
...
Task Gate
→ git push Task branch
→ PR Task → Outcome
```

Но PR base должен существовать **на Git remote**, а skill не требует push новой Outcome branch.

Сценарий:

```text
remote/main exists
remote/outcome/123 does not exist

local outcome/123 created
local task/456 created from it
Task Gate PASS
git push task/456
PR base = outcome/123
→ base branch отсутствует на remote
```

## Требуемое исправление

Branch policy должна различать `local` и `remote` existence.

Рекомендуемый алгоритм:

```text
git fetch <remote>

remote Outcome exists?
├─ yes → create/reuse local tracking branch from remote Outcome
└─ no
   → create local Outcome from remote default branch
   → push Outcome branch to remote
   → verify remote Outcome exists

Task branch exists?
├─ yes → reuse
└─ no → create from local Outcome
```

После создания Outcome branch обязательно:

```bash
git push -u <remote> <outcome-branch>
```

и затем проверить:

```text
remote/<outcome-branch> resolves to expected SHA
```

Только после этого разрешено исполнять Task.

Failure создания/push/verification Outcome branch → **Task `FAIL`**.

Также evidence/metadata должны хранить:

```text
outcome_branch
outcome_remote
outcome_base_sha
```

---

# 2. BLOCKER — partial Kaneo failure всё ещё может привести к повторному Cursor

Skill правильно говорит:

```text
Action Gate PASS
→ persist evidence
→ transition_guard
→ Done

write failure → do not rerun Cursor
```

Но алгоритм следующего cron-run не определён достаточно механически.

Особенно опасный сценарий:

```text
Action = To Do
Cursor сделал валидный commit C
Action Gate PASS

запись evidence в Kaneo упала
или Done update упал

cron запускается снова
Action всё ещё To Do
```

В текущем workflow сказано "reconcile", но нет процедуры, позволяющей однозначно отличить это состояние от ещё не выполнявшегося Action.

Commit marker уже предусмотрен:

```text
action(<ACTION_ID>): <title>
```

но `action_gate.sh` проверяет marker только как `SHOULD`, а не обязательный инвариант.

## Требуемое исправление

Перед **каждым** запуском Cursor для unfinished Action выполнить orphan-commit reconciliation.

Алгоритм:

```text
Action status != Done
AND no FAIL
↓
search Task branch for commit marker action(<ACTION_ID>):
```

### 0 matching commits

```text
normal execution allowed
```

### exactly 1 matching commit

Не запускать Cursor.

Проверить:

```text
commit is ancestor of Task HEAD
commit is non-merge
commit changes exactly Target file
commit parent can be used as before_sha
Action Gate passes for parent..commit
```

Если PASS:

```text
reconstruct/persist AIDESKLAB_EXEC_EVIDENCE_V1
→ transition_guard
→ Done
```

### >1 matching commits

```text
Action FAIL
state conflict
```

Commit marker должен стать **MUST**, не SHOULD.

Лучше расширить `action_gate.sh` параметром:

```bash
--action-id "<ACTION_ID>"
```

и механически проверять HEAD subject:

```text
^action\(<ACTION_ID>\):
```

Так Action ↔ Git остаётся восстанавливаемой связью даже при полном падении Kaneo write после commit.

---

# 3. BLOCKER — recovery после Action FAIL должен проверять не только HEAD

Сейчас retry после снятия `FAIL` разрешён при:

```text
HEAD == recorded before_sha
```

Этого недостаточно.

Пример:

```text
before_sha = A
Cursor изменил файл, но не сделал commit
HEAD = A
working tree dirty
Action FAIL

FAIL сняли
HEAD == A  ← условие формально выполнено
```

Но branch не восстановлена в trusted state.

## Требуемое исправление

Retry после Action FAIL разрешён только если одновременно:

```text
HEAD == recorded before_sha
AND git status --porcelain == empty
AND index has no staged changes
```

Практически `git status --porcelain` уже покрывает staged/unstaged/untracked state, поэтому достаточно закрепить:

```text
trusted retry state = HEAD == before_sha AND working tree clean
```

Если HEAD совпадает, но worktree dirty:

```text
Action To Do + FAIL
stop
```

Failed artifacts не удалять автоматически.

Recovery остаётся отдельной операцией вне skill.

---

# 4. BLOCKER — Verification нельзя исполнять как произвольную shell-строку

Сейчас skill блокирует несколько очевидных конструкций:

```text
;
&&
>
>>
|
curl
rm
```

Это недостаточная security boundary.

Опасную команду можно выразить множеством других способов:

```text
$(...)
`...`
python -c ...
sh -c ...
bash -c ...
wget ...
nc ...
git push ...
find ... -exec ...
newline injection
```

Blacklisting shell syntax не даёт безопасного machine-executable contract.

## Требуемое исправление

Не хранить `Verification` как unrestricted shell program.

Для текущей версии фабрики выбрать один из двух вариантов.

### Предпочтительно — structured verification

Task содержит:

```yaml
Verification:
  runner: pytest
  args:
    - -q
    - tests/auth/test_login.py::test_invalid_token_rejected
```

или эквивалентную структуру Kaneo.

Разрешённые runners задаются repo policy:

```text
pytest
pnpm
npm
cargo
make
... explicit allowlist ...
```

Аргументы передаются как argv, **не через `bash -lc`**.

### Минимальный переходный вариант

Если формат Task сейчас нельзя менять:

- parser Verification обязан запретить любые shell metacharacters/substitution/newlines;
- первый executable должен входить в explicit allowlist из repo policy;
- запрещены shell interpreters (`sh`, `bash`, `zsh`, `python -c` как generic escape hatch);
- затем сформировать argv и запускать без shell interpretation.

Если Verification не проходит validation:

```text
Task To Do + FAIL
```

Это должен быть mechanical validator, а не решение LLM на глаз.

---

# 5. BLOCKER — Cursor execution envelope остаётся prompt-only protection

Skill говорит Cursor:

```text
do not modify .pipe
do not switch/rebase/merge
do not push
do not create PR
do not change Kaneo
```

Это полезный prompt, но не security boundary.

`agent -p --force` разрешает Agent выполнять write/bash operations без обычного подтверждения. Современный Cursor CLI поддерживает project-level permissions и deny rules; deny имеет приоритет над allow. Также Cursor поддерживает sandboxing для ограничения filesystem/network side effects.

Для автоматической фабрики ограничения, критичные для разделения ответственности, следует фиксировать механически.

## Требуемое исправление

Добавить prerequisite:

```text
production repo must contain an approved Cursor CLI permission policy
```

Например project-level:

```text
.cursor/cli.json
```

или актуальный эквивалент Cursor permissions config.

Политика должна запрещать Cursor как минимум:

```text
write .pipe/**
write .git/** where configurable
read/write credential and secret files
shell git push
shell gh
network/MCP access not required for code implementation
other repo-defined forbidden operations
```

Точный синтаксис должен быть сформирован по установленной версии Cursor CLI и проверен тестом deny-rule до включения cron.

Важно: Cursor действительно должен иметь возможность сделать **локальный commit**, поэтому нельзя просто запретить весь `git`.

Нужно разрешить необходимый локальный Git subset и запретить remote/control-plane operations (`push`, PR, branch-management where supported by permission patterns).

Execution envelope оставить как semantic instruction, но не считать его единственной защитой.

---

# 6. ВАЖНО — Outcome drift policy всё ещё неоднозначна

Workflow говорит:

```text
Outcome moved → deterministic sync OR Task FAIL
```

`deterministic sync` не определён.

Это опасно, потому что разные варианты имеют разные последствия:

### rebase

Переписывает Action commit SHA и ломает сохранённый execution evidence.

### merge Outcome → Task

Сохраняет Action commit SHA, но добавляет служебный merge commit, который не соответствует Action.

На текущем этапе фабрики лучше **не разрешать агенту выбирать стратегию**.

## Рекомендация для v0.x

Сделать однозначно:

```text
Outcome tip != pinned outcome_base_sha
→ Task FAIL
```

Без auto-rebase/auto-merge.

Позже можно добавить отдельную deterministic sync policy с обновлением evidence.

Это проще и безопаснее для первого production цикла.

---

# 7. ВАЖНО — local/remote branch existence нужно различать в idempotence

Фраза:

```text
Outcome branch exists → reuse
```

не определяет где branch существует.

Нужно различать минимум четыре состояния:

```text
remote exists / local exists
remote exists / local missing
remote missing / local exists
remote missing / local missing
```

Рекомендуемое поведение:

| Remote | Local | Action |
|---|---|---|
| yes | yes | verify relationship, reuse |
| yes | no | create local tracking remote |
| no | yes | verify expected origin, push remote |
| no | no | create from remote default, then push |

Любая неоднозначность → Task FAIL.

---

# 8. ВАЖНО — `task_gate.sh` остаётся внешним непроверенным dependency

Skill теперь описывает правильный 6-case fake-progress contract:

```text
1. Task PASS / baseline assertion FAIL → PASS
2. baseline test file missing → gate FAIL
3. baseline runner missing → gate FAIL
4. baseline setup/dependency failure → gate FAIL
5. baseline test PASS → fake progress → gate FAIL
6. Task test FAIL → gate FAIL
```

Но сам `.pipe/aidesklab-factory-gates/task_gate.sh` в этом раунде не приложен.

Поэтому подтвердить соответствие **реального gate** контракту невозможно.

Это не дефект текущих трёх skill-файлов, но остаётся deployment blocker.

До cron обязательно прогнать эти 6 сценариев непосредственно против `task_gate.sh`.

---

# 9. Cursor CLI — текущая команда подтверждена

На момент этого review актуальная документация Cursor подтверждает:

```text
agent
```

как основной CLI entrypoint, `-p/--print` для automation и `--force` для разрешения команд в non-interactive режиме.

То есть текущий переход skill на:

```bash
agent -p --force --model auto
```

логичен.

Но именно из-за `--force` project-level deny policy становится ещё важнее.

---

# Что закрыто успешно после второго review

Подтверждаю, что предыдущие замечания в skill устранены:

- deterministic preflight stops теперь получают FAIL;
- zero Actions → Task FAIL;
- malformed Target → Action FAIL;
- `FAIL` recovery использует `before_sha`, а failed HEAD не становится baseline;
- destructive reset исключён из scope;
- branch naming использует Kaneo ID fallback, а не mutable title;
- Outcome base pinning введён;
- evidence/failure records versioned и machine-readable;
- Action ID присутствует в commit identity contract;
- push/PR/guard technical failures получают Task FAIL;
- Target file boundary включает `.pipe/**`, `.git/**`, secrets и repo policy;
- native platform ограничен Linux;
- semantic review/merge остаются вне `devJunior`.

---

# Итоговая оценка

Skill уже близок к пилотному запуску.

Перед первым cron-run я бы потребовал закрыть:

```text
1. Remote publication Outcome branch.
2. Deterministic orphan-commit reconciliation after partial Kaneo failure.
3. Recovery check = HEAD + clean working tree.
4. Structured/allowlisted Verification вместо raw shell.
5. Mechanical Cursor permissions/sandbox policy.
6. Реальный 6-case test task_gate.sh.
```

После пунктов 1–5 skill можно считать архитектурно готовым. Пункт 6 — обязательная проверка deployment tooling перед включением cron.

---

# Итоговый промт агенту — четвёртая правка

Обнови существующий Hermes skill `action-execution` точечно по результатам третьего review.

Работай с:

```text
SKILL.md
references/workflow.md
references/invariants.md
```

Не меняй базовую архитектуру:

```text
devMaster = decomposition + semantic review + merge
devJunior = execution orchestrator
Cursor = единственный production-code writer
mechanical gates = technical verdict
FAIL = anti-loop label
```

Исправь следующие пункты.

## 1. Outcome branch должна существовать на remote

Branch policy должна различать local/remote branch existence.

После `git fetch <remote>`:

```text
remote Outcome exists + local exists → verify/reuse
remote Outcome exists + local missing → create local tracking branch
remote Outcome missing + local exists → verify origin, push Outcome
remote Outcome missing + local missing → create Outcome from remote default, push Outcome
```

Новая Outcome branch обязана быть опубликована **до Task execution/PR**:

```bash
git push -u <remote> <outcome-branch>
```

После push проверить, что remote Outcome ref существует и указывает на ожидаемый SHA.

Failure → Task `To Do + FAIL`.

Persist:

```text
outcome_remote
outcome_branch
outcome_base_sha
```

Task branch создаётся только после подтверждения remote Outcome branch.

## 2. Добавь orphan-commit reconciliation до Cursor

Для каждого unfinished Action до запуска Cursor:

```text
найти commits с marker action(<ACTION_ID>):
```

0 commits → обычное выполнение.

1 commit → **не запускать Cursor**; проверить:

- commit принадлежит Task branch;
- non-merge;
- изменяет ровно Target file;
- parent commit использовать как before_sha;
- Action Gate проходит parent→commit.

Если PASS:

```text
persist/reconstruct AIDESKLAB_EXEC_EVIDENCE_V1
→ transition_guard
→ Done
```

>1 matching commit → Action `FAIL` как state conflict.

Commit marker `action(<ACTION_ID>):` сделать обязательным MUST.

Если возможно, обновить контракт `action_gate.sh` на обязательный:

```bash
--action-id <ACTION_ID>
```

с mechanical verification HEAD commit subject.

Если сам gate находится в другом repo и не должен изменяться этой задачей — явно отметить необходимое изменение как dependency, но в skill всё равно выполнить local commit-marker check перед признанием PASS.

## 3. Recovery trusted state = SHA + clean worktree

После снятия Action FAIL retry Cursor разрешён только когда:

```text
HEAD == recorded before_sha
AND git status --porcelain is empty
```

HEAD совпадает, но working tree/index/untracked state dirty → Action `FAIL`, stop.

Не выполнять destructive cleanup автоматически.

## 4. Убери unrestricted shell Verification

`Verification` нельзя считать безопасной только по blacklist `; | rm curl ...`.

Предпочтительный contract:

```yaml
Verification:
  runner: <allowlisted runner>
  args:
    - <arg>
```

Runner должен входить в explicit repo allowlist/AGENTS policy.

Arguments запускать как argv без shell interpretation.

Если текущий Kaneo format пока остаётся строкой:

- полностью запретить shell metacharacters, substitution и multiline;
- запретить shell interpreters/generic escape commands;
- разрешать только explicit executable allowlist;
- parse в argv;
- не использовать `bash -lc` для Task Verification.

Validation failure → Task FAIL.

Validation должна быть mechanical, не свободным решением LLM.

## 5. Добавь mechanical Cursor permission prerequisite

Execution envelope оставить, но больше не считать его security boundary.

Production repo должен иметь проверенную Cursor CLI permission/sandbox policy.

Skill preflight обязан проверить наличие/валидность разрешённой factory policy.

Policy должна механически запрещать Cursor минимум:

```text
write .pipe/**
write/read secrets/credentials as defined by repo policy
remote git push
PR commands / gh
automation-control operations
ненужный network/MCP access
```

При этом Cursor должен сохранять возможность:

```text
редактировать Target file
читать нужный repository context
запускать разрешённые tests/tools
создать локальный commit
```

Не запрещай весь `git`, если это ломает commit.

Используй актуальный Cursor project permission format установленной версии (`.cursor/cli.json` / актуальный эквивалент), deny rules и при необходимости sandbox.

Перед cron наличие policy должно быть prerequisite; отсутствие → Task FAIL.

## 6. Убери неоднозначный Outcome auto-sync

Для текущей версии skill не разрешать devJunior выбирать между rebase/merge.

Правило v0.x:

```text
current Outcome tip != pinned outcome_base_sha
→ Task FAIL
```

Без автоматического rebase/merge.

Причина: rebase меняет Action commit SHA, merge добавляет служебные commits и требует отдельной evidence policy.

Outcome synchronization оставить отдельным будущим workflow.

## 7. Partial Kaneo write recovery

Явно описать следующий cron-run после:

```text
Action Gate PASS
but evidence/status Kaneo write failed
```

Он обязан сначала выполнить orphan-commit reconciliation из пункта 2.

Cursor повторно не запускается, пока Git commit текущего Action уже существует и может быть подтверждён.

## 8. task_gate deployment dependency

Сохранить 6-case fake-progress contract.

Добавить в prerequisites/verification, что cron запрещено включать до отдельного подтверждения production `.pipe/aidesklab-factory-gates/task_gate.sh` этими шестью test cases.

Не пытайся считать описание contract доказательством реализации самого gate.

## Scope

Не добавлять:

```text
semantic review
merge
Outcome execution
Outcome Review
rescue
adversary
decomposition
branch recovery
```

После изменений выдай краткий отчёт:

1. изменённые файлы;
2. final local/remote branch state machine;
3. orphan-commit reconciliation algorithm;
4. trusted recovery condition;
5. Verification execution contract;
6. Cursor mechanical permission policy requirement;
7. подтверди, что Outcome drift теперь всегда FAIL, а не неопределённый auto-sync.
