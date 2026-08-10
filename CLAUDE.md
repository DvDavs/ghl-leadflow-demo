# Agent protocol for this repository

Compact. Read this fully; do not skip to the task.

## Start here, every session

Read in this order, and stop as soon as you have what the task needs:

1. [`PROJECT_STATE.md`](PROJECT_STATE.md) — the current-state snapshot. Do not
   reconstruct project history from commits or docs.
2. [`TEST_CASES.md`](TEST_CASES.md) — the status matrix: per scenario, its
   status, the artifact version the pass covers, and a link to its evidence.
3. [`docs/INDEX.md`](docs/INDEX.md) — the reading route to everything else.
4. **Open evidence (`docs/evidence/`) or history (`docs/history/`) only when
   the task actually needs them.** They are deliberately kept out of the
   default reading path so a session does not load them by reflex.

The GitHub Project board is the source of truth for sprint status
(Backlog/Ready/In Progress/Testing/Done/Blocked). `PROJECT_STATE.md` is its
public mirror, not a replacement.

Read only the specific issue and docs relevant to your task. Do not
re-summarize the whole repository in your output — the reader already has
this file and `PROJECT_STATE.md`.

## Naming

- Prompts: `PXX_SHORT_NAME` (e.g. `P04_GHL_OAUTH_AND_CAPABILITY_PROBES`).
- Main agent per prompt: `PXX-A00_ROLE_NAME`.
- Subagents: `PXX-SXX_ROLE_NAME`, numbered per prompt.

## Delegation

- Subagents receive only the context their specific task needs — not the full
  brief.
- The main agent consolidates subagent results into facts/evidence/risk/
  recommendation. Never paste subagent transcripts into a user-facing report.

## Human interaction

- Human action requests go at the **start** of a message, clearly marked,
  with a maximum of two actions per prompt.
- Never ask a human to paste secrets, tokens, private URLs, IDs, or
  screenshots into chat, a commit, an Issue, or the Project board.

## Evidence discipline

- Never mark a capability or test `PASS` without observed evidence attached.
- Never present a schema-level inference ("the operation exists") as a
  verified capability ("the operation works"). Distinguish discovered vs.
  executed vs. absent vs. unknown.
- A sequential test proves sequential behavior only. Never generalize it to a
  claim about concurrency.

## Secrets and data

- Never commit tokens, location/account IDs, or real customer data. This repo
  is public.
- Test fixtures are fictional only — check `git diff --check` and scan staged
  files for secret-shaped strings before every commit.
- `docs/environment.local.md` is intentionally gitignored — keep it that way.

## State hygiene

- Update `PROJECT_STATE.md` after any change significant enough to affect
  what the next session needs to know.
- **Keep `PROJECT_STATE.md` a snapshot, not a log.** Milestone narrative goes
  to `docs/history/`, observed test output to `docs/evidence/`, and the status
  matrix stays a matrix. If a section starts growing a story, move the story.
- Keep this file short. Architecture, decisions, and setup detail live in
  `docs/` — do not duplicate them here.
