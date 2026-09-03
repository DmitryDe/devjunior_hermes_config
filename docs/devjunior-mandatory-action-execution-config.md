# devJunior — обязательное использование `action-execution`

## Цель

Обеспечить инвариант:

```text
ни один Kaneo Task не может попасть в execution-loop devJunior,
если action-execution не был загружен runtime-механизмом ДО первого model turn.
```

Важно разделять:

```text
100% skill loading  — можно обеспечить механически;
100% послушание LLM — нельзя обеспечить одним prompt/SOUL.
```

Правильная архитектура:

```text
entrypoint mechanically loads skill
→ SOUL запрещает обход workflow
→ action-execution задаёт алгоритм
→ gates доказывают фактическое выполнение
→ FAIL блокирует недоказанное состояние
```

Не полагаться на обычный Hermes skill discovery (`skills_list → модель сама решает вызвать skill_view`). Для production worker это только fallback.

---

## 1. Сделать skill profile-level dependency devJunior

`action-execution` не должен зависеть от текущего product repo.

Рекомендуемый источник истины:

```text
devJunior config repository
└── skills/
    └── autonomous-ai-agents/
        └── action-execution/
```

В profile `config.yaml` указать каталог как `external_dirs`, например:

```yaml
skills:
  external_dirs:
    - /absolute/path/to/devjunior-config/skills
  project_discovery: false
```

`project_discovery: false` для `devJunior` рекомендован намеренно:

- product repo не сможет подложить другой project-local skill с именем `action-execution`;
- не возникает precedence `project skill > profile/external skill`;
- `AGENTS.md` product repo продолжает загружаться отдельно через `workdir`;
- единственным `action-execution` остаётся версия из конфигурации devJunior.

Не держать параллельно вторую копию `action-execution` в profile-local `skills/`, иначе local skill имеет precedence над `external_dirs`.

Если вместо `external_dirs` используется deployment-copy в `$HERMES_HOME/skills/`, правило то же: должен существовать ровно один canonical экземпляр.

---

## 2. Startup preflight: fail closed

`external_dirs` с отсутствующим каталогом Hermes может просто пропустить. Поэтому gateway/cron worker нельзя запускать без отдельного preflight.

Перед стартом `devJunior` проверять механически:

```text
1. canonical skill directory exists;
2. SKILL.md exists;
3. references/workflow.md exists;
4. references/invariants.md exists;
5. skill name == action-execution;
6. expected version == 0.5.1;
7. нет другой action-execution с более высоким precedence;
8. hash package совпадает с pinned manifest.
```

Рекомендую хранить в config repo manifest:

```text
skills.lock
```

например:

```yaml
action-execution:
  version: 0.5.1
  sha256: <hash-of-canonical-package>
```

И добавить `ExecStartPre` / startup script для сервиса devJunior.

Инвариант:

```text
skill missing / duplicate / wrong hash / wrong version
→ devJunior gateway + cron worker НЕ стартуют
```

---

## 3. SOUL.md: mandatory Task routing

В `SOUL.md` devJunior добавить короткий системный policy как defense-in-depth:

```md
# TASK EXECUTION POLICY

For every Kaneo entity with:

- label `Task`
- assigned to `devJunior`

execution is permitted only through the preloaded `action-execution` skill.

Never execute a Task through generic coding behaviour.
Never implement a Task directly from its Kaneo text.
Never substitute another coding skill for `action-execution`.
Never bypass Action Gate, Task Gate, FAIL semantics, or transition_guard.

If a Task execution session does not contain the preloaded
`action-execution` instructions, do not execute the Task and do not call
Cursor. Stop with `SKILL_NOT_LOADED`.

Cron, Telegram, CLI, and any future dispatcher are subject to the same rule.
```

Не копировать workflow skill в SOUL. SOUL отвечает только за routing:

```text
Task → action-execution
```

---

## 4. Cron: skill должен быть attached к job нативно

Не использовать prompt вида:

```text
"прочитай action-execution и выполни Task"
```

Использовать Hermes skill-backed job:

