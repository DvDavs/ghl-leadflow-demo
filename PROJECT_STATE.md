# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 7 — failure, retry and human handoff (P08). The retry half is
built, published and evidenced. Reconciliation is built and cannot run yet.**

A downstream failure no longer loses the lead and no longer lies to the sender.
The backup write is answered `202 retry_scheduled` and retried on a bounded
ladder held by a database-persisted wait; a transient failure that clears
converges on exactly one backup row; a failure that does not clear ends in a
ledger `failed`, a `needs_human` row, and a `run_log` outcome that cannot be
confused with a validation rejection. Validation also stopped rejecting
phone-only leads.

**Nine scenarios pass against the deployed artifacts**: **TC-01**, **TC-02**,
**TC-03**, **TC-09** (unreachable lead refused before any business write),
**TC-10** (transient failure detected, persisted, retry scheduled), **TC-11**
(retry converges on exactly one record), **TC-12** (budget exhausts into a
visible terminal state), **TC-18** and **TC-19**. A tenth, **TC-02b**, still
covers an artifact that no longer exists.

**P08 re-ran four earlier rows rather than assuming them.** The rebuild spliced
a retry loop into the happy path, rewrote `Normalize and Authorize`, and
reparameterized `Sheets: leads_backup` — so TC-01, TC-02, TC-18 and TC-19 were
all covering a workflow that no longer existed. Each was re-executed against
the P08 artifact and each held.

What is *not* proven is **TC-17**, reconciliation. The sweep is built, exported
and deliberately inactive: it needs a read-only GoHighLevel credential that
does not exist. Its query has never returned a live `200`, so it is recorded as
`BLOCKED`, not as a pass.

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
  TC-02, TC-03, TC-18 and TC-19 are `PASS` against the currently deployed
  artifacts; **TC-02b passed against a GHL workflow that no longer exists** and
  needs re-running; the rest are `BLOCKED` or deliberately deferred. A coverage
  table records which **n8n and GHL** workflow version each pass was observed
  against, because a passing test
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
- **Issue backlog.** 17 issues with priority and area labels, closed
  progressively against published, verified artifacts as each phase landed.
  **Read from GitHub while writing this: #1 through #8 closed, #9 through #17
  open.** Of the nine open, only #9 has been started.
- **Sprint board.** *GHL Leadflow Demo Sprint* — statuses Backlog, Ready, In
  Progress, Testing, Done, Blocked, plus a P0–P3 priority field. All 17 issues
  loaded and set to their real state. **Read from the board at the start of
  P08: nine Done, #10 Ready, #11 and #12 Blocked, five Backlog** — seventeen
  total, and the nine Done are exactly the nine closed issues above, so the two
  views agree. **P08 moved #10 Ready → In Progress**, observed, not assumed.
  **#10 stays open and In Progress at the end of P08**, because TC-17 is a
  named residual rather than a done criterion. Re-read the board rather than
  trusting this line; the repository has twice been bitten by treating a change
  that *should* have landed as one that did.

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
- **TC-02b — PASS against the pre-P07 workflow only; re-run required.** Two
  sequential submissions of the same fixture produced exactly one Contact and
  one open Opportunity, live-verified via MCP. **P07 demoted this row twice
  over:** its attribution to the duplicate-opportunity guard is retracted (the
  guard was never reached, because `Allow Re-entry` was off), and the GHL
  workflow it ran against no longer exists (v9 → v12). Full evidence and the
  demotion in [`TEST_CASES.md`](TEST_CASES.md). The first attempt surfaced
  three build defects (email not mapped to the standard attribute, the form
  builder forking two duplicate custom fields instead of reusing the P0 set,
  an Opportunity name left as unresolved placeholder text) — all three fixed
  and re-verified; see `docs/ghl-setup.md` "Gotchas".
