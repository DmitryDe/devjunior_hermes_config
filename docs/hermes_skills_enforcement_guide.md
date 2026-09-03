# Hermes Agent: обязательное использование Skills

## Цель

Сделать так, чтобы Hermes Agent:

1. всегда проверял наличие подходящего skill перед выполнением задачи;
2. не полагался на память о содержимом skill;
3. для критичных сценариев получал skill в контекст автоматически через preload;
4. одинаково предсказуемо работал из CLI и через Telegram gateway.

Рекомендуемая схема:

```text
SOUL.md
  └─ обязательная Skill Policy для всех задач

        +

Telegram topic / CLI -s
  └─ preload критичного skill до первого шага агента
```

`SOUL.md` задаёт постоянное правило поведения.  
Preload устраняет саму необходимость надеяться, что модель решит открыть конкретный skill.

---

# 1. Где находятся файлы профиля

Для default-профиля Hermes использует:

```text
~/.hermes/
├── config.yaml
├── SOUL.md
├── skills/
├── memories/
└── ...
```

Для именованных profiles:

```text
~/.hermes/profiles/<profile>/
├── config.yaml
├── .env
├── SOUL.md
├── skills/
├── memories/
└── ...
```

Например для `devjunior`:

```text
~/.hermes/profiles/devjunior/
├── config.yaml
├── .env
├── SOUL.md
└── skills/
```

Проверить путь активного профиля:

```bash
hermes profile
```

или список:

```bash
hermes profile list
```

Для профиля `devjunior` все дальнейшие изменения нужно делать именно в его `HERMES_HOME`, а не в `~/.hermes/` default-профиля.

---

# 2. Обязательная Skill Policy через SOUL.md

`SOUL.md` — primary identity Hermes и занимает первый слот system prompt.

Для профиля `devjunior`:

```bash
nano ~/.hermes/profiles/devjunior/SOUL.md
```

Не удаляйте существующее описание роли агента. Добавьте в него отдельный раздел:

```md
## Skill Policy

Before planning or executing any task:

1. Check the available skills for instructions relevant to the task.
2. If a relevant skill exists, you MUST load and read it before planning or execution.
3. Follow the loaded skill as authoritative task instructions.
4. Never rely on memory or assumptions about a skill's contents.
5. If multiple skills apply, load all relevant skills before execution.

Required execution order:

task → discover relevant skills → load skills → plan → execute

Skipping an applicable skill is incorrect task execution.
```

Для экономии токенов можно использовать более короткий вариант:

```md
## Skill Policy

For every task:

task → find relevant skills → read them → plan → execute

A relevant skill MUST be read before planning or execution.
Never rely on memory of a skill.
Skipping an applicable skill is incorrect execution.
```

Для AIDeskLab я рекомендую короткий вариант: он достаточно жёсткий и не раздувает system prompt.

---

# 3. Применение изменений SOUL.md

Изменения `SOUL.md` гарантированно применяются к новой сессии.

После редактирования рекомендуется:

```bash
devjunior gateway restart
```

Если alias профиля не создан:

```bash
hermes -p devjunior gateway restart
```

Затем в Telegram начать новую сессию:

```text
/reset
```

Это важно: уже существующая сессия могла быть создана со старым system prompt.

---

# 4. Проверка SOUL.md

Для быстрой проверки через CLI:

```bash
hermes -p devjunior chat -q "What is your required execution order when a relevant skill exists?"
```

Ожидаемая логика ответа:

```text
discover/read skill → plan → execute
```

Проверка должна выполняться в новой сессии.

---

# 5. Preload skill через CLI

Если конкретный skill должен быть загружен гарантированно, Hermes поддерживает:

```bash
-s
```

или:

```bash
--skills
```

Пример:

```bash
hermes -p devjunior -s decomposition
```

или:

```bash
hermes -p devjunior chat -s decomposition
```

Несколько skills:

```bash
hermes -p devjunior -s decomposition,kaneo
```

или:

```bash
hermes -p devjunior chat \
  -s decomposition \
  -s kaneo
```

При таком запуске Hermes загружает указанные skills в session prompt до первого сообщения модели.

Это сильнее, чем обычная Skill Policy:

```text
SOUL only
task
  ↓
agent видит список skills
  ↓
agent должен решить прочитать skill
  ↓
skill загружается

preload
task
  ↓
skill уже находится в контексте
  ↓
agent выполняет задачу
```

---

# 6. Preload через Telegram Gateway

Для Telegram не нужно модифицировать Python-код gateway.

Текущий Hermes поддерживает привязку skill к Telegram Topic.

При создании новой сессии topic указанный skill загружается автоматически.

Есть два варианта:

1. Private Chat Topics — topic внутри личного диалога с ботом.
2. Group Forum Topics — topic внутри Telegram supergroup.

