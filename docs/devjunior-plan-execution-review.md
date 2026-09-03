# Оценка плана `devJunior mandatory routing`

## Вердикт

**Не выполнять весь план одним прогоном Grok 4.6 в Cursor.**

Сам план хороший: он достаточно детализирован, содержит stop-conditions, фиксированные branch names, `1 Action = 1 file = 1 commit`, проверки после каждого Action и явно запрещает додумывать значения. fileciteturn12file0

Проблема — не качество плана, а его runtime-форма:

```text
Bootstrap
→ Outcome branch
→ Task 1
→ PR
→ merge
→ Task 2
→ PR
→ merge
→ ...
→ Task 7
→ final verification
```

Это слишком длинная цепочка mutable external state для одного model session.

---

# Почему один прогон рискован

## 1. Семь последовательных Task boundary

План требует:

```text
следующий Task только после merge предыдущего PR
```

То есть один run должен многократно:

- переключать branch;
- делать commits;
- создавать PR;
- merge;
- обновлять Outcome;
- снова создавать следующую branch.

Для Grok 4.6 это значительно опаснее, чем семь независимых кодовых изменений.

---

## 2. Есть runtime-dependent решения

В Bootstrap модель должна определить:

```text
PROFILE_ROOT
ACTION_EXECUTION_DIR
ACTION_EXECUTION_SKILLS_ROOT
Hermes CLI syntax
Telegram configured yes/no
deployment mechanism
existing cron jobs
model/provider
```

Дальнейшие Tasks зависят от этих результатов.

Ошибка или неверная интерпретация одного bootstrap-факта будет размножена по всему оставшемуся run.

---

## 3. Task 4 условный

```text
Telegram configured?
yes → Task 4
no  → NOT_APPLICABLE
```

Это нормально для отдельной итерации, но в очень длинном execution trace увеличивает вероятность, что модель забудет условие и начнёт создавать Telegram config «по плану».

---

## 4. Task 5 самый опасный

Cron wrapper требует адаптации под **фактический Hermes CLI**, обнаруженный через:

```text
hermes cron --help
cron create --help
cron edit --help
```

То есть здесь недостаточно просто транслировать текст плана в код.

Это хороший естественный checkpoint.

---

## 5. Task 6 зависит от всего предыдущего

`audit-devjunior-runtime.sh` должен проверять уже созданные:

```text
config
SOUL
skills.lock
verify-action-execution.sh
devjunior-task.sh
ensure-devjunior-cron.sh
audit-devjunior-cron.sh
Telegram config
```

Если дать его Grok в той же огромной session, он склонен подгонять audit под собственную реализацию.

Лучше запускать Task 6 в новом контексте уже против фактического repository state.

---

# Рекомендуемое разделение

Оптимально: **4 итерации**.

Это достаточно крупные блоки, чтобы не плодить лишнюю ручную работу, но между ними есть хорошие mechanical checkpoints.

---

# Итерация 1 — Bootstrap + runtime foundation

Выполнить:

```text
Bootstrap B1–B5
Outcome branch
Task 1
Task 2
```

То есть:

```text
config.yaml
SOUL.md
skills.lock
verify-action-execution.sh
```

## Почему вместе

Task 1 и Task 2 формируют фундамент:

```text
Hermes видит canonical skill
+
profile запрещает shadowing
+
skill version/hash доказуемы
```

Без этого остальные entrypoints вообще не стоит строить.

## Checkpoint после итерации

Обязательно:

```bash
./scripts/verify-action-execution.sh
hermes -p devjunior skills list
hermes -p devjunior config show
```

Должен быть PASS.

После этого зафиксировать:

```text
PROFILE_ROOT
ACTION_EXECUTION_SKILLS_ROOT
Hermes version
actual skill visibility
```

---

# Итерация 2 — User-facing entrypoints

Выполнить:

```text
Task 3
Task 4
```

То есть:

```text
devjunior-task.sh
Telegram routing, если configured
```

## Почему вместе

