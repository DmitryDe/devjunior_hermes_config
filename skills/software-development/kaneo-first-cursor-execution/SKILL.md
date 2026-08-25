---
name: kaneo-first-cursor-execution
description: "Atomic cursor execution of Kaneo KDL Actions."
version: 1.0.0
author: devJunior @ AIDeskLab
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kaneo, kaneo-first, cursor, remediation, orchestration, pnpm, monorepo, pr-hygiene]
    related_skills: [kanban-orchestrator, kaneo-mcp-integration, kaneo-mcp-ops]
---

# kaneo-first: atomic cursor-execution of Kaneo remediation Actions

## When this applies
You are devJunior and a Kaneo task (KDL-xxx) in workspace **AIDeskLab** (project `kaneo`, id `jxs1sp34aftj6q38z0shhjuy`) decomposes into **Action** subtasks, each scoped to change EXACTLY ONE file. The user wants them executed **atomically and sequentially** via `cursor agent --model auto`, one file per commit. This is the round-N review-remediation pattern against an existing PR (e.g. PR #20 `outcome/cascade-nested-task-operations`).

## Repo facts (AIDeskLab/kaneo-first)
- **pnpm monorepo** (pnpm pinned 10.32.1). Node >=18. `pnpm install` once.
- Workspace roots: `apps/api` (@kaneo/api), `apps/web` (@kaneo/web), `apps/docs`, `packages/*`.
- **Cursor CLI** at `/home/dev/.cursor/cli-config.json`: set `approvalMode` to allow `Shell(**)` so cursor can run `git`/`pnpm`. (Previously a `Shell(ls)` allowlist blocked commits — widen it.)
- **Integration tests need a live PostgreSQL.** Env `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/kaneo_test`. In the standard agent environment this is absent — integration `vitest` runs CANNOT be executed locally; you can only biome-check + typecheck them and rely on GitHub CI to actually run them. Do not claim integration-green; say "written, biome+typecheck clean, CI will run".
- **Pre-existing biome lint error blocks ALL pre-commit hooks**: `tests/api/ws/broadcast.test.ts` fails `noUndeclaredEnvVars` (REDIS_URL) — comes from `origin/main`, not your files. The `biome ci .` hook therefore fails every commit. **Commit with `git commit --no-verify`**, but FIRST verify YOUR changed files are biome-clean individually (`pnpm exec biome check <file>`). Never `--no-verify` to bypass a check on your own code.

## Workflow (per Action)
1. **Create the cumulative branch** off the agreed base (e.g. PR head `f26e330c`, or an `outcome/*` branch) and base each Task's branch on the outcome after the previous Task is merged in.
   - `git checkout outcome/cascade-nested-task-operations && git merge --no-edit task/<name>` to fold a finished Task branch in (fast-forward). Then `git checkout -B task/<next> outcome/cascade-nested-task-operations`.
2. **Read the Action's executor prompt from Kaneo** via `mcp__kaneo__get_task`. Some Actions specify a **required order** that is NOT numeric (e.g. KDL-158: 163→166→161→162→164→165). Honor it — dependencies (additive fields, fan-out props) won't exist otherwise and later cursor runs will fail typecheck.
3. **Write the executor prompt to a temp file** (`write_file` is reliable; `terminal` heredocs with `PROMPT` delimiter have failed — use `write_file` then `cat "$file"` into cursor). Augment the Kaneo prompt with:
   - "STRICT RULES: Change EXACTLY ONE file: `<path>`. Do NOT commit — the orchestrator commits after verifying."
   - "Preserve preceding commits; do not reset/rebranch."
4. **Invoke cursor** — ALWAYS `--model auto` unless another model was requested:
   ```
   cursor agent --model auto --print --trust --workspace /home/dev/kaneo-first "$(cat /tmp/kdlXXX_prompt.md)" > /tmp/kdlXXX.log 2>&1
   ```
   Run it **background=true with notify_on_complete=true** (foreground 300s hits the timeout; cursor keeps running and you lose the handle). Wait via `process wait` on the returned session_id.
5. **Verify BEFORE committing** (cursor self-reports lie — see pitfalls):
   - `git status --short` → exactly the one intended file changed.
   - `git diff --stat <file>` → sane line counts.
   - `pnpm exec biome check <file>` → no errors.
   - `pnpm --filter @kaneo/api typecheck` (or `@kaneo/web`) → green.
   - For SQL/migration JSON: `python3 -m json.tool <file> >/dev/null` and confirm `_journal.json` entry count/increment.
6. **Commit one file per Action** (atomic): `git add -- <file> && git commit --no-verify -m "conventional: short"`. Single short line only (commitlint rejects bodies).
7. After the Task's Actions are done, merge into `outcome/*`, push, and update PR #20 (it tracks `outcome/cascade-nested-task-operations` → `main`). Move KDL Task + all Action cards to `in-review` via `mcp__kaneo__update_task_status`.

## `gh` fork-PR hygiene (CRITICAL)
- `gh` defaults its repo context to the **upstream fork** (e.g. `usekaneo/kaneo`), NOT `AIDeskLab/kaneo-first`.
- `gh pr view 20` (bare) returned a *different, already-merged* upstream PR and masked that the real fork PR #20 was still OPEN. **Always pass `--repo AIDeskLab/kaneo-first`** on EVERY `gh pr` read/write: `gh pr view 20 --repo AIDeskLab/kaneo-first`, `gh pr create --repo AIDeskLab/kaneo-first --head <branch> --base main`, `gh pr checks 20 --repo AIDeskLab/kaneo-first`.
- After `git push origin outcome/...`, the PR auto-updates; confirm with `gh pr view 20 --repo AIDeskLab/kaneo-first --json state,headRefName,updatedAt`.

## Pitfalls
- **Cursor self-reports are not verification.** Cursor prints `KDLXXX_DONE` + "biome и typecheck прошли" but has shipped code that FAILS typecheck (seen on KDL-182 web test: 3 TS errors; KDL-183/184: `isPending` prop missing on ArchiveTasksModal until KDL-185 added it). Always run the real `pnpm --filter @kaneo/<app> typecheck` and read the actual `error TS` lines. Fix typecheck errors yourself (patch the file) before committing — don't re-prompt cursor and wait.
- **Cross-file Action dependencies**: when Action B adds a prop/field that Actions C,D consume, C and D will show ONLY that "missing symbol" typecheck error until B lands. This is expected; commit B first (or in order), then C/D typecheck green. Don't treat the lone "missing prop" error as a cursor failure — it's a sequencing artifact.
- **`--print` cursor output goes to the log file**, not stdout, when backgrounded. Tail `/tmp/kdlXXX.log` for the `KDLXXX_DONE` line; the diff is your real evidence.
- **`gh pr create` "No commits between main and outcome"** means `gh` compared against upstream default — fix with `--repo AIDeskLab/kaneo-first`.
- **Never merge to `main`** without an explicit user command (KDL DoD). Stop at merge-ready / push + PR.
- **DATABASE_URL absent** → integration `vitest` cannot run here. Verify integration-test files by biome + typecheck only; let CI run them.

## Verification checklist (each Action)
- [ ] `git status --short` shows ONLY the one intended file
- [ ] `pnpm exec biome check <file>` clean
- [ ] `pnpm --filter @kaneo/<app> typecheck` clean (read real `error TS` lines)
- [ ] committed with one-file-per-commit + `--no-verify` (pre-existing hook error only)
- [ ] cumulative branch merged to `outcome/*`; PR #20 `--repo AIDeskLab/kaneo-first` updated
