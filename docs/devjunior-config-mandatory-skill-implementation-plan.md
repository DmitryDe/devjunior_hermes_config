---
name: devJunior mandatory action-execution routing
overview: >
  Доработать repository-конфигурацию Hermes-профиля devJunior так, чтобы любой Kaneo Task
  исполнялся только в session, где action-execution загружен до первого model turn.
  Task = отдельная PR-ветка; Action = ровно один файл = ровно один commit.
isProject: false
---

# devJunior — обязательное использование `action-execution`

## Outcome

Сделать `action-execution` обязательной execution dependency профиля `devJunior`.

Допустимые Task entrypoints после реализации:

```text
Cron      → skill-backed job → action-execution → product workdir → Task
Telegram  → skill-bound Task topic → action-execution → Task
CLI       → repository wrapper → hermes -p devjunior ... -s action-execution → Task
```

Запрещённый путь:

```text
bare devJunior session → Task text → модель сама решает, читать ли skill
```

## Общие правила для исполнителя

1. Выполнять Tasks только в указанном порядке.
2. Каждый Task — отдельная branch и PR в Outcome branch.
3. Каждый Action меняет/создаёт ровно один файл и заканчивается ровно одним commit.
4. Не объединять Actions и не переносить изменения между ними.
5. Не менять `action-execution` (`SKILL.md`, `workflow.md`, `invariants.md`).
6. Не искать, не clone'ить и не менять `.pipe`.
7. Не менять Hermes source.
8. Не редактировать `~/.hermes/cron/jobs.json` напрямую.
9. Не придумывать model/provider/chat_id/product paths.
10. Если план требует значение из существующей конфигурации — использовать exact existing value.
11. Failure Verification любого Action → stop, следующий Action не начинать.

---

# Bootstrap — inspection only, без commit

Выполнить до Task 1.

## B1. Repository root

```bash
git rev-parse --show-toplevel
```

Сохранить как `REPO_ROOT`.

## B2. Profile root

В текущем repo найти ровно одну директорию профиля `devjunior`, содержащую одновременно:

```text
config.yaml
SOUL.md
```

Назвать `PROFILE_ROOT`.

Если таких директорий 0 или >1 — STOP.

## B3. Canonical action-execution

Найти ровно один package с:

```yaml
name: action-execution
version: 0.5.1
```

Он обязан содержать:

```text
SKILL.md
references/workflow.md
references/invariants.md
```

Сохранить:

```text
ACTION_EXECUTION_DIR
ACTION_EXECUTION_SKILLS_ROOT
```

`ACTION_EXECUTION_SKILLS_ROOT` — директория, которую Hermes должен сканировать через `skills.external_dirs`.

0 или >1 package → STOP.

## B4. Hermes profile

Проверить:

```bash
hermes --version
hermes profile show devjunior
hermes -p devjunior skills list
hermes -p devjunior cron status
```

Profile должен существовать.

## B5. Existing runtime values

Существующими Hermes CLI/config средствами определить и сохранить без изменения:

```text
current devjunior model
current devjunior provider
existing cron.model / cron.model_provider, если заданы
Telegram configured yes/no
existing authorized Telegram chat_id, если Telegram configured
existing cron jobs whose name starts with "devjunior:"
```

Не менять состояние.

---

# Branches

Outcome branch:

```text
outcome/devjunior-mandatory-action-execution
```

Tasks:

```text
Task 1 → task/devjunior-runtime-policy
Task 2 → task/devjunior-skill-integrity
Task 3 → task/devjunior-cli-entrypoint
Task 4 → task/devjunior-telegram-routing
Task 5 → task/devjunior-cron-routing
Task 6 → task/devjunior-runtime-audit
Task 7 → task/devjunior-pilot-readiness
```

Каждый Task branch создавать от актуальной Outcome branch. После Task Verification открыть PR Task → Outcome. Следующий Task начинать только после merge предыдущего.

---

# Task 1 — Runtime policy

## Goal

Profile fail-closes generic Task execution и unattended loops; project-local skill не может shadow canonical `action-execution`.

## Task Verification

Должно выполняться:

