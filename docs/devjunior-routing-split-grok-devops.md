# devJunior mandatory routing — split by executor

Источник: `devjunior_mandatory_routing_30040c9c.plan.md`.

## Главный принцип

```text
Grok 4.6 / Cursor
→ только git repository конфигурации devJunior
→ файлы, commits, branches, PR

devOps
→ только host/runtime Hermes devJunior
→ deployment, profile state, cron state, Telegram runtime, runtime verification
```

Ни один исполнитель не выполняет работу другого.

---

# 1. Handoff model

```text
Grok Iteration A
→ repo foundation

devOps Checkpoint A
→ deploy foundation
→ снять реальные Hermes runtime contracts

Grok Iteration B
→ CLI + Telegram repo config

devOps Checkpoint B
→ deploy + smoke

Grok Iteration C
→ cron management scripts

devOps Checkpoint C
→ deploy + provision/audit cron

Grok Iteration D
→ unified audit + pilot runbook

devOps Final
→ deploy + real pilot
```

---

# TRACK A — GROK 4.6 / CURSOR

## G1 — Repo bootstrap

Inspection-only.

### G1.1
Определить `REPO_ROOT`:

```bash
git rev-parse --show-toplevel
```

### G1.2
Найти ровно один `PROFILE_ROOT` с `config.yaml` + `SOUL.md`.

0 или >1 → STOP.

### G1.3
Найти ровно один canonical package:

```yaml
name: action-execution
version: 0.5.1
```

с:

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

### G1.4
Проверить, что skill package уже tracked в base/HEAD.

Если untracked → STOP. Этот workstream skill не коммитит.

---

## G2 — Repo runtime policy foundation

Соответствует исходным Task 1 + Task 2.

### G2.1 — `config.yaml`

Target:

```text
<PROFILE_ROOT>/config.yaml
```

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

Сохранить unrelated config, existing legitimate `external_dirs`, `loop_caps`, model/provider и Telegram blocks.

Commit:

```text
config(devjunior): enforce task runtime policy
```

### G2.2 — `SOUL.md`

Target:

```text
<PROFILE_ROOT>/SOUL.md
```

Добавить `TASK EXECUTION POLICY` с `SKILL_NOT_LOADED`.

Не копировать workflow skill.

Commit:

```text
policy(devjunior): require action-execution for tasks
```

### G2.3 — `skills.lock`

Target:

```text
<PROFILE_ROOT>/skills.lock
```

Зафиксировать exact:

```text
ACTION_EXECUTION_NAME
ACTION_EXECUTION_VERSION=0.5.1
ACTION_EXECUTION_RELATIVE_DIR
ACTION_EXECUTION_PACKAGE_SHA256
```

Commit:

```text
chore(devjunior): pin action-execution package
```

### G2.4 — `verify-action-execution.sh`

Target:

```text
<PROFILE_ROOT>/scripts/verify-action-execution.sh
```

Проверять:

```text
skills.lock
skill files
name/version
hash
project_discovery=false
external_dirs contains canonical root
no higher-precedence duplicate
hermes -p devjunior skills list contains action-execution
```

Не менять runtime state.

Commit:

```text
feat(devjunior): verify action-execution integrity
```

### Grok checkpoint

Repo/static проверки и `bash -n`.

Полный runtime PASS `hermes -p devjunior ...` проверяет devOps после deploy.

---

## G3 — Mandatory CLI/manual entrypoint

Выполнять после devOps H1/H2, когда известен реальный Hermes CLI syntax.

### G3.1 — `devjunior-task.sh`

Target:

```text
<PROFILE_ROOT>/scripts/devjunior-task.sh
```

Wrapper:

```text
<task-id> <absolute-product-repo>
```

Обязательно:

```text
verify-action-execution.sh
safe task-id
absolute git workdir
.pipe/aidesklab-factory-gates exists
profile=devjunior
skill preload=-s action-execution
product workdir through confirmed Hermes CLI flag
```

Не угадывать syntax `--in`; использовать facts devOps.

No fallback without `-s`.

Commit:

```text
feat(devjunior): add mandatory task entrypoint
```

---

## G4 — Telegram repo config

Выполнять только после devOps передаст:

```text
TELEGRAM_CONFIGURED=yes|no
AUTHORIZED_CHAT_ID=<if yes>
CONFIRMED_TOPIC_SCHEMA
```

### If Telegram not configured

```text
G4 = NOT_APPLICABLE
```

No change / commit / PR.

### If configured — G4.1

Target:

