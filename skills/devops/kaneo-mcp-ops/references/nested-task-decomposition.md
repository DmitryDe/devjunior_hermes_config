# Nested task decomposition in Kaneo

Use this when the user asks for a plan represented as a parent task with one or two nested levels.

## Core semantics

- `create_task` only creates a flat project task. A title such as `KDL-120.1` does **not** make it a child.
- Nesting is created separately with `create_task_relation`:
  - `relationType: "subtask"`
  - `sourceTaskId`: parent
  - `targetTaskId`: child
- `create_task` requires `projectId`, `title`, `description`, `priority`, and `status`.
- Use the project's real statuses. For work that is planned but explicitly not started, use `planned`.
- There is no `cancelled` status in the standard Kaneo project columns. Use `archived` when a task must be withdrawn.

## Planning-only workflow

1. **Confirm scope and project**
   - Fetch the existing parent if one was named.
   - Resolve its `projectId`; do not use a workspace ID as a project ID.
   - Inspect the repository read-only when concrete file-level decomposition was requested.

2. **Create the parent plan task**
   - Status: `planned`.
   - Description: objective, invariants, acceptance criteria, explicit scope boundary.
   - State clearly that code execution requires a later command when the user requested planning only.

3. **Create level 1 — logical workstreams**
   - One child per logical behavior/domain, not per worker persona.
   - Examples: shared traversal engine, cascade deletion, cascade archiving, status propagation, contracts/verification.
   - Create each as `planned`, then attach it immediately to the parent with a `subtask` relation.

4. **Create level 2 — atomic code changes**
   - Only when the user explicitly requests two levels.
   - Each item should name the exact file/module and one verifiable change.
   - Include atomic tests/migrations/contracts as separate children where they have independent gates.
   - Attach every atomic task to its level-1 parent; do not attach it directly to the root.

5. **Record dependencies and gates**
   - Add a parent comment describing implementation order, parallelizable branches, and quality gates.
   - Do not move any implementation task to `in-progress` during a planning-only request.

6. **Verify the hierarchy**
   - Call `get_task_relations` for the root and every level-1 task.
   - Verify expected counts, parent/child direction, `relationType=subtask`, and `planned` status.
   - Report actual task numbers and counts only after this read-back.

## Internal kanban behavior

During a planning-only request, the built-in kanban tracks the **planning operation** (inspect → create → relate → verify). It must not contain implementation cards marked `in_progress`. Future implementation phases remain represented in Kaneo as `planned` until the user explicitly starts execution.

## Pitfalls

- **Flat tasks presented as nested:** numbering and naming are cosmetic. Relations are mandatory.
- **Execution starts before plan approval:** creating the plan is the deliverable; stop after verification.
- **Optional unavailable tooling becomes a required gate:** verify availability before adding optional reviewers/bots to the plan. If unavailable, omit them or mark them explicitly optional rather than making completion depend on them.
- **Wrong relation direction:** parent is always `sourceTaskId`; child is `targetTaskId` for `subtask`.
- **Unverified bulk creation:** after multi-item creation, read back and count relations programmatically or via all parent relation lists.