- **The genuine re-inquiry branch — P07.** `LeadFlow Demo — Form to Opportunity`
  now opens with a `Find Opportunity` step scoped to `Status = open` on the demo
  pipeline. `Not Found` is the untouched original path plus `inquiry_count = 1`;
  `Found` applies `repeat-inquiry`, appends an internal note carrying the new
  intent, increments `inquiry_count`, and pulls the opportunity back to
  `Contacting` — gated by a second `Find Opportunity` filtered to `Follow-up`, so
  that a lead sitting at `Qualified` is not dragged backwards. Built in the UI
  (workflows remain write-less over MCP), published as **version 12**, and proven
  by **TC-03** with live MCP reads. **What TC-03 did not exercise:** the
  `Not Found` arm of that second step — the arm that actually protects a
  `Qualified` or `Appointment` deal — is designed and published but unobserved.
  Procedure, scope limits and rejected alternatives in
  [`docs/ghl-setup.md`](docs/ghl-setup.md).
- **Opportunity-side P0 guard — a different mechanism than ADR-002 planned.**
  GHL's native duplicate-opportunity block (location setting +
  workflow-action toggle) is confirmed configured and ~~, via TC-02b, confirmed
  to hold for a quick sequential resubmission~~ **has never been exercised —
  attribution retracted in P07**. It is person-scoped, not
  event-scoped, so it does not close the gap ADR-002 originally described —
  see "Known risks" below and ADR-002 "Consequences to watch".
- **Bounded retry with backoff — P08.** A failed `leads_backup` write now
  answers **202 `retry_scheduled`**, not 500, because the workflow owns the
  outcome and 500 would be a lie. The retry is held inside the original
  execution by a **database-persisted** `Wait` that loops back through the
  fault gate, so the switch is re-read on every attempt and a transient failure
  can genuinely clear. Budget: **3 attempts, base 70s, ×2, additive-only jitter
  0–20%, cap 300s** — every constant in one Code node. Observed live: 80s then
  166s, terminal at 4m03s. The 70-second base and the one-sided jitter are both
  forced by an n8n behaviour, not taste: a wait under 65 seconds is held in
  memory rather than persisted, and symmetric jitter would drop the first retry
  under that line. See [`docs/n8n-setup.md`](docs/n8n-setup.md) §5b.
- **Terminal handoff — P08.** Exhaustion writes ledger `failed`, one
  `needs_human` row (`status=open`, `owner=unassigned`,
  `lastAction=retry_exhausted`) and a `run_log` `outcome=retry_exhausted`
  distinct from both `invalid_payload` and `unauthorized`. The `needs_human`
  tab is written for the first time. Manual replay needed no new tooling:
  `Ledger State` short-circuits only on `completed`, so a `failed` row is
  re-claimed on the next delivery of the same `eventId`.
- **Validation contract loosened — P08.** `email` alone is no longer required.
  The rule is `opportunityId` + `contactId` + **at least one of** email or
  phone, and the 422 names the rule (`email_or_phone`) rather than blaming one
  field. The old rule rejected a phone-only lead the business could have called
  back, which is the one thing `architecture.md` §7's invariant forbids.
- **Operator-only fault injection — P08.** The `leadflow_test_controls` Data
  Table arms the downstream failure for TC-10/11/12. It is deliberately not a
  payload field — a public form must never be able to steer the pipeline into
  its own failure path or into the human-review queue. Append-only (n8n exposes
  no row update), so the switch carries its own history. Fails open by
  construction. **Left `off`.**
- **Reconciliation sweep — P08, built and inactive.** 12 nodes, schedule every
  10 minutes, one candidate at a time. Asks GHL for recent opportunities and
  asks *our own ledger* whether it has seen each derived `eventId` — the
  question moved to the only side that can answer it, because
  `search-opportunity` has no custom-field filter. Safe to run twice by
  construction. Artifact:
  [`n8n/workflows/reconciliation-sweep.sanitized.json`](n8n/workflows/reconciliation-sweep.sanitized.json).
- **Internal test harness — P08.** Two manual-trigger-only n8n workflows made
  the whole reliability suite executable without a browser and without anyone
  handling the shared secret: a sender that injects
  `$vars.GHL_WEBHOOK_SHARED_SECRET` in the HTTP node's own expression at send
  time — so it never enters an item or execution data — and an evidence reader
  over the three sheet tabs, the ledger and the fault switch. Neither has a
  public trigger.