```text
<PROFILE_ROOT>/config.yaml
```

Использовать только host facts devOps.

Обеспечить:

```text
ignore_root_dm=true
topic name=devJunior Tasks
topic.skill=action-execution
```

Не придумывать `thread_id`, token, chat_id.

Commit:

```text
config(devjunior): bind task topic to action-execution
```

---

## G5 — Cron management code

Выполнять только после devOps H1/H2 передаст:

```text
HERMES_VERSION
CRON_CREATE_FLAGS
CRON_EDIT_FLAGS
CRON_LIST_FORMAT
WORKDIR_FLAG
SKILL_FLAG
MODEL_FLAG
PROVIDER_FLAG
```

### G5.1 — `ensure-devjunior-cron.sh`

Target:

```text
<PROFILE_ROOT>/scripts/ensure-devjunior-cron.sh
```

Реализовать:

```text
skill preflight
product-id validation
absolute product repo
.pipe exists
explicit provider/model
job name devjunior:<product-id>
0-or-1 existing managed job
create/edit only via Hermes CLI
skill exactly action-execution
explicit workdir
exact managed prompt
mandatory read-back
never write jobs.json
```

Commit:

```text
feat(devjunior): enforce skill-backed task cron
```

### G5.2 — `audit-devjunior-cron.sh`

Target:

```text
<PROFILE_ROOT>/scripts/audit-devjunior-cron.sh
```

Read-only audit:

```text
managed skill exactly action-execution
absolute workdir
provider pinned
model pinned
cron.preflight=true
cron.model_drift_guard=true
cron.allow_agent_scheduling=false
```

No jobs → PASS jobs=0.

Commit:

```text
feat(devjunior): audit task cron routing
```

---

## G6 — Unified runtime audit

### G6.1 — `audit-devjunior-runtime.sh`

Target:

```text
<PROFILE_ROOT>/scripts/audit-devjunior-runtime.sh
```

Aggregate checks:

```text
skill preflight
config invariants
SOUL markers
CLI wrapper
cron ensure/audit
Hermes skill visibility
Telegram binding or NOT_CONFIGURED
```

Script read-only.

Commit:

```text
feat(devjunior): add runtime task routing audit
```

---

## G7 — Pilot runbook

### G7.1 — `docs/devjunior-task-routing-pilot.md`

Target:

```text
<PROFILE_ROOT>/docs/devjunior-task-routing-pilot.md
```

Документировать:

```text
pre-deploy audit
existing deployment mechanism
runtime checks
cron provisioning
cron audit
CLI smoke
Telegram smoke
real cron pilot
evidence checklist
PASS/FAIL criteria
```

Сам pilot Grok не выполняет.

Commit:

```text
docs(devjunior): define task routing pilot
```

---

# TRACK B — devOps / HOST

## H1 — Runtime discovery

Выполнить до G3/G4/G5.

### H1.1 — Hermes identity

```bash
hermes --version
hermes profile show devjunior
hermes -p devjunior config show
hermes -p devjunior skills list
hermes -p devjunior cron status
```

Зафиксировать:

```text
HERMES_VERSION
PROFILE_RUNTIME_PATH
CURRENT_MODEL
CURRENT_PROVIDER
```

### H1.2 — CLI contracts

```bash
hermes --help
hermes chat --help
hermes cron --help
hermes cron create --help
hermes cron edit --help
hermes cron list --help
```

Передать Grok exact supported flags.

### H1.3 — Telegram runtime facts

Определить:

```text
TELEGRAM_CONFIGURED
AUTHORIZED_CHAT_ID
actual dm_topics schema
ignore_root_dm support
skill binding support
```

Ничего не менять.

### H1.4 — Deployment mechanism

Определить existing:

```text
config repo → deployed devjunior profile
```

Зафиксировать exact deployment command/service.

### H1.5 — Existing cron inventory

Read-only:

```bash
hermes -p devjunior cron list
```

Зафиксировать `devjunior:*` jobs, schedules, workdirs, model/provider, skills.

---

## H2 — Deploy foundation

После G2 merge.

### H2.1
Deploy exact merged repo revision штатным mechanism.

### H2.2

```bash
<deployed-profile>/scripts/verify-action-execution.sh
```

Must PASS.

### H2.3

```bash
hermes -p devjunior config show
hermes -p devjunior skills list
```

Доказать:

```text
action-execution visible
version/hash match
project_discovery=false
tool_use_enforcement=true
execution_guidance=true
cron guards configured
```

### H2.4 — Handoff to Grok

Передать:

```text
Hermes version
confirmed chat invocation syntax
confirmed workdir syntax
Telegram facts
cron create/edit/list flags
deployment mechanism
```

---

## H3 — Deploy CLI/Telegram changes

После G3/G4 merge.

### H3.1
Deploy merged SHA.

### H3.2 — CLI wrapper smoke

Negative paths:

```text
bad task-id
relative repo
non-git repo
repo without .pipe
```

Без реального production Task.

### H3.3 — Telegram runtime verification

If configured:

```text
restart gateway/profile if required
topic devJunior Tasks exists
topic bound action-execution
root DM not Task surface
```

Если runtime создаёт `thread_id`, проверить штатное появление.

---

## H4 — Deploy/provision cron

После G5 merge.

### H4.1
Deploy merged SHA.

### H4.2

```bash
audit-devjunior-cron.sh
```

Existing violation → STOP.

### H4.3 — Provision one controlled job

С operator-supplied:

```text
product-id
absolute product repo
provider
model
schedule
```

Выполнить:

```bash
ensure-devjunior-cron.sh ...
```

### H4.4 — Read-back

Доказать:

```text
name exact
skills exactly ["action-execution"]
workdir exact
provider/model exact
prompt exact
schedule expected
```

### H4.5

```bash
audit-devjunior-cron.sh
```

PASS.

---

## H5 — Final runtime audit

После G6/G7 merge + deploy.

### H5.1
Deploy final merged SHA.

### H5.2

```bash
verify-action-execution.sh
audit-devjunior-cron.sh
audit-devjunior-runtime.sh
```

Все PASS.

### H5.3

```bash
hermes -p devjunior skills list
hermes -p devjunior config show
hermes -p devjunior cron status
```

No errors.

---

## H6 — Real pilot

Только devOps.

### Preconditions

```text
H5 PASS
production .pipe gates ready
pilot product repo selected
pilot Kaneo Task selected
managed cron job exists
```

### H6.1 — Optional manual smoke

Только wrapper:

```bash
devjunior-task.sh <pilot-task-id> <product-repo>
```

### H6.2 — Telegram smoke if configured

Task request только в:

```text
devJunior Tasks
```

Проверить preload evidence.

### H6.3 — Cron pilot

Разрешить controlled execution и собрать:

```text
cron job id
execution id
profile
skill name
skill version/hash
workdir
Task id
Action ids
branch
commits
Action Gate results
Task Gate result
PR URL
Kaneo transitions
```

### H6.4 — Verdict

PASS только если:

```text
session started with action-execution preloaded
AND exact product workdir
AND execution followed skill workflow
AND evidence complete
AND Task reached In review through correct PR
```

Нет доказательства preload → `PILOT=FAIL`.

---

# Рекомендуемые итерации

## Grok / Cursor

```text
Run 1: G1 + G2
Run 2: G3 + G4        после H1/H2 facts
Run 3: G5             после exact cron CLI facts
Run 4: G6 + G7
```

## devOps / host

```text
Run 1: H1 + H2
Run 2: H3
Run 3: H4
Run 4: H5 + H6
```

---

# Handoff chain

```text
G2 → H2
foundation repo → deployed runtime validation

H2 → G3/G4/G5
real Hermes/Telegram/cron facts → implementation

G3/G4 → H3
manual + Telegram repo changes → runtime smoke

G5 → H4
cron code → real cron provision/audit

G6/G7 → H5/H6
audit/runbook → final deploy + pilot
```

---

# Ownership matrix

| Work | Grok/Cursor | devOps |
|---|---:|---:|
| repo `config.yaml` | YES | NO |
| repo `SOUL.md` | YES | NO |
| `skills.lock` | YES | NO |
| scripts in repo | YES | NO |
| pilot runbook | YES | NO |
| git branch/commit/PR | YES | NO |
| live Hermes CLI discovery | NO | YES |
| live model/provider | NO | YES |
| Telegram runtime facts | NO | YES |
| deploy profile | NO | YES |
| restart gateway/service | NO | YES |
| create/edit real cron | NO | YES |
| runtime jobs inspection | NO | YES |
| real product path validation | NO | YES |
| real Task execution | NO | YES |
| runtime trace collection | NO | YES |
| pilot verdict | NO | YES |

---

# Final states

```text
Grok track complete
→ READY_FOR_DEPLOYMENT

devOps H5 complete
→ READY_FOR_PILOT

devOps H6 PASS
→ DEVJUNIOR_TASK_ROUTING_PRODUCTION_READY
```
