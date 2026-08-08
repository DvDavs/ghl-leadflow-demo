# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 2 — Architecture and repository baseline.**

Design-first: the architecture, lifecycle model, idempotency strategy, and test
matrix are written before any GHL, n8n, or Google resource is created, so the
implementation is measured against a contract rather than the contract being
back-fitted to the implementation.

# Completed

- **Milestone 1 — Environment inventory.** Toolchain, GitHub access, service
  availability, and MCP registry audited read-only. Published in sanitized form
  as [`docs/environment.md`](docs/environment.md).
- **Repository hardening.** `.gitignore` written before the first `git add`,
  covering secrets, credential-shaped files, local n8n state, and cloud-sync
  conflict artifacts — without blanket-ignoring `*.json`, since workflow
  exports and payload fixtures will be versioned JSON.
- **Inventory sanitization.** The full inventory is retained locally and
  untracked; the published version keeps capabilities, versions, and
  classification, and drops local security detail.
- **Architecture baseline.** [`docs/architecture.md`](docs/architecture.md) plus
  three Mermaid diagrams under [`docs/diagrams/`](docs/diagrams/).
- **Decision records.** Integration hierarchy, idempotency strategy, and AI
  boundaries recorded under [`docs/decisions/`](docs/decisions/).
- **Test matrix.** [`TEST_CASES.md`](TEST_CASES.md) — 19 scenarios, all
  `BLOCKED`, none passing.
- **Integration research.**
  [`docs/integration-options.md`](docs/integration-options.md), sourced from
  official documentation only.

- **Adversarial review.** Ran before publication. Three blockers found and
  fixed, the most serious being that the idempotency claim was wrong as drawn —
  see the correction commit and `architecture.md` §6.0.
- **Published.** Four commits on `main`, pushed over SSH. The untracked local
  inventory is confirmed absent from the remote.
- **Issue backlog.** 17 issues with priority and area labels; the three genuinely
  complete ones closed against published, verified artifacts.
- **Sprint board.** *GHL Leadflow Demo Sprint* — statuses Backlog, Ready, In
  Progress, Testing, Done, Blocked, plus a P0–P3 priority field. All 17 issues
  loaded and set to their real state: three Done, one Ready, eight Blocked,
  five Backlog. The board is private; this file is the public mirror of it.

# In Progress

- Nothing. This milestone is complete.

# Blocked

- **All GHL, n8n, and Google implementation work.** No external resource has
  been created. This is deliberate sequencing, not an obstacle.
- **n8n hosting decision.** Cannot be finalized until we know whether an n8n
  instance already exists on the interviewer's side. Reusing one beats standing
  one up. See [`docs/integration-options.md`](docs/integration-options.md).
- **Docker engine is stopped**, so container-level inventory is undetermined and
  a self-hosted n8n cannot start until it is started. Only relevant if
  self-hosting is chosen.

# Known risks carried forward

- **Two unverified GoHighLevel capabilities hold up the idempotency design:**
  the matching semantics of contact upsert, and whether opportunities can be
  searched by a custom-field value. Items 11 and 12 in
  [`docs/integration-options.md`](docs/integration-options.md) §5. Both are
  five-minute checks once a token exists, and three documents lean on them.
- **The documentation-to-implementation ratio is now the main risk.** The design
  set is thorough and nothing runs. One passing test case changes the meaning of
  the whole repository; more prose does not.

# Environment

| Area | State |
|---|---|
| Toolchain | Git, GitHub CLI, Node, npm, Claude Code present and verified |
| Docker | Installed, engine stopped |
| Playwright | Not installed — required later for E2E evidence |
| n8n | Not detected locally |
| GoHighLevel | No access configured, no credentials requested |
| Google | No integration configured |
| Tunnel | ngrok installed, not running, auth state unconfirmed |

Detail in [`docs/environment.md`](docs/environment.md).

# Decisions

| ID | Decision |
|---|---|
| [ADR-001](docs/decisions/ADR-001-integration-hierarchy.md) | Integration order: official MCP → official API → UI → browser automation → manual |
| [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) | `externalLeadId` is the primary identity; `contactId` only after GHL persistence; email/phone are secondary signals |
| [DECISION-001](docs/decisions/DECISION-001-ai-boundaries.md) | AI may summarize, extract, classify, and suggest — never approve or reject financial requests |
| — | Repository stays public for now; Git transport is SSH; sensitive environment detail is not published |
| — | Mermaid is the diagramming tool, in place of Excalidraw |
| — | First golden path is a single service type; four-service routing and appointments follow once it is stable |

# Next 3 actions

1. **Ask whether an n8n instance already exists.** One question, and it removes
   the largest unknown in the sprint. Reusing an instance eliminates tunnel
   rotation, Google OAuth setup, and the trial execution cap in one move.
2. **Create the GoHighLevel sandbox and immediately verify the two unproven
   capabilities** — contact upsert matching semantics, and searching
   opportunities by a custom-field value. If either is unsupported, the
   idempotency design needs rework, and that is far cheaper to discover on day
   one than on day two.
3. **Implement TC-01 end to end, then immediately TC-02**, before adding any
   further scope. One passing duplicate-suppression test is worth more than any
   additional design document.

# Demo readiness

**NOT READY.**

No end-to-end flow exists. No GHL, n8n, or Google resource has been created. No
test case has passed. What exists is a design, a test contract, and a
publishable repository baseline — which is the honest state of the work after
architecture and before implementation.