```text
skills:
  - action-execution
```

Hermes загружает attached skill до task prompt.

Пример:

```bash
hermes cron create "every 5m"   "Process at most one eligible Kaneo Task assigned to devJunior. If none exists, finish without changes."   --skill action-execution   --workdir /absolute/path/to/product-repo   --name "devjunior:<product>"
```

Prompt cron-job должен быть минимальным. Workflow в нём не дублировать.

---

## 5. Один cron job на product repo

Для текущей архитектуры рекомендую:

```text
1 product repo = 1 devJunior cron job
```

Причина — `workdir`.

Hermes при cron `workdir`:

- загружает project context (`AGENTS.md` / rules);
- запускает terminal/file tools относительно нужного repo;
- валидирует абсолютный существующий путь;
- jobs с `workdir` выполняются scheduler'ом последовательно.

Для множества repo:

```text
devjunior:product-a → workdir=/repos/product-a → skill=action-execution
devjunior:product-b → workdir=/repos/product-b → skill=action-execution
devjunior:product-c → workdir=/repos/product-c → skill=action-execution
```

Не делать пока один глобальный LLM-cron, который выбирает Task из любого repo и затем сам `cd`: системный project context будет определён не тем repo.

Позже это может генерировать reconciler/control-plane.

---

## 6. Cron config: fail-closed defaults

В profile `config.yaml`:

```yaml
cron:
  preflight: true
  model_drift_guard: true
  allow_agent_scheduling: false
```

`preflight: true` — Hermes блокирует job до LLM-call, если attached skill/prerequisites не готовы.

`model_drift_guard: true` — unattended worker не должен неожиданно перейти на другую model/provider config.

`allow_agent_scheduling: false` — cron-run devJunior не должен создавать или менять собственные cron jobs.

Дополнительно желательно pin model/provider прямо в job, если используемая версия job schema это поддерживает.

---

## 7. Tool-use enforcement

Для devJunior:

```yaml
agent:
  tool_use_enforcement: true
```

Это не загружает skill, но уменьшает failure mode:

```text
"я бы выполнил..."
"нужно запустить..."
```

вместо реальных tool calls.

---

## 8. Tool-loop hard stop

Для автономного worker:

```yaml
tool_loop_guardrails:
  warnings_enabled: true
  hard_stop_enabled: true

  warn_after:
    exact_failure: 2
    same_tool_failure: 3
    idempotent_no_progress: 2

  hard_stop_after:
    exact_failure: 5
    same_tool_failure: 8
    idempotent_no_progress: 5
```

Это второй anti-loop слой:

```text
Kaneo FAIL
→ блокирует повторные execution runs;

Hermes tool-loop hard stop
→ блокирует бессмысленный цикл tool calls внутри одного run.
```

---

## 9. Не давать devJunior менять свой execution skill

Production worker не должен иметь normal self-modification path для `action-execution`.

Минимум:

```text
- не использовать skill_manage для action-execution;
- canonical config repo deployment считать read-only для runtime;
- startup hash должен ловить любое изменение;
- изменение skill выполняется только через обычный PR в config repo.
```

Если profile devJunior не нуждается в skill management — не давать ему writable skill-management surface.

Правильно:

```text
skill/config defect
→ FAIL / stop
→ отдельная задача на изменение config repo
```

---

## 10. Telegram / gateway execution

Если Task можно вручную запускать через Telegram, SOUL недостаточно.

Лучший native-вариант Hermes — отдельный Telegram topic с binding:

```yaml
platforms:
  telegram:
    extra:
      dm_topics:
        - chat_id: <operator-id>
          topics:
            - name: devJunior Tasks
              skill: action-execution
```

Для специализированного devJunior можно дополнительно:

```yaml
ignore_root_dm: true
```

чтобы root DM был lobby и Task нельзя было случайно запустить вне skill-bound topic.

Схема:

```text
Telegram Task topic
→ native skill binding
→ action-execution loaded
→ user instruction
```

### Ограничение

Обычный single-thread Telegram DM нельзя считать гарантированным auto-load surface. Там skill discovery остаётся model-driven.