- **Three defects found by the tests they were meant to pass.** The 422 body
  named no field; every node on the failure branch read `$json`, which by then
  held the row the previous write had returned rather than the decision item;
  and the `needs_human` append had an empty `columns.schema`, so the terminal
  handoff silently did not happen while the ledger said `failed`. All three
  fixed and re-run. The third is the one worth remembering.

# In Progress

- **Issue #10 — failure, retry and observability.** TC-09 through TC-12 pass
  against the deployed workflow. TC-17 is the residual: built, inactive,
  waiting on a credential. The issue stays **open** with that residual named,
  rather than being closed on four of five acceptance criteria.

# Blocked

- **TC-17 — reconciliation.** The sweep exists as a 12-node published artifact
  and is deliberately **not activated**. It needs a GoHighLevel credential n8n
  does not have, and cannot borrow: the OAuth grant used everywhere else in
  this project belongs to the Claude Code MCP client, whose token lives in that
  client's own store bound to its `client_id`/`client_secret`. **An MCP session
  is not a runtime credential.** The proportionate fix is a read-only Private
  Integration scoped to `opportunities.readonly` and nothing else — one scope,
  because the opportunity search already embeds the contact's name, email and
  phone.
- **TC-02b — still not re-run against GHL v12.** It needs two live submissions
  of the public GHL form. No browser automation was registered in the P08
  session, and the form has no documented submit endpoint, so this did not move.
- **Pre-P07 `inquiry_count` null safety — not addressed in P08.** Same cause:
  exercising it requires a form submission from a legacy contact.
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
- **Nine fictional diagnostic contacts now pollute the demo location**, and the
  arithmetic is spelled out because earlier versions of this bullet did not
  reconcile. All nine: Marisol Vega, Tobias Lind, Camila Torres, Camila Torres
  02, Sofia Bennett, David Demo, Valeria Cruz, the `=1+1 Testcase` formula
  fixture, and — from P07 — Priya Chandran. **Six have an opportunity with no
  `leads_backup` row** (the first six, all build artifacts predating the n8n
  leg), and each is a live instance of TC-17's scenario: a GHL opportunity
  whose webhook never landed. **Three are not**: Valeria Cruz (TC-01), the
  formula fixture (TC-19) and Priya Chandran (TC-03) all fired their webhook
  normally and have rows. Priya Chandran demonstrates the gap TC-17 *cannot*
  reach — her second inquiry produced no opportunity and no row, so an
  opportunity-keyed sweep scans straight past it. Useful as reconciliation test
  data; noise for a demo walkthrough. Cleanup is pending an explicit decision;
  nothing has been deleted.
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
  workflow-action toggle), ~~confirmed live via TC-02b~~. It is
  **person-scoped, not event-scoped**. **Two corrections from P07.** First, the
  re-inquiry suppression is **fixed** — the compensating branch is built and
  TC-03 passes. Second, and less comfortably: **the guard has never actually
  been exercised.** TC-02b ran with `Allow Re-entry` off, so its second
  submission never re-entered the workflow and `Create Opportunity` never ran a
  second time — which looks identical to the guard blocking it. The guard is
  configured, and now sits as a backstop behind the `Find Opportunity` split
  that reaches `Create Opportunity` only on the `Not Found` path. See ADR-002
  "Consequences to watch".
- **A re-inquiry leaves no `leads_backup` row, and reconciliation cannot find
  it.** No second Opportunity means no webhook. `architecture.md` §5's "Sheets
  is event-grained" is therefore not true for re-inquiries yet: one person with
  two inquiries is 1 contact, 1 opportunity, 1 row. Deferred deliberately — GHL
  exposes no stable per-submission identity to key a downstream
  `inquiry.repeated` event on, and the two available shortcuts are both actively
  harmful (ADR-002, item 2). **This is not a TC-17 instance** — TC-17 sweeps for
  an Opportunity lacking a backup row, and here there is no Opportunity while the
  existing one already has its row. It is a distinct, currently unreconcilable
  gap, and it is the strongest remaining argument for building the downstream
  event once GHL offers an identity to key it on.
