# Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview.

The deliverable is not "a workflow that fires once". It is a pipeline that
survives duplicate events, missing fields, and downstream failures, and that
can prove it did so.

# Current milestone

**Milestone 6 — idempotency and the genuine re-inquiry (P07). Work complete
and evidenced; Issue #9's bookkeeping closes as this prompt ends.**

The golden path runs end to end and is proven, and a returning lead is no
longer swallowed. A second inquiry from a person who already has an open
opportunity now produces a `repeat-inquiry` tag, an internal note carrying the
*new* intent, an incremented `inquiry_count`, and a stage pull-back from
`Follow-up` to `Contacting` — instead of silence. Issues #7 and #8 are closed
against executed acceptance criteria; **#9 is still open and In Progress at the
time of writing**, and closes as this prompt ends — see "Sprint board" for why
that is stated as pending rather than done.

Five scenarios pass against the deployed artifacts, and a sixth passed against
one that no longer exists: **TC-01** (happy path), **TC-02**
(webhook redelivery deduped), **TC-02b** (duplicate form submission, P05 —
**demoted in P07**: its attribution was retracted and its pass covers the
pre-P07 GHL workflow only, so it needs re-running), **TC-03** (genuine
re-inquiry), **TC-18** (unauthorized rejected, both the absent-secret and
wrong-value arms), and **TC-19** (formula injection through the public form).

What is *not* built is the reliability half — retry, failure handling, and
reconciliation.

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
  loaded and set to their real state. **Read from the board while writing this,
  before the P07 closure: eight Done, one In Progress (#9), three Blocked, five
  Backlog** — seventeen total, and the eight Done are exactly the eight closed
  issues above, so the two views agree. **Pending, as this prompt closes:** #9
  moves to Done and #10 from Blocked to Ready, giving nine Done, one Ready, two
  Blocked, five Backlog. That transition is stated as pending rather than
  written as observed, because the board is private and this file is its only
  public mirror. Re-read the board rather than trusting this line; the
  repository has twice been bitten by treating a change that *should* have
  landed as one that did.

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

# In Progress

- **Issue #9 — idempotency and the duplicate scenario.** The work is complete
  and TC-03 passes; the issue and its board card close as this prompt ends. It
  is listed here rather than under Completed because, at the moment this file
  was written, GitHub still reported it open.
- Nothing else. P07's build is finished; the next sprint item (#10) has not
  been started.

# Blocked

- **The reliability scenarios — TC-09 through TC-12, and TC-17.** Validation
  rejection is built and returns 422, but retry, retry-exhaustion, and the
  reconciliation sweep are not. These are the point of the demo and are the
  largest remaining gap.
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
| — | The re-inquiry branch is gated by **`Find Opportunity`**, not `If/Else`. HighLevel filters opportunity fields in a condition only when the workflow has an opportunity-based trigger, and this one triggers on a form submission — see [`docs/ghl-setup.md`](docs/ghl-setup.md) |
| — | The stage pull-back is gated by a **second `Find Opportunity` filtered to `Follow-up`**, never an unconditional move. Dragging an opportunity back from `Qualified` or `Appointment` would corrupt stage-duration metrics — `architecture.md` §3 |
| — | `inquiry_count` is **initialised to 1 on the first inquiry, after `Create Opportunity`**, so a failure there can never block opportunity creation. This protects contacts created from P07 onward only — **pre-P07 contacts still have the field unset**, and the increment's behaviour on a null is undocumented and unobserved; see "Known risks" |
| — | **No downstream `inquiry.repeated` event.** GHL exposes no stable per-submission identity; reusing the opportunity-created key would make the ledger discard the re-inquiry as a redelivery, and a receive-time key would break retry dedup. Compensation stays in GHL and the event-grained backup is deferred — see [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) |

# Next 3 actions

1. **Build the reliability half — TC-09 through TC-12** (Issue #10). Retry with
   backoff, retry exhaustion into a terminal failed state, and `needs_human`
   routing. The `Ledger: Fail` branch and the `needs_human` tab already exist as
   the landing places; nothing drives them yet. This is the largest gap between
   what the demo claims and what it proves.
2. **Re-run TC-02b against v12, and exercise the duplicate-opportunity guard for
   real.** The GHL workflow changed underneath TC-02b's pass — `Allow Re-entry`
   went on and the `Find Opportunity` split was added — so that pass covers v9
   only. With re-entry on, a fast double submission can finally reach
   `Create Opportunity` twice for one contact, which is the first test that would
   actually exercise the guard. Until it runs, the guard is configured and
   unproven, and the docs say exactly that.
3. **Build the reconciliation sweep (TC-17).** Six opportunities with no
   `leads_backup` row sit in the location as ready-made test data — enumerated
   in "Known risks". ADR-002 makes
   this backstop more load-bearing than originally planned, since the
   opportunity-side race mitigation does not exist. Note the sweep as designed
   will **not** recover a suppressed re-inquiry — see "Known risks".

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

**What it cannot yet demonstrate** is the half the design says is the point:
retry, retry exhaustion, human-review routing, and reconciliation. Every
reliability claim in `architecture.md` §7 beyond validation is still design,
not evidence — and six opportunities with no backup row are sitting in the CRM
as proof that the reconciliation sweep is missing. P07 added a **second kind**
of gap on top of those six, and the sweep cannot even see this one: a
re-inquiry writes no backup row *and* creates no opportunity, so there is
nothing for an opportunity-keyed sweep to find. Documented rather than hidden.

All evidence is sequential. Nothing here says anything about concurrency.