Для 100% routing выбрать одно:

```text
A. только skill-bound Telegram topic;

B. gateway wrapper, который для Task-entrypoint
   механически inject/prepend action-execution;

C. собственный Hermes patch с mandatory profile/chat skill binding.
```

Вариант «в SOUL написано использовать skill» гарантией не считать.

---

## 11. CLI/manual invocation

Не:

```bash
hermes -p devjunior "execute Task ..."
```

а:

```bash
hermes -p devjunior chat   -s action-execution   -q "Execute Kaneo Task <id>"
```

Рекомендую скрыть это за единственным wrapper entrypoint:

```text
devjunior-task <task-id> <repo>
```

Wrapper:

```text
validate skill hash
→ validate repo
→ invoke Hermes with -s action-execution
→ set exact workdir
```

Generic `hermes` CLI не считать production Task-entrypoint.

---

## 12. Не использовать `-z` для обязательного skill preload

Для этого worker не использовать:

```text
hermes -z ...
```

В Hermes были/есть проблемы с forwarding `--skills` в отдельных one-shot surfaces.

Для ручного unattended вызова использовать:

```text
hermes chat -s action-execution -q ...
```

Для cron — native attached skill.

---

## 13. Approvals для cron

Не рекомендую:

```yaml
approvals:
  cron_mode: approve
```

Это blanket auto-approval dangerous commands.

Начать с:

```yaml
approvals:
  mode: smart
  cron_mode: deny
```

и провести pilot.

Если конкретная необходимая операция фабрики попадает под dangerous-command classifier, лучше вынести её в детерминированный wrapper/gate или изменить command shape, чем открывать cron целиком через `approve`.

---

## 14. Runtime evidence

Для production нужен audit invariant:

```text
run_id
task_id
profile=devjunior
skill=action-execution
skill_version=0.5.1
skill_sha256=<expected>
workdir=<product repo>
source=cron|telegram|cli
```

Это позволяет после pilot доказать:

```text
Task execution никогда не стартовал без exact skill package.
```

---

## 15. Рекомендуемый итоговый `config.yaml`

```yaml
skills:
  external_dirs:
    - /absolute/path/to/devjunior-config/skills
  project_discovery: false

agent:
  tool_use_enforcement: true

cron:
  preflight: true
  model_drift_guard: true
  allow_agent_scheduling: false

tool_loop_guardrails:
  warnings_enabled: true
  hard_stop_enabled: true

  warn_after:
    exact_failure: 2
    same_tool_failure: 3
    idempotent_no_progress: 2

  hard_stop_after:
    exact_failure: 5
    same_tool_failure: 8
    idempotent_no_progress: 5

approvals:
  mode: smart
  cron_mode: deny
```

Плюс:

```text
SOUL.md mandatory Task routing
startup skill hash/version preflight
skill-backed cron job PER PRODUCT REPO
Telegram skill-bound topic OR deterministic gateway wrapper
CLI wrapper with `chat -s action-execution`
```

---

## 16. Что реально даёт 100%

После этих изменений Task может прийти только через:

```text
Cron
  → attached skill=action-execution

Telegram
  → skill-bound Task topic

CLI
  → wrapper → chat -s action-execution

future Kaneo dispatcher
  → explicit skill=action-execution
```

Запрещённый путь:

```text
task event
→ bare devJunior session
→ модель сама решает, читать ли skill
```

Именно это превращает skill из рекомендации модели в обязательную execution dependency.

---

## Рекомендуемый порядок внедрения

```text
1. canonical skill path + duplicate prevention
2. startup hash/version preflight
3. skills.project_discovery=false
4. SOUL Task routing policy
5. agent.tool_use_enforcement=true
6. tool-loop hard-stop
7. cron preflight/model-drift config
8. skill-backed cron per product repo
9. Telegram topic binding / gateway routing
10. CLI wrapper
11. pilot Task + audit trace
```

После этого следующий объект проверки — конфигурация devJunior + один реальный cron pilot, а не сам Markdown skill.