- **An accidental double submission is now indistinguishable from a genuine
  re-inquiry**, and is treated as one — tag, note, and `inquiry_count = 2`.
  GHL supplies no submission id to separate them; HighLevel's own feature
  request for one is open and unshipped. The direction of the error is
  deliberate: a visible duplicate artifact is recoverable, a swallowed hot lead
  is not. TC-02b's observable output changed, and it has not been re-run — so
  its outcome under the deployed workflow is unknown, not assumed.
- **The Opportunity name is a snapshot from creation time.** After the TC-03
  re-inquiry the contact's service interest reads `Mortgage` while the
  opportunity is still named `... - Real Estate`. A rep sees the original
  intent on the board and the new one only in the note. Left as-is deliberately
  — renaming would overwrite the deal's own identity — but it is a real
  readability gap worth naming before a demo walkthrough.
- **`Math Operation` will hit a null for every contact created before P07.**
  `inquiry_count` exists on the location but nothing had ever written to it
  before P07, so pre-P07 contacts have it unset. `David Demo` and
  `Valeria Cruz` both have an **open** opportunity, so a resubmission from
  either takes the `Found` path straight into an increment on a null —
  behaviour HighLevel does not document and that has not been observed.
  Unclosed; see [`docs/ghl-setup.md`](docs/ghl-setup.md) build rule 3.
- **The re-inquiry branch is pipeline-scoped; the guard it compensates for is
  person-scoped.** A contact whose only open opportunity is in another pipeline
  still falls through to the silent-swallow path, now with `inquiry_count = 1`
  written over it. Unreachable in a single-pipeline demo, real the moment a
  second pipeline exists. Fix is one filter removal.
- **`inquiry_count` is per-opportunity, not lifetime.** When the previous
  opportunity is won or lost, a new inquiry resets it to `1`.
- **A GHL workflow edit can sit unpublished, exactly like an n8n one.** P07 read
  `version: 9` after the branch was reported built, and `12` after it was
  published. `get-workflow` exposes no step detail, so **the version number is
  the only machine-checkable proof a UI edit shipped**. Always re-read it before
  executing a test against the change.
- **Concurrent-call behaviour is still unverified.** Both the P04 contact-upsert
  probe and the P05 duplicate-opportunity test were strictly sequential (TC-02b
  ran ~1 minute apart); neither is evidence about true concurrency.
- **The trial location's owner First/Last Name is still real** (`get-location`
  `firstName`/`lastName`). Three UI correction requests did not fix it —
  likely a different settings screen (team/user profile, not Business
  Profile) than the one already fixed for email/phone/address. Not committed
  to git and not part of the interview-facing fixture, so not blocking, but
  still open.
- **A retry that dies mid-wait is not re-driven.** The retry lives inside the
  original execution rather than in a sweeper polling the ledger — a deliberate
  trade that keeps exactly one copy of the backup-write node, so
  `cellFormat: RAW` cannot drift between two copies. The cost: an execution
  lost while waiting leaves its ledger row `retry_scheduled` forever.
  **There is a live instance:** ledger row `id=5`,
  `ghl:opportunity-created:p08-tc10-transient`, orphaned by a P08 execution
  that died on a defect before that defect was fixed. Left in place because it
  is the honest shape of the limitation. The reconciliation sweep does **not**
  rescue it — that `opportunityId` is synthetic and has no GHL Opportunity.
- **A `failed` ledger row is not proof a human was told.** The `needs_human`
  write is a separate node and can fail on its own; ledger row `id=7` is
  exactly that case, from TC-12's first run. Judge the handoff on the
  `needs_human` row, never on the ledger alone.
- **The retry attempt counter depends on an undocumented n8n resolution rule.**
  Downstream nodes read `$('Retry Decision').first()`, and within a loop
  iteration n8n resolves that to the *current* run — verified live across three
  attempts in TC-12, but not a documented guarantee. If the ladder ever starts
  repeating attempt 1, this is the first thing to check.
