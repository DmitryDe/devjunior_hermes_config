---
name: kaneo-mcp-ops
description: "Kaneo labels 1:1 with tasks. Attach moves, not copies."
version: 1.0.0
author: Hermes Agent (curator)
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kaneo, mcp, gotchas, devops]
    related_skills: [kaneo-mcp-integration]
    companion_to: kaneo-mcp-integration
---

# Kaneo MCP — Operational Gotchas

Companion to the read-only `kaneo-mcp-integration` skill. Covers patterns, pitfalls, and
workarounds discovered in real sessions that aren't in the external skill.

## When to Use

Load this skill when:
- Calling `attach_label_to_task` or `create_label` on multiple tasks
- Debugging "Workspace ID could not be determined" from `attach_label_to_task`
- Working with label IDs from prior sessions or task descriptions
- Any multi-task label operation in Kaneo

## Labels are 1:1 with tasks

`attach_label_to_task` **MOVES** the label from its current task to the target — it does NOT
copy or share. Attaching label X to task B silently removes it from task A.

### Example (2026-08-11, AIDeskLab workspace)

- SPLIT label on KDL-85 (`jm2tg9...`), id `lgvaka2...`
- `attach_label_to_task(labelId=lgvaka2..., taskId=cugsag8...)` → KDL-87 got SPLIT, KDL-85 lost it
- `list_workspace_labels` confirmed the original record gone; only the new one remained

### Correct pattern: same-name label on multiple tasks

Use `create_label` with `taskId` — creates a separate label instance per task:

```
create_label(name="SPLIT", color="#8B5CF6", workspaceId="<WS>", taskId="<TASK>")
```

After creation, `list_workspace_labels` shows multiple "SPLIT" entries, each with a different
`taskId` and `id`.

## `attach_label_to_task` → "Workspace ID could not be determined"

Some tasks trigger this error consistently even when:
- The label exists and is valid
- The task exists and belongs to the correct project/workspace
- Other sibling tasks in the same project work fine

**Workaround:** use `create_label` with explicit `workspaceId` and `taskId`:

```
create_label(name="SPLIT", color="#8B5CF6", workspaceId="uYQac3vbNBvYestN8V8CacytYyZ9sVAV", taskId="<TASK>")
```

This bypasses the workspace-resolution bug in the attach endpoint.

## Label IDs are not stable across sessions

Kaneo creates a new label record on every `create_label`. `attach_label_to_task` can produce
new IDs. **Never trust a label ID from a prior session, task description, or cross-session
context without re-verifying.**

Always run `list_workspace_labels(workspaceId="<WS>")` to get current label IDs before using
`attach_label_to_task`.