```text
skills.project_discovery=false
ACTION_EXECUTION_SKILLS_ROOT ∈ skills.external_dirs
agent.tool_use_enforcement=true
agent.execution_guidance=true
tool_loop_guardrails.hard_stop_enabled=true
cron.preflight=true
cron.model_drift_guard=true
cron.allow_agent_scheduling=false
approvals.mode=smart
approvals.cron_mode=deny
SOUL contains TASK EXECUTION POLICY
```

## Action 1.1 — Profile config

### Target file

```text
<PROFILE_ROOT>/config.yaml
```

### Exact changes

Сохранить все unrelated settings.

Обеспечить:

```yaml
skills:
  external_dirs:
    - <ACTION_EXECUTION_SKILLS_ROOT>
  project_discovery: false

agent:
  tool_use_enforcement: true
  execution_guidance: true

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

cron:
  preflight: true
  model_drift_guard: true
  allow_agent_scheduling: false

approvals:
  mode: smart
  cron_mode: deny
```

Rules:

- existing legitimate `skills.external_dirs` сохранить;
- canonical skills root добавить один раз;
- existing `cron.model` / `cron.model_provider` сохранить;
- existing `loop_caps` сохранить;
- Telegram в этом Action не менять;
- model/provider, `.env`, MCP, terminal cwd не менять.

### Verification

```bash
hermes -p devjunior config show
hermes -p devjunior skills list
```

No parse errors; `action-execution` visible.

### Commit

```text
config(devjunior): enforce task runtime policy
```

## Action 1.2 — SOUL routing invariant

### Target file

```text
<PROFILE_ROOT>/SOUL.md
```

### Append exactly once

```md
# TASK EXECUTION POLICY

For every Kaneo entity with label `Task` assigned to `devJunior`,
execution is permitted only when the current session has the
`action-execution` skill preloaded before the task instruction.

Never execute a Kaneo Task through generic coding behavior.
Never implement a Task directly from Task text.
Never substitute another coding skill for `action-execution`.
Never bypass Action Gate, Task Gate, FAIL semantics, execution evidence,
or transition_guard.

If a Task execution request reaches a session where `action-execution`
was not preloaded, do not execute the Task and do not call Cursor.
Stop with the exact reason `SKILL_NOT_LOADED`.

Cron, Telegram, CLI, and future dispatchers are subject to the same rule.

The detailed Task execution procedure belongs only to `action-execution`.
Do not duplicate or reconstruct that procedure from memory.
```

Не копировать workflow skill в SOUL.

### Verification

Markers `TASK EXECUTION POLICY` и `SKILL_NOT_LOADED` встречаются ровно один раз.

### Commit

```text
policy(devjunior): require action-execution for tasks
```

---

# Task 2 — Skill integrity

## Goal

Runtime должен доказуемо использовать exact `action-execution v0.5.1`, а missing/wrong/duplicate package должен fail closed.

## Action 2.1 — Lock package

### Target file

```text
<PROFILE_ROOT>/skills.lock
```

### Exact format

```text
ACTION_EXECUTION_NAME=action-execution
ACTION_EXECUTION_VERSION=0.5.1
ACTION_EXECUTION_RELATIVE_DIR=<repo-relative path REPO_ROOT → ACTION_EXECUTION_DIR>
ACTION_EXECUTION_PACKAGE_SHA256=<computed hash>
```

### Hash algorithm

Для всех regular files внутри package:

1. path relative to skill root;
2. SHA256 file;
3. sort paths bytewise;
4. aggregate lines `<sha256><two spaces><relative-path>\n`;
5. SHA256 aggregate.

Не включать `.git`, `__pycache__`, editor/temp files.

### Verification

Повторный расчёт даёт тот же hash.

### Commit

```text
chore(devjunior): pin action-execution package
```

## Action 2.2 — Skill integrity preflight

### Target file

```text
<PROFILE_ROOT>/scripts/verify-action-execution.sh
```

### Requirements

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Определять `PROFILE_ROOT` относительно path самого script. Hard-coded clone path запрещён.

Проверять:

1. `skills.lock` exists and all four keys present.
2. canonical package path resolves inside `REPO_ROOT`.
3. required three skill files exist.
4. `SKILL.md` exact name/version match lock.
5. package hash exact match.
6. `hermes -p devjunior skills list` contains `action-execution`.
7. `skills.project_discovery` in config is false.
8. canonical skills root is configured in `skills.external_dirs`, если package не находится непосредственно в profile-local skills.
9. нет higher-precedence duplicate `action-execution` в profile-local skills, который shadow'ит canonical external package.
10. script ничего не исправляет автоматически.

Success output:

```text
ACTION_EXECUTION_PREFLIGHT=PASS
name=action-execution
version=0.5.1
sha256=<actual>
```

Failure:

```text
ACTION_EXECUTION_PREFLIGHT=FAIL
reason=<short-machine-readable-reason>
```

non-zero.

### Verification

```bash
bash -n <PROFILE_ROOT>/scripts/verify-action-execution.sh
chmod +x <PROFILE_ROOT>/scripts/verify-action-execution.sh
<PROFILE_ROOT>/scripts/verify-action-execution.sh
```

Exit 0.

### Commit

```text
feat(devjunior): verify action-execution integrity
```

---

# Task 3 — Mandatory CLI/manual entrypoint

## Goal

Штатный manual Task execution всегда preloads skill и задаёт product repo.

## Action 3.1 — Task wrapper

### Target file

```text
<PROFILE_ROOT>/scripts/devjunior-task.sh
```

### Interface

```bash
devjunior-task.sh <task-id> <absolute-product-repo>
```

Ровно два args.

### Validation

До Hermes call:

1. `verify-action-execution.sh` → exit 0.
2. task-id matches:
   ```text
   ^[A-Za-z0-9_-]+$
   ```
3. workdir absolute.
4. workdir exists.
5. `git -C "$workdir" rev-parse --is-inside-work-tree` succeeds.
6. exists:
   ```text
   $workdir/.pipe/aidesklab-factory-gates/
   ```

### Only allowed Hermes invocation

Semantically exact:

```bash
hermes -p devjunior \
  --in "<absolute-product-repo>" \
  chat \
  -s action-execution \
  -q "Execute Kaneo Task <task-id> assigned to devJunior. Execute only this Task through the preloaded action-execution skill."
```

Если installed CLI требует другое placement global `--in`, подтвердить через `hermes --help`, но обязательны:

```text
profile=devjunior
workdir=exact product repo
skill preloaded=-s action-execution
```

No fallback:

```text
-z
bare chat without -s
"please read the skill"
```

### Verification

```bash
bash -n <PROFILE_ROOT>/scripts/devjunior-task.sh
```

Negative tests: missing task-id, relative repo, non-git repo, missing `.pipe` → non-zero.

### Commit

```text
feat(devjunior): add mandatory task entrypoint
```

---

# Task 4 — Telegram routing

## Goal

Если Telegram configured, Kaneo Task requests идут только через skill-bound topic. Root DM не является alternative Task surface.

## Action 4.1 — Bind Task topic

### Target file

```text
<PROFILE_ROOT>/config.yaml
```

### If Telegram NOT configured

Не создавать fake Telegram config/chat_id/token. Action = NOT_APPLICABLE, no commit.

### If Telegram configured

Использовать только existing authorized `chat_id`.

Обеспечить:

```yaml
platforms:
  telegram:
    extra:
      ignore_root_dm: true
```

Под existing authorized `chat_id` найти topic:

```text
name: devJunior Tasks
```

Если существует:

```yaml
skill: action-execution
```

Если отсутствует — добавить:

```yaml
- name: devJunior Tasks
  skill: action-execution
```

Не задавать `thread_id` вручную для нового topic.

Существующий `thread_id`, icon fields и другие topics сохранить.

### Prohibitions

Не менять token/chat authorization; не bind skill к General; не оставлять root DM как Task surface.

### Verification

YAML parses; structure contains `ignore_root_dm: true` and exact Task topic skill binding.

### Commit

```text
config(devjunior): bind task topic to action-execution
```

---

# Task 5 — Skill-backed cron routing

## Goal

Repo предоставляет единственный supported mechanism создания/обновления Task cron jobs. Невозможно provision managed Task job без `action-execution`, product `workdir`, provider/model pin.

### Managed job contract