Оба Task отвечают за interactive/manual entrypoints:

```text
CLI
Telegram
```

Они не затрагивают scheduler.

## Checkpoint

Проверить:

```text
manual wrapper всегда содержит -s action-execution
negative workdir tests проходят
Telegram topic bound к action-execution либо Task 4 = NOT_APPLICABLE
```

Никакой bare Task execution route не должен остаться как supported entrypoint.

---

# Итерация 3 — Cron

Выполнить только:

```text
Task 5
```

Это намеренно отдельная итерация.

Создаются:

```text
ensure-devjunior-cron.sh
audit-devjunior-cron.sh
```

## Почему отдельно

Это наиболее environment-sensitive часть:

- зависит от реального Hermes CLI;
- create/edit syntax может отличаться;
- работает с runtime cron state;
- есть idempotent reconciliation;
- provider/model pin;
- обязательный read-back;
- нельзя напрямую менять jobs.json.

Grok должен иметь свежий короткий контекст и сосредоточиться только на этом.

## Checkpoint

```bash
bash -n scripts/ensure-devjunior-cron.sh
bash -n scripts/audit-devjunior-cron.sh
./scripts/audit-devjunior-cron.sh
```

Если существуют safe test values — один create/update/read-back managed job.

Если production values отсутствуют — **не придумывать их**.

---

# Итерация 4 — Independent audit + runbook

Выполнить:

```text
Task 6
Task 7
Final verification
```

Создаются:

```text
audit-devjunior-runtime.sh
docs/devjunior-task-routing-pilot.md
```

## Почему отдельная session критична

Task 6 фактически является acceptance-test предыдущих трёх итераций.

Новый Grok context получает **готовый repo**, а не собственную память о том, как он его писал.

Это полезный принцип:

```text
implementation session != acceptance session
```

Так выше шанс, что audit реально проверяет state, а не подтверждает предположения предыдущего run.

---

# Рекомендуемый запуск Grok

Каждой итерации передавать:

```text
1. исходный полный plan file;
2. отдельную короткую инструкцию:
   "Выполни только Iteration N / перечисленные Tasks.
    Остальные Tasks не начинай.";
3. актуальную Outcome branch;
4. требование STOP после checkpoint.
```

Не вырезать Tasks из master-plan и не создавать четыре расходящиеся версии.

**Master plan остаётся единственным source of truth.**

---

# Что должен делать Grok в конце каждой итерации

Не писать длинный отчёт.

Только:

```text
ITERATION: <N>
STATUS: PASS | FAIL

Merged Tasks:
- ...

Outcome HEAD:
<sha>

Verification:
- <command> → PASS
- <command> → PASS

Blocked:
<none | exact reason>
```

Если `FAIL`:

```text
не начинать следующую итерацию
```

---

# Дополнительная правка самого плана

Я бы добавил в начало master-plan один раздел:

```text
## Execution batching

This master plan MUST NOT be executed in one agent run.

Iteration 1: Bootstrap + Tasks 1–2
Iteration 2: Tasks 3–4
Iteration 3: Task 5
Iteration 4: Tasks 6–7 + Final Verification

At the end of each iteration STOP.
The next iteration starts in a fresh Cursor agent session
against the current merged Outcome branch.
```

Это снимет последний источник неоднозначности для Grok.

---

# Итоговая оценка

### Один прогон

```text
Вероятность полного корректного исполнения: средняя.
```

План достаточно точный, но слишком много state transitions и environment-dependent branching.

Я бы **не доверял one-shot Grok 4.6** именно из-за orchestration length.

### 4 итерации

```text
Вероятность корректного исполнения: высокая.
```

Каждая итерация имеет естественный verification boundary, а последняя выполняет независимый audit уже готового state.

### Дробить ещё мельче

Не нужно.

`1 Task = 1 Grok run` даст 7 sessions и создаст больше coordination overhead, чем пользы.

**Оптимум для этого плана: 4 последовательных Cursor/Grok runs.**
