# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 5 — outbound webhook, n8n ingress, and Sheets backup (P06).
Complete.**

The golden path runs end to end and is proven: a lead submits the live form,
GHL creates the Contact and Opportunity, the outbound webhook delivers to n8n,
ingress validates a shared secret, a Data Table ledger claims the event, and
`leads_backup` plus `run_log` are written. Issues #7 and #8 are closed against
executed acceptance criteria.

Five scenarios pass with live evidence: **TC-01** (happy path), **TC-02**
(webhook redelivery deduped), **TC-02b** (duplicate form submission, P05),
**TC-18** (unauthorized rejected, both the absent-secret and wrong-value
arms), and **TC-19** (formula injection through the public form).

What is *not* built is the reliability half — retry, failure handling,
reconciliation, and the re-inquiry branch.

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
- **Test matrix.** [`TEST_CASES.md`](TEST_CASES.md) — 20 scenarios. TC-01,
  TC-02, TC-02b, TC-18 and TC-19 are `PASS` with live evidence; the rest are
  `BLOCKED` or deliberately deferred. A coverage table records which n8n
  workflow version each pass was observed against, because a passing test
  proves the artifact it ran against and nothing later.
- **n8n ingress and Sheets backup — P06.** Webhook → allowlist normalization →
  shared-secret check → `leadflow_event_ledger` Data Table claim →
  `leads_backup` (Append or Update on `eventId`) → ledger `completed`, with
  deterministic 401 / 422 / 200 / 200-duplicate / 500 responses and
  append-only `run_log` boundaries. Published and active. Artifacts:
  [`n8n/workflows/ghl-opportunity-to-sheets.sanitized.json`](n8n/workflows/ghl-opportunity-to-sheets.sanitized.json),
  [`scripts/replay-webhook.ps1`](scripts/replay-webhook.ps1),
  [`docs/n8n-setup.md`](docs/n8n-setup.md).
- **Vendor documentation corrected against observation.** GHL nests declared
  Custom Data under `customData`, not at the payload root as its own example
  shows, and the real payload carries `contact_id` at the root although the
  example omits it. The first error cost six rejected deliveries. Both are
  written up rather than quietly worked around.
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

- Nothing. P06 closed; the next sprint item has not been started.

# Blocked

- **The reliability scenarios — TC-09 through TC-12, and TC-17.** Validation
  rejection is built and returns 422, but retry, retry-exhaustion, and the
  reconciliation sweep are not. These are the point of the demo and are the
  largest remaining gap.
- **TC-03, the genuine re-inquiry.** Still foreclosed by the person-scoped
  duplicate-opportunity guard; the compensating branch (note +
  `inquiry_count` + `repeat-inquiry` tag) is not built.
- **Docker engine is stopped**, so container-level inventory is undetermined.
  Only relevant if the Docker + ngrok fallback is ever needed.

# Known risks carried forward

- **Vendor documentation was wrong twice, and both errors were load-bearing.**
  GHL's documented outbound-webhook example shows Custom Data flattened to the
  payload root; it actually arrives nested under `customData`. The same example
  shows no contact-id field; the real payload carries `contact_id` at the root.
  The first error cost six diagnostic deliveries. Treat the vendor example as
  a hypothesis and a captured payload as evidence — see
  [`docs/n8n-setup.md`](docs/n8n-setup.md). GHL also misspells its own field as
  `pipleline_stage`.
- **Eight diagnostic contacts and opportunities now pollute the demo
  location** (Marisol Vega, Tobias Lind, Camila Torres, Camila Torres 02,
  Sofia Bennett, Valeria Cruz, and the `=1+1 Testcase` formula fixture). All
  fictional. Every one except Valeria Cruz and the formula fixture is a build
  artifact with **no `leads_backup` row** — which makes each a live instance
  of TC-17's scenario, a GHL opportunity whose webhook never landed. Useful as
  reconciliation test data; noise for a demo walkthrough. Cleanup is pending
  an explicit decision; nothing has been deleted.
- **Saving an n8n workflow is not publishing it.** n8n keeps a draft and an
  active version, and the API's read returns the draft. A security fix looked
  applied for over an hour while production served the old version. Always
  compare `activeVersionId` against the current `versionId` — see
  [`docs/n8n-setup.md`](docs/n8n-setup.md) §5.
- **`cellFormat: RAW` must survive every future edit to a Sheets node.**
  Re-picking a node in the UI can reset its options, and the n8n default is
  `USER_ENTERED`, which would silently re-open formula injection from the
  public form.
- **`Sofia  Bennett - Real Estate`** carries a double space, so the Opportunity
  Name merge template has a spacing defect. Cosmetic, unfixed.

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
| n8n | **n8n Cloud live** — workflow published and active on its production webhook URL. Variables and Data Tables both confirmed available on the plan. MCP server connected, tools available. |
| GoHighLevel | **Connected** — official MCP over OAuth, one trial location. No PIT. Operations require an explicit `locationId` even so. |
| Google | **Sheets connected to n8n** via a credential-store OAuth2 credential, bound only to the native Sheets node. Sheet is private. |
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
| — | The GHL→n8n payload contract is **declared** through Custom Data merge tags, not discovered from GHL's implicit body; n8n allowlists only the declared keys — see [`docs/n8n-setup.md`](docs/n8n-setup.md) |
| — | Ingress protection is an unguessable path plus a shared secret **in the body**, because the free Outbound Webhook action supports no headers and the signed alternative is billable. Weaker than a signature, and documented as such |
| — | Every Google Sheets write forces `cellFormat: RAW`. The node default, `USER_ENTERED`, turned public form text into live formulas in the durable backup — reachable with no secret at all |
| — | The ledger is an n8n Data Table, kept separate from `run_log`: `run_log` is a narrative for humans, the ledger is queried state that decides control flow, and a logging failure must not change behaviour |

# Next 3 actions

1. **Build the reliability half — TC-09 through TC-12.** Retry with backoff,
   retry exhaustion into a terminal failed state, and `needs_human` routing.
   The `Ledger: Fail` branch and the `needs_human` tab already exist as the
   landing places; nothing drives them yet. This is the largest gap between
   what the demo claims and what it proves.
2. **Build the reconciliation sweep (TC-17).** Eight opportunities with no
   `leads_backup` row are already sitting in the location as ready-made test
   data. ADR-002 makes this backstop more load-bearing than originally
   planned, since the opportunity-side race mitigation does not exist.
3. **Build the compensating branch for a genuine re-inquiry (TC-03)** — note +
   `inquiry_count` + `repeat-inquiry` tag — so the person-scoped
   duplicate-opportunity guard stops silently suppressing a real second
   inquiry while an opportunity is open.

# Demo readiness

**PARTIAL.**

**The golden path is demonstrable end to end.** A lead submits the live form
and the pipeline produces one Contact, one Opportunity, one backup row, and a
`run_log` trail sharing one `correlationId`. Redeliver the same webhook and it
answers `200 already_processed` with no second row. Send it without the right
secret and it answers `401` having written nothing but the audit line. Submit
a name that looks like a spreadsheet formula and it is stored as text.

That is enough to walk an interviewer through the whole flow and defend each
decision with an execution record rather than a screenshot.

**What it cannot yet demonstrate** is the half the design says is the point:
retry, retry exhaustion, human-review routing, and reconciliation. Every
reliability claim in `architecture.md` §7 beyond validation is still design,
not evidence — and eight opportunities with no backup row are sitting in the
CRM as proof that the reconciliation sweep is missing.

All evidence is sequential. Nothing here says anything about concurrency.