```text
name: devjunior:<product-id>
skill list: exactly ["action-execution"]
workdir: absolute existing product repo
provider: explicit
model: explicit
prompt: exact managed prompt
```

Managed prompt:

```text
Process at most one eligible Kaneo Task assigned to devJunior for this product repository.
The action-execution skill is already preloaded and is the only permitted Task execution workflow.
If no eligible Task exists, finish without repository changes.
```

Default schedule for new job:

```text
every 5m
```

Existing schedule сохранять, если caller не передал schedule.

## Action 5.1 — Cron ensure wrapper

### Target file

```text
<PROFILE_ROOT>/scripts/ensure-devjunior-cron.sh
```

### Interface

```bash
ensure-devjunior-cron.sh \
  <product-id> \
  <absolute-product-repo> \
  <provider> \
  <model> \
  [schedule]
```

### Validation

1. skill preflight PASS.
2. product-id `^[A-Za-z0-9_-]+$`.
3. workdir absolute/existing/git.
4. `.pipe/aidesklab-factory-gates/` exists.
5. provider/model non-empty.
6. schedule non-empty after applying default.

### Existing job

Managed name:

```text
devjunior:<product-id>
```

Resolve via Hermes CLI and, if necessary, read profile cron `jobs.json` read-only. Never write it.

Require 0 or 1 exact match. >1 → non-zero.

### Create

Use Hermes CLI, not natural-language agent:

```bash
hermes -p devjunior cron create \
  "<schedule>" \
  "<managed prompt>" \
  --name "devjunior:<product-id>" \
  --skill action-execution \
  --workdir "<absolute-product-repo>" \
  --provider "<provider>" \
  --model "<model>"
```

### Update

If one existing job, use:

```bash
hermes -p devjunior cron edit <job-id>
```

to enforce exact:

```text
skills=["action-execution"]
workdir
provider
model
prompt
```

If caller supplied schedule, enforce it; otherwise preserve current schedule.

Do not attach another Task workflow skill.

### Mandatory read-back

After create/edit re-read job state and prove all exact contract fields. Mismatch → non-zero.

### Verification

```bash
bash -n <PROFILE_ROOT>/scripts/ensure-devjunior-cron.sh
```

Negative argument tests only unless exact deployment product/provider/model values are available.

### Commit

```text
feat(devjunior): enforce skill-backed task cron
```

## Action 5.2 — Cron audit

### Target file

```text
<PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
```

### Behavior

Read-only audit of every job whose name starts `devjunior:`.

Require each:

```text
skills exactly ["action-execution"]
absolute workdir
workdir exists
provider pinned
model pinned
```

Also require config:

```text
cron.preflight=true
cron.model_drift_guard=true
cron.allow_agent_scheduling=false
```

Success:

```text
DEVJUNIOR_CRON_AUDIT=PASS
jobs=<N>
```

Failure non-zero with job/reason.

No managed jobs → `PASS jobs=0`.

### Verification

```bash
bash -n <PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
<PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
```

### Commit

```text
feat(devjunior): audit task cron routing
```

---

# Task 6 — Unified runtime audit

## Goal

Одна read-only команда доказывает repo-level readiness профиля.

## Action 6.1 — Runtime audit

### Target file

```text
<PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
```

### Must check

1. `verify-action-execution.sh` PASS.
2. Config exact:
   ```text
   skills.project_discovery=false
   agent.tool_use_enforcement=true
   agent.execution_guidance=true
   tool_loop_guardrails.hard_stop_enabled=true
   cron.preflight=true
   cron.model_drift_guard=true
   cron.allow_agent_scheduling=false
   approvals.mode=smart
   approvals.cron_mode=deny
   ```
3. SOUL markers:
   ```text
   TASK EXECUTION POLICY
   SKILL_NOT_LOADED
   ```
4. `devjunior-task.sh` exists/executable.
5. `ensure-devjunior-cron.sh` exists/executable.
6. `audit-devjunior-cron.sh` PASS.
7. Hermes skill list contains action-execution.
8. If Telegram configured:
   ```text
   ignore_root_dm=true
   devJunior Tasks topic exists
   topic.skill=action-execution
   ```
