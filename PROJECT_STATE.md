# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 3 — GHL access and capability verification.**

The official HighLevel MCP is connected via OAuth, scoped to one disposable
trial location. The two highest-priority unknowns carried forward from
Milestone 2 have been checked against live data. No E2E flow exists yet — this
milestone closes unknowns, it does not build the pipeline.

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

- **GHL MCP access.** Official HighLevel MCP connected over OAuth
  (`https://services.leadconnectorhq.com/mcp/anthropic/v2`), project-scoped
  `.mcp.json` holding only the endpoint URL, no PIT created. Confirmed scoped
  to exactly one location. See [`docs/ghl-setup.md`](docs/ghl-setup.md).
- **Trial location identity — partially sanitized.** Location/business name
  fields are fictional (`LeadFlow Demo` / `Northstar Demo Services`). David
  explicitly approved leaving the pre-existing email, phone, website, and
  address as-is rather than requiring full fictional replacement. This is a
  deliberate scope decision, not an oversight.
- **Contact upsert matching semantics — resolved.** Live sequential probe
  (fictional fixtures, cleaned up after) confirms `upsert-contact` matches on
  email OR phone independently; either field alone merges into the existing
  contact, and the differing field is overwritten by the latest call.
  Concurrent-call behaviour remains unverified by design — the probe was
  sequential. See [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md).
- **Opportunity custom-field search — resolved, unfavourably.**
  `search-opportunity`'s schema (confirmed via `describe_operation`) has no
  custom-field parameter. ADR-002's planned second independent dedup check
  cannot be built against this operation. Flagged as a real design gap for a
  later phase, not papered over.
- **Custom fields capability — corrected.** Previously classified
  *partial — unconfirmed*; live discovery confirms dedicated read and write
  operations exist in the grant. No fixture custom field was created — the
  opportunity-search question resolved by schema inspection alone.
- **n8n hosting — decided.** Primary: n8n Cloud (provisioned, ready). Fallback:
  Docker local + ngrok. VPS and any existing server ruled out. See
  [`docs/integration-options.md`](docs/integration-options.md) §3–4.

# In Progress

- Nothing. This milestone is complete.

# Blocked

- **TC-01 and the rest of the E2E build.** No pipeline, form, or n8n workflow
  exists yet — deliberately out of this milestone's scope.
- **Docker engine is stopped**, so container-level inventory is undetermined.
  Only relevant if the Docker + ngrok fallback is ever needed.

# Known risks carried forward

- **The opportunity-side race mitigation does not exist.** Confirmed, not
  assumed: `search-opportunity` cannot filter by `external_lead_id`. The
  reconciliation sweep is now the only backstop for a raced duplicate
  opportunity. A follow-up design decision (client-side filter, or accept the
  documented residual risk) is needed before this is fully closed — see
  ADR-002 "Consequences to watch".
- **Concurrent-call behaviour of contact upsert is still unverified.** The
  live probe was sequential by design; it resolved matching semantics, not
  race behaviour.
- **The documentation-to-implementation ratio is still the main risk.** One
  live location and two resolved unknowns are real progress, but no lead has
  gone through the pipeline end to end yet.

# Environment

| Area | State |
|---|---|
| Toolchain | Git, GitHub CLI, Node, npm, Claude Code present and verified |
| Docker | Installed, engine stopped |
| Playwright | Not installed — required later for E2E evidence |
| n8n | Not detected locally; hosting decided as n8n Cloud (ready), Docker+ngrok fallback |
| GoHighLevel | **Connected** — official MCP over OAuth, one trial location. No PIT. |
| Google | No integration configured |
| Tunnel | ngrok installed, not running, auth state unconfirmed — only needed if n8n Cloud fallback triggers |

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
| — | GHL integration via official MCP over OAuth, not a Private Integration Token — see [`docs/ghl-setup.md`](docs/ghl-setup.md) |
| — | n8n hosting: n8n Cloud primary, Docker local + ngrok fallback; no VPS, no existing server |
| — | Trial location identity sanitized partially by explicit owner decision — name fields fictional, contact fields left as pre-existing real values |

# Next 3 actions

1. **Design or accept a mitigation for the opportunity-side race gap.**
   `search-opportunity` cannot filter by custom field, so ADR-002's planned
   second independent check does not exist. Decide: client-side fetch-and-filter
   on `external_lead_id`, or accept the reconciliation sweep as the sole
   backstop and document the residual risk formally.
2. **Stand up n8n Cloud and the inbound webhook.** Issue #8, now unblocked on
   the hosting decision.
3. **Implement TC-01 end to end, then immediately TC-02**, before adding any
   further scope. One passing duplicate-suppression test is worth more than any
   additional design document.

# Demo readiness

**NOT READY.**

No end-to-end flow exists yet. GHL access is live and two idempotency unknowns
are resolved (one favourably, one not), but no n8n or Google resource has been
created and no test case has passed. What exists is a design, a test contract,
a publishable repository baseline, and — new this milestone — a verified GHL
connection with empirical evidence instead of assumptions on two of the
riskiest design bets.