Для схемы с отдельными сотрудниками удобнее Private Chat Topics либо отдельные Telegram-боты/profile.

---

# 7. Private Chat Topics

Telegram поддерживает Topics в личном чате с ботом.

Сначала включите Topics для диалога с Hermes bot в Telegram.

Затем откройте:

```bash
nano ~/.hermes/profiles/devjunior/config.yaml
```

Добавьте:

```yaml
platforms:
  telegram:
    extra:
      dm_topics:
        - chat_id: 123456789
          topics:
            - name: Development
              skill: software-development
```

Где:

```text
123456789
```

— ваш Telegram user ID.

А:

```text
software-development
```

— имя установленного Hermes skill.

После запуска gateway Hermes создаст topic и автоматически запишет его `thread_id` обратно в `config.yaml`.

В результате конфигурация может выглядеть примерно так:

```yaml
platforms:
  telegram:
    extra:
      dm_topics:
        - chat_id: 123456789
          topics:
            - name: Development
              thread_id: 42
              skill: software-development
```

`thread_id` вручную задавать при первоначальном создании topic не требуется.

---

# 8. Несколько Telegram Topics для разных типов работы

Например:

```yaml
platforms:
  telegram:
    extra:
      dm_topics:
        - chat_id: 123456789
          topics:

            - name: Development
              skill: software-development

            - name: Decomposition
              skill: decomposition

            - name: Kaneo
              skill: kaneo
```

Получается:

```text
Telegram
├── Development
│   └── preload software-development
│
├── Decomposition
│   └── preload decomposition
│
└── Kaneo
    └── preload kaneo
```

Каждый topic имеет отдельную Hermes session и отдельную историю.

---

# 9. Не использовать root DM

Чтобы пользователь случайно не писал агенту вне topic без preload, можно включить:

```yaml
platforms:
  telegram:
    extra:
      ignore_root_dm: true

      dm_topics:
        - chat_id: 123456789
          topics:
            - name: Development
              skill: software-development
```

Тогда обычные сообщения в корневой DM будут игнорироваться, а работа будет происходить через topics.

Для строгого production-поведения это полезно.

---

# 10. Group Forum Topics

Если Hermes работает в Telegram supergroup:

```yaml
platforms:
  telegram:
    extra:
      group_topics:
        - chat_id: -1001234567890
          topics:

            - name: Development
              thread_id: 5
              skill: software-development

            - name: Decomposition
              thread_id: 12
              skill: decomposition
```

Здесь:

```yaml
chat_id: -1001234567890
```

— ID Telegram supergroup.

А:

```yaml
thread_id: 5
```

— ID конкретного forum topic.

При сообщении в соответствующий topic Hermes автоматически preload'ит связанный skill для новой session.

---

# 11. Важное ограничение Telegram preload

В topic binding используется:

```yaml
skill: <skill-name>
```

То есть один topic напрямую привязывается к одному skill.

Если задача требует нескольких обязательных skills, есть три подхода.

## Вариант A — один orchestration skill

Создать, например:

```text
devjunior/
```

который сам определяет обязательный workflow и при необходимости использует остальные skills.

Telegram:

```yaml
skill: devjunior
```

Это наиболее чистый вариант для роли постоянного сотрудника.

---

## Вариант B — один основной preload + Skill Policy

Например:

```yaml
skill: software-development
```

А в `SOUL.md`:

```text
task → find additional relevant skills → read → plan → execute
```

Тогда основной skill гарантированно присутствует, а остальные агент обязан подобрать.

---

## Вариант C — разные topics

```text
Development  → software-development
Kaneo        → kaneo
Decomposition → decomposition
```

Подходит, если тип задачи выбирает пользователь.

---

# 12. Рекомендуемая схема для devJunior

Для `devjunior` я рекомендую:

```text
SOUL.md
  └── глобальная Skill Policy

devjunior skill
  └── постоянный workflow роли

Telegram topic
  └── preload devjunior
```

Структура:

```text
~/.hermes/profiles/devjunior/
├── config.yaml
├── SOUL.md
└── skills/
    ├── devjunior/
    │   └── SKILL.md
    │
    ├── decomposition/
    │   └── SKILL.md
    │
    ├── kaneo/
    │   └── SKILL.md
    │
    └── ...
```

Telegram:

```yaml
platforms:
  telegram:
    extra:
      ignore_root_dm: true

      dm_topics:
        - chat_id: 123456789
          topics:
            - name: devJunior
              skill: devjunior
```

---

# 13. Почему использовать одновременно SOUL и preload

Эти механизмы решают разные задачи.

## SOUL.md

Задаёт инвариант поведения:

```text
если skill релевантен → прочитать его обязательно
```