9. If Telegram not configured:
   ```text
   telegram=NOT_CONFIGURED
   ```
   not failure.

Success:

```text
DEVJUNIOR_RUNTIME_AUDIT=PASS
skill=action-execution
skill_version=0.5.1
cron=PASS
telegram=PASS|NOT_CONFIGURED
manual_entrypoint=PASS
```

No mutations.

### Verification

```bash
bash -n <PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
<PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
```

Exit 0.

### Commit

```text
feat(devjunior): add runtime task routing audit
```

---

# Task 7 — Pilot readiness runbook

## Goal

Зафиксировать exact deployment/pilot sequence. Production-ready запрещено объявлять только по repo tests.

## Action 7.1 — Pilot runbook

### Target file

```text
<PROFILE_ROOT>/docs/devjunior-task-routing-pilot.md
```

### Must contain

#### Before deployment

```bash
./scripts/audit-devjunior-runtime.sh
```

PASS.

#### Deploy

Использовать existing repository deployment mechanism. Не изобретать новый.

#### Runtime checks

```bash
hermes -p devjunior skills list
hermes -p devjunior cron status
```

#### Provision one product cron

Operator supplies exact:

```text
product-id
absolute product repo
provider
model
schedule
```

Then:

```bash
./scripts/ensure-devjunior-cron.sh \
  <product-id> \
  <absolute-product-repo> \
  <provider> \
  <model> \
  "every 5m"
```

#### Audit

```bash
./scripts/audit-devjunior-cron.sh
```

PASS.

#### CLI smoke

Only:

```bash
./scripts/devjunior-task.sh <pilot-task-id> <absolute-product-repo>
```

No bare Hermes Task call.

#### Telegram smoke, if configured

1. open `devJunior Tasks`;
2. start new/reset session;
3. send Task-related request;
4. confirm skill-bound session behavior/log evidence;
5. confirm root DM is not Task surface.

#### Cron pilot evidence

Collect:

```text
cron job id
cron execution id
product workdir
skill name
skill version
Task id
Action ids
Git branch
Action commit SHAs
Action Gate results
Task Gate result
PR URL
Kaneo status transitions
```

Pilot PASS only if:

```text
cron job.skills == ["action-execution"]
AND cron workdir == product repo
AND execution followed action-execution state machine
AND all Action evidence exists
AND Task reached In review through correct PR
```

If skill preload cannot be proven:

```text
pilot = FAIL
```

### Commit

```text
docs(devjunior): define task routing pilot
```

---

# Final verification

После merge всех Tasks в Outcome:

```bash
<PROFILE_ROOT>/scripts/verify-action-execution.sh
<PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
<PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
hermes -p devjunior skills list
hermes -p devjunior config show
hermes -p devjunior cron status
```

Все scripts exit 0, Hermes commands без config errors.

Разрешённые изменения Outcome vs base:

```text
<PROFILE_ROOT>/config.yaml
<PROFILE_ROOT>/SOUL.md
<PROFILE_ROOT>/skills.lock
<PROFILE_ROOT>/scripts/verify-action-execution.sh
<PROFILE_ROOT>/scripts/devjunior-task.sh
<PROFILE_ROOT>/scripts/ensure-devjunior-cron.sh
<PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
<PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
<PROFILE_ROOT>/docs/devjunior-task-routing-pilot.md
```

Если Telegram not configured, Task 4 = NOT_APPLICABLE и его commit отсутствует.

Запрещены изменения:

```text
action-execution package
.pipe
product repositories
Hermes source code
runtime jobs.json
.env
credentials
```

# Definition of Done

```text
canonical action-execution v0.5.1 pinned + hash-verified
AND project skill shadowing disabled
AND SOUL blocks bare Task execution
AND manual wrapper always preloads action-execution
AND Telegram Task topic auto-loads action-execution when Telegram exists
AND managed cron jobs always attach action-execution
AND managed cron jobs always have product workdir
AND cron model/provider are pinned
AND cron preflight + drift guard enabled
AND cron child scheduling disabled
AND unattended tool-loop hard-stop enabled
AND unified runtime audit passes
AND pilot runbook exists
```

Repo work завершён после этого. Production-ready — только после отдельного real pilot Task.
