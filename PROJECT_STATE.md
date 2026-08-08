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
- **Test matrix.** [`TEST_CASES.md`](TEST_CASES.md) — 16 scenarios, all
  `BLOCKED`, none passing.
- **Integration research.**
  [`docs/integration-options.md`](docs/integration-options.md), sourced from
  official documentation only.

# In Progress

- Publishing the baseline to the public remote over SSH and reflecting real
  state in GitHub Issues and the sprint Project.

# Blocked

- **All GHL, n8n, and Google implementation work.** No external resource has
  been created. This is deliberate sequencing, not an obstacle.
- **n8n hosting decision.** Cannot be finalized until we know whether an n8n
  instance already exists on the interviewer's side. Reusing one beats standing
  one up. See [`docs/integration-options.md`](docs/integration-options.md).
- **Docker engine is stopped**, so container-level inventory is undetermined and
  a self-hosted n8n cannot start until it is started. Only relevant if
  self-hosting is chosen.

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

Detail in [`docs/environment.md`](docs/environment.md). Local security findings
are maintained outside version control.

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

1. **Confirm the n8n hosting path** — ask whether an n8n instance already
   exists. This single answer removes the largest unknown in the sprint.
2. **Create the GoHighLevel test location**, pipeline, custom fields, and lead
   capture form — the prerequisite that unblocks most of the test matrix.
3. **Implement the single-service golden path end to end** (TC-01), then
   immediately prove idempotency with TC-02 before adding any further scope.

# Demo readiness

**NOT READY.**

No end-to-end flow exists. No GHL, n8n, or Google resource has been created. No
test case has passed. What exists is a design, a test contract, and a
publishable repository baseline — which is the honest state of the work after
architecture and before implementation.
