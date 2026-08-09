# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 4 — GHL form-to-pipeline build (P05).**

The real GHL tramo — Form → Contact → Opportunity → Pipeline — is built,
published, and proven live: two sequential submissions of the same fixture
produce exactly one Contact and one open Opportunity. n8n, Google Sheets, and
the outbound webhook are still out of scope; this milestone proves the
GHL-native leg only.

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
- **Test matrix.** [`TEST_CASES.md`](TEST_CASES.md) — 19 scenarios. TC-02b is
  `PASS` with live evidence; the rest are `BLOCKED` or deliberately deferred.
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

- **GHL tramo built and proven — P05.** Form → Contact → Opportunity →
  Pipeline runs live. 7 P0 custom fields, 5 P0 tags, the `LeadFlow Demo
  Pipeline` (7 exact stages), the `LeadFlow Demo — Service Inquiry` form, and
  the `LeadFlow Demo — Form to Opportunity` workflow all exist and are
  published. Custom fields and tags were created via MCP; pipeline, form, and
  workflow are UI-only — confirmed by exhaustive registry search, no
  write operation exists for any of the three (see
  [`docs/ghl-setup.md`](docs/ghl-setup.md) "Registry gaps confirmed live").
- **TC-02b — PASS.** Two sequential submissions of the same fixture produced
  exactly one Contact and one open Opportunity, live-verified via MCP. Full
  evidence in [`TEST_CASES.md`](TEST_CASES.md). The first attempt surfaced
  three build defects (email not mapped to the standard attribute, the form
  builder forking two duplicate custom fields instead of reusing the P0 set,
  an Opportunity name left as unresolved placeholder text) — all three fixed
  and re-verified; see `docs/ghl-setup.md` "Gotchas".
- **Opportunity-side P0 guard — a different mechanism than ADR-002 planned.**
  GHL's native duplicate-opportunity block (location setting +
  workflow-action toggle) is confirmed configured and, via TC-02b, confirmed
  to hold for a quick sequential resubmission. It is person-scoped, not
  event-scoped, so it does not close the gap ADR-002 originally described —
  see "Known risks" below and ADR-002 "Consequences to watch".

# In Progress

- Nothing on the GHL leg. Next work moves to Issue #7 (workflow + outbound
  webhook to n8n) and Issue #8 (n8n Cloud + Sheets).

# Blocked

- **TC-01 in full, and the rest of the E2E build.** The GHL leg (form →
  Contact → Opportunity) is proven; the backup-sheet row and `run_log`
  boundary still need n8n and Google Sheets, neither of which exists yet.
- **Docker engine is stopped**, so container-level inventory is undetermined.
  Only relevant if the Docker + ngrok fallback is ever needed.

# Known risks carried forward

- **The opportunity-side race mitigation ADR-002 originally wanted still does
  not exist.** Confirmed: `search-opportunity` cannot filter by
  `external_lead_id`. A **different** guard now exists instead (P05): GHL's
  native duplicate-opportunity block (location setting +
  workflow-action toggle), confirmed live via TC-02b. It is **person-scoped,
  not event-scoped** — it stops a quick duplicate resubmission, but while an
  opportunity is open it also currently suppresses a genuine re-inquiry
  (TC-03's compensating branch — note + `inquiry_count` + `repeat-inquiry`
  tag — is not built yet). See ADR-002 "Consequences to watch".
- **Concurrent-call behaviour is still unverified.** Both the P04 contact-upsert
  probe and the P05 duplicate-opportunity test were strictly sequential (TC-02b
  ran ~1 minute apart); neither is evidence about true concurrency.
- **The trial location's owner First/Last Name is still real** (`get-location`
  `firstName`/`lastName`). Three UI correction requests did not fix it —
  likely a different settings screen (team/user profile, not Business
  Profile) than the one already fixed for email/phone/address. Not committed
  to git and not part of the interview-facing fixture, so not blocking, but
  still open.
- **The documentation-to-implementation ratio is improving but is still the
  main risk.** One full GHL leg now runs and is proven end to end; n8n,
  Sheets, and the webhook remain entirely unbuilt.

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
| — | Trial location identity sanitized partially (P05) — business contact fields (email, phone, address, city, state, postal, country) are now fictional; the owner's `firstName`/`lastName` are still real, unresolved after three correction attempts — see "Known risks" |
| — | P0 opportunity-duplicate guard: GHL-native, person-scoped (location setting + workflow-action toggle), not the event-scoped `external_lead_id` check ADR-002 wanted — see ADR-002 "Consequences to watch" |
| — | Downstream delivery identity for the GHL-native path: `ghl:opportunity-created:<opportunityId>`, dedupes webhook redeliveries only, never gates whether to create the Opportunity — see ADR-002 |

# Next 3 actions

1. **Configure the workflow's outbound webhook to n8n and stand up n8n Cloud.**
   Issue #7 (Ready) then Issue #8 — both UI/external-service work the MCP
   registry cannot touch.
2. **Build the compensating branch for a genuine re-inquiry** (note +
   `inquiry_count` + `repeat-inquiry` tag) so the P0 duplicate-opportunity
   guard stops silently suppressing TC-03's case while an opportunity is open.
3. **Implement TC-02 (webhook redelivery) and TC-09–TC-12 (validation,
   retry, failure)** once n8n exists, using the `ghl:opportunity-created:
   <opportunityId>` delivery identity already documented in ADR-002.

# Demo readiness

**PARTIAL.**

The GHL leg is real and proven: a lead can submit the live form twice and the
CRM ends up in exactly the state ADR-002 predicts — one Contact, one open
Opportunity, no duplicate. That is the first genuinely executed (not just
designed) piece of this pipeline. n8n, Google Sheets, the outbound webhook,
and every reliability scenario (TC-09 onward) remain entirely unbuilt, so the
demo is not yet end-to-end.