- **The reconciliation sweep recovers a thinner row than the webhook path.**
  `business` is empty and `service` is **derived** by splitting the Opportunity
  name on `" - "`, because both live on contact custom fields that would need a
  scope the sweep did not ask for. Recovered rows carry
  `lastAction=reconciled` so they cannot be mistaken for first-class
  deliveries. Adding `contacts.readonly` is a defensible upgrade; taking it
  silently is not.
- **One parameter in the sweep is unverified.** The location is sent as
  `location_id`; it has never been confirmed against a live `200` because no
  credential has existed to make the call. The alternative spelling is
  `locationId`. The node carries a note saying so.
- **P08 fixtures now sit in the durable backup.** `p08-regress-alpha`,
  `p08-tc10b-transient` and `p08-tc19-formula` have `leads_backup` rows;
  `p08-tc12-persistent` and `p08-tc12b-persistent` are terminal `failed` with
  no row. All fictional, all carrying `source = P08 Internal Test Harness` —
  the column to filter on before a demo walkthrough.
- **The documentation-to-implementation ratio is improving but is still the
  main risk.** The GHL leg, the n8n ingress, the durable backup and now the
  retry and human-handoff paths all run and are proven end to end.
  Reconciliation is the one piece still documented but unproven.

# Environment

| Area | State |
|---|---|
| Toolchain | Git, GitHub CLI, Node, npm, Claude Code present and verified |
| Docker | Installed, engine stopped |
| Playwright | **Not available as a tool in the P08 session.** The MCP registry held engram, context7, excalidraw, leadconnector and n8n — no browser automation. Everything GHL-UI-shaped (TC-02b's re-run, the `inquiry_count` null fix) is blocked on this; everything n8n-shaped was done over MCP instead |
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
| — | The re-inquiry branch is gated by **`Find Opportunity`**, not `If/Else`. HighLevel filters opportunity fields in a condition only when the workflow has an opportunity-based trigger, and this one triggers on a form submission — see [`docs/ghl-setup.md`](docs/ghl-setup.md) |
| — | The stage pull-back is gated by a **second `Find Opportunity` filtered to `Follow-up`**, never an unconditional move. Dragging an opportunity back from `Qualified` or `Appointment` would corrupt stage-duration metrics — `architecture.md` §3 |
| — | `inquiry_count` is **initialised to 1 on the first inquiry, after `Create Opportunity`**, so a failure there can never block opportunity creation. This protects contacts created from P07 onward only — **pre-P07 contacts still have the field unset**, and the increment's behaviour on a null is undocumented and unobserved; see "Known risks" |
| — | **No downstream `inquiry.repeated` event.** GHL exposes no stable per-submission identity; reusing the opportunity-created key would make the ledger discard the re-inquiry as a redelivery, and a receive-time key would break retry dedup. Compensation stays in GHL and the event-grained backup is deferred — see [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) |
| — | A failed backup answers **202 `retry_scheduled`**, not 500. The workflow owns a durable retry, so 500 — "this failed, it's yours" — would be false. 500 survives only for a one-attempt budget, which is unreachable at `maxAttempts = 3` |
| — | The retry lives **inside the original execution** on a durable `Wait`, not in a separate ledger-polling sweeper. One copy of the backup-write node means `cellFormat: RAW` cannot drift between two copies — a failure this repo has already had once. Cost: an execution lost mid-wait is not re-driven |
| — | Retry budget: **3 attempts, base 70s, ×2, jitter additive-only 0–20%, cap 300s.** The 70s base and one-sided jitter are forced by n8n holding sub-65-second waits in memory instead of persisting them |
| — | Validation requires `opportunityId` + `contactId` + **at least one of** email or phone. A phone-only lead is contactable and must not be rejected |
| — | Failure injection lives in an **operator-only, append-only Data Table** that fails open — never a payload field, because that would let an anonymous form submitter choose which leads fail |
| — | The reconciliation sweep asks **our ledger**, not GHL, whether an event was seen. `search-opportunity` cannot filter by custom field, so the vendor cannot answer the question — see [`docs/n8n-setup.md`](docs/n8n-setup.md) §5d |
| — | n8n gets its own **read-only Private Integration** scoped to `opportunities.readonly`. The Claude Code MCP OAuth grant is not a runtime credential and cannot be lent |

# Next 3 actions

1. **Give the reconciliation sweep a credential and run TC-17** (Issue #10's
   residual). Create a GHL Private Integration scoped to
   `opportunities.readonly`, bind it to an n8n Header Auth credential, confirm
   the location query-parameter spelling on the first live `200` — it is
   currently `location_id` and **unverified** — then activate the sweep. Six
   opportunities with no `leads_backup` row are sitting in the location as
   ready-made test data. Assert the second run changes nothing, and that
   neither Valeria Cruz nor the formula fixture is touched.
2. **Re-run TC-02b against GHL v12, and exercise the duplicate-opportunity
   guard for real.** Unchanged from P07, and unmoved: it needs two live
   submissions of the public form. With re-entry on, a fast double submission
   can finally reach `Create Opportunity` twice for one contact, which is the
   first test that would actually exercise the guard. Until it runs, the guard
   is configured and unproven.
3. **Close the `inquiry_count` null on pre-P07 contacts**, and clean up the
   accumulated fixture noise — the orphaned `retry_scheduled` ledger row, the
   `failed` row with no `needs_human` row, and the `p08-` rows in
   `leads_backup`. All are documented rather than hidden; none is dangerous;
   all of them are noise in a demo walkthrough.

# Demo readiness

**PARTIAL.**

**The golden path is demonstrable end to end.** A lead submits the live form
and the pipeline produces one Contact, one Opportunity, one backup row, and a
`run_log` trail sharing one `correlationId`. Redeliver the same webhook and it
answers `200 already_processed` with no second row. Send it without the right
secret and it answers `401` having written nothing but the audit line. Submit
a name that looks like a spreadsheet formula and it is stored as text.

Submit again as the same person with a different need, while their first
opportunity is still open, and the CRM says so: a `repeat-inquiry` tag, a note
carrying the new intent, `inquiry_count = 2`, and the deal pulled back out of
`Follow-up` into `Contacting` — with no duplicate opportunity and no second
contact.

That is enough to walk an interviewer through the whole flow and defend each
decision with an execution record rather than a screenshot — including the
three places where the record is *weaker* than an earlier version of this file
claimed: the duplicate-opportunity guard has never been exercised, TC-02b's
pass no longer covers the deployed workflow, and a re-inquiry writes no backup
row and cannot be recovered by the reconciliation sweep as designed.

**And the reliability half is now demonstrable too.** Submit a lead with no way
to reach them and it is refused `422` naming the rule, with nothing written but
the audit line. Break the downstream write and the caller gets `202`, the
execution goes to sleep in the database with a due time, and the ledger says
`retry_scheduled` with the reason. Fix the breakage and it wakes up, writes
exactly one row, and clears its own retry state. Leave it broken and it spends
a bounded budget — 3 attempts over four minutes, visible attempt by attempt in
`run_log` — then stops, marks itself `failed`, and puts the lead in front of a
human instead of dropping it.

**What it still cannot demonstrate is reconciliation.** The sweep is built,
exported and inactive; its query has never returned a live `200`, and six
opportunities with no backup row are still sitting in the CRM as proof it is
missing. P07 added a second kind of gap the sweep could not see even once it
runs: a re-inquiry writes no backup row *and* creates no opportunity, so an
opportunity-keyed sweep scans past it.

Three things are weaker than a clean matrix would suggest, and are stated here
rather than buried: TC-02b still covers a GHL workflow that no longer exists;
the duplicate-opportunity guard has never been exercised; and P08's own tests
found three defects, one of which produced a `failed` ledger row with nobody
told — the exact silent loss TC-12 exists to disprove. That row is still in the
ledger.

All evidence is sequential. Nothing here says anything about concurrency.