Работает независимо от источника задания:

```text
CLI
Telegram
Discord
Gateway
one-shot command
```

## Preload

Гарантирует наличие конкретного критического skill:

```text
этот skill уже загружен
```

Поэтому рекомендуемая комбинация:

```text
SOUL = policy
Skill = procedure
Preload = enforcement
```

---

# 14. Итоговый SOUL.md для devJunior

Минимальный рекомендуемый вариант:

```md
# devJunior

You are devJunior.

Execute tasks precisely and concisely.
Do not expand the requested scope without necessity.

## Skill Policy

For every task:

task → find relevant skills → read them → plan → execute

A relevant skill MUST be read before planning or execution.
Never rely on memory of a skill.
Skipping an applicable skill is incorrect execution.
```

Если в текущем `SOUL.md` уже описана личность/роль `devJunior`, добавьте только `## Skill Policy`, не заменяя остальное содержимое.

---

# 15. Итоговый Telegram config

Пример:

```yaml
platforms:
  telegram:
    extra:
      ignore_root_dm: true

      dm_topics:
        - chat_id: 123456789
          topics:
            - name: devJunior
              skill: devjunior
```

Перезапуск:

```bash
hermes -p devjunior gateway restart
```

или, если profile alias исправно создан:

```bash
devjunior gateway restart
```

После этого открыть topic `devJunior` и выполнить:

```text
/reset
```

Затем отправить тестовую задачу.

---

# 16. Проверка preload

Простой функциональный тест лучше делать не вопросом:

```text
Did you load the skill?
```

Модель может ответить на него недостоверно.

Лучше создать в `devjunior/SKILL.md` характерное, безопасное правило, например:

```md
For implementation tasks, always begin the execution summary with:
WORKFLOW: DEVJUNIOR
```

После `/reset` дать обычную implementation-задачу.

Если preload работает, агент должен выполнить правило без просьбы открыть skill.

После проверки тестовый маркер можно удалить.

---

# 17. Проверка через CLI тем же skill

Перед отладкой Telegram можно проверить сам skill:

```bash
hermes -p devjunior chat -s devjunior -q "Summarize the workflow you must follow for implementation tasks."
```

Если CLI preload работает, а Telegram нет, проблема находится в Telegram topic binding/configuration, а не в самом skill.

---

# 18. Диагностический порядок

Если агент снова игнорирует skill:

```text
1. Проверить profile
2. Проверить HERMES_HOME
3. Проверить SOUL.md именно этого profile
4. Начать новую session
5. Проверить наличие skill в skills/
6. Проверить точное имя skill
7. Проверить Telegram topic binding
8. Перезапустить gateway
9. Выполнить /reset
10. Проверить behaviour marker
```

Команды:

```bash
hermes profile list
```

```bash
ls -la ~/.hermes/profiles/devjunior/
```

```bash
ls -la ~/.hermes/profiles/devjunior/skills/
```

```bash
cat ~/.hermes/profiles/devjunior/SOUL.md
```

```bash
cat ~/.hermes/profiles/devjunior/config.yaml
```

```bash
hermes -p devjunior gateway restart
```

---

# 19. Рекомендуемый production-вариант AIDeskLab

```text
                         ┌──────────────────────┐
                         │     Telegram task    │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ devJunior DM Topic   │
                         │ skill: devjunior     │
                         └──────────┬───────────┘
                                    │
                             automatic preload
                                    │
                                    ▼
┌───────────────────┐    ┌──────────────────────┐
│ SOUL.md           │───▶│ Hermes session       │
│ Skill Policy      │    │                      │
└───────────────────┘    └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ devjunior/SKILL.md   │
                         │ role workflow        │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         relevant additional
                              skills loaded
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │      execution       │
                         └──────────────────────┘
```

Главный принцип:

```text
SOUL.md заставляет искать skills.
Preload гарантирует основной skill.
Основной skill задаёт workflow роли.
Специализированные skills задают конкретные процедуры.
```

Так пользователь отправляет в Telegram только саму задачу и больше не повторяет инструкции вида:

```text
сначала прочитай skills
```

---

# Источники

Актуальная документация Hermes Agent:

- Profiles: https://hermes-agent.nousresearch.com/docs/user-guide/profiles
- Personality & SOUL.md: https://hermes-agent.nousresearch.com/docs/user-guide/features/personality
- Prompt Assembly: https://hermes-agent.nousresearch.com/docs/developer-guide/prompt-assembly
- CLI Commands: https://hermes-agent.nousresearch.com/docs/reference/cli-commands
- Telegram Messaging: документация Hermes Agent, `website/docs/user-guide/messaging/telegram.md`

Проверено по актуальной документации Hermes Agent на 21 августа 2026 года.
