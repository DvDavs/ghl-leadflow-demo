# GHL Leadflow Demo

A design-first lead pipeline connecting a lead source, a **GoHighLevel** CRM
location, an **n8n** automation layer, and a **Google Sheets** backup.

> ## Status: all P0 work complete — golden path live, reliability evidenced, reconciliation running, demo rehearsed
>
> The GHL → n8n → Sheets flow runs end to end against live GoHighLevel and n8n
> Cloud resources. A downstream failure retries on a bounded ladder and
> converges on one record, or reaches a logged terminal state with a human
> handoff. **A webhook that never arrives is recovered too**: a reconciliation
> sweep runs on a schedule against a read-only GHL credential, and TC-17 passes
> against it — recovery, idempotence and log accuracy.
>
> **Every P0 issue is closed.** The interview demo was rehearsed twice
> unassisted, and its offline fallback exists: five sanitized captures plus a
> captioned walkthrough video in [`assets/demo/`](assets/demo/), with the script
> and per-system fallbacks in [`docs/demo/runbook.md`](docs/demo/runbook.md).
> What remains is P1 and unstarted.
>
> Scenario coverage is not summarized here on purpose, because a number in a
> banner goes stale. **[`TEST_CASES.md`](TEST_CASES.md) is the status matrix and
> [`PROJECT_STATE.md`](PROJECT_STATE.md) is the current state** — those two are
> the source of truth, including for what is still open.

---

## The business problem

A home-services business buys leads from Facebook ads and a landing page. Each
lead is worth real money, and the value decays by the hour — the business that
calls first usually wins the job.

Four things go wrong in practice, and none of them are exotic:

- **Leads arrive twice.** An ad platform retries a webhook, a customer submits
  the form again, a workflow fires on a duplicate event. The CRM fills with
  double records, two salespeople call the same person, and the pipeline numbers
  stop meaning anything.
- **Leads arrive broken.** A required field is missing, or a service type
  arrives that nobody planned for. The naive handling is to drop it, which is
  indistinguishable from never receiving it.
- **Downstream systems fail temporarily.** A backup sheet or an endpoint returns
  a 5xx for thirty seconds. Without retry the lead is lost; with careless retry
  it is duplicated.
- **Nobody can tell what happened.** When a lead goes missing there is no
  correlation id, no log, and no way to answer "did we receive it at all?"

A demo that only shows the happy path proves none of this was handled.

## What this demo shows

A pipeline that stays correct when the inputs misbehave:

- **Duplicate deliveries produce no second record.** On the demo's GHL-native
  path, GHL creates the Contact and Opportunity *before* n8n sees anything, so
  identity cannot be decided before that first write. The dedup ledger instead
  keys each delivery on `ghl:opportunity-created:<opportunityId>`, derived
  after the CRM write — verified by TC-02. `externalLeadId` is reserved for a
  future direct-ingress source where n8n would gate the CRM write itself.
- **Invalid input is rejected loudly**, before any business write, with the
  specific failing field named — verified by TC-09.
- **Transient failures retry** and still converge on one downstream record;
  exhausted retries reach a terminal, visible state rather than vanishing —
  verified by TC-10, TC-11, TC-12.
- **Every lead carries a correlation id** through every hop, so its path is
  reconstructable from logs.
- **Uncertain cases reach a human** instead of being guessed at — designed,
  blocked on the same missing prerequisites as TC-15/TC-16.

## The golden path

The first end-to-end path is deliberately narrow — **one service type**:

```
Lead source  →  GoHighLevel contact  →  Opportunity in pipeline
             →  Workflow  →  Outbound webhook  →  n8n
             →  Validate → check idempotency → enrich
             →  Google Sheets backup  +  notification
```

| Hop | State |
|---|---|
| Lead source → GHL Contact → Opportunity → Pipeline | **Live** (P05/P07) |
| GHL Workflow → outbound webhook | **Live** — `Form to Opportunity`; deployed version in [`PROJECT_STATE.md`](PROJECT_STATE.md) |
| n8n ingress: validate → dedup → backup | **Live**, evidenced by TC-01, TC-02, TC-09, TC-18, TC-19 |
| Downstream failure → retry → terminal handoff | **Live**, evidenced by TC-10, TC-11, TC-12 |
| Missing webhook → scheduled reconciliation sweep | **Live and active**, evidenced by TC-17 |
| AI enrichment | **Designed**, not built |

Four-service routing, appointment booking, and AI enrichment are designed for
and diagrammed, but they are **not** in the first path. They are added only once
the single-service path survives its duplicate and failure test cases. Widening
scope before that point produces four broken paths instead of one working one.

## Reliability principles

These are the rules the design is held to, and each one is testable:

1. **Idempotency before convenience.** A write that cannot be safely repeated
   does not ship. Identity is established at the boundary, not inferred later.
2. **Fail loudly, never silently.** A rejected lead is a logged event with a
   reason. Silence is the one unacceptable outcome.
3. **Retries must converge.** Retry is only safe where the operation is
   idempotent. Where it is not, that is stated rather than hoped over.
4. **Correlation over guesswork.** One id, propagated end to end.
5. **Terminal states are explicit.** "Failed after N attempts" is a state the
   system reaches on purpose, with a backup record and a human owner.
6. **The CRM pipeline models the business, not the plumbing.** Retry and error
   handling belong to the integration layer; they never become fake pipeline
   stages a salesperson has to look at.
7. **Untested is not "working".** Every reliability claim above is *intended* to
   map to a row in [`TEST_CASES.md`](TEST_CASES.md), and no row is marked
   passing without evidence. Coverage is not yet complete — where a claim has no
   test, that is a gap to close, not a claim to trust.

## AI boundaries

AI may **summarize, extract, classify, and suggest**. Its output is always
advisory, attributed, and stored alongside the raw input.

AI may **not approve or reject financial requests**, assign a score that gates a
financial outcome, or silently discard a lead. Uncertain cases route to a human.

This is a compliance boundary, not a technical preference. The full reasoning and
the test that resolves ambiguous cases are in
[DECISION-001](docs/decisions/DECISION-001-ai-boundaries.md).

## Data

**All data in this repository is fictional.** No real customer, contact, phone
number, email address, or business record appears anywhere, in documentation,
diagrams, fixtures, or test data. The demo runs against a test location with
invented leads.

No credentials are stored here. [`.env.example`](.env.example) lists variable
*names* only; real values belong in a local `.env`, which is gitignored.

## How to navigate this repository

**Start here:**

| Document | What it answers |
|---|---|
| [`PROJECT_STATE.md`](PROJECT_STATE.md) | What is actually done, blocked, and next |
| [`TEST_CASES.md`](TEST_CASES.md) | What "working" means, defined before the code, and which rows pass |
| [`docs/INDEX.md`](docs/INDEX.md) | The reading route to everything else, including test evidence and milestone history |

**Design:**

| Document | What it answers |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Components, boundaries, who owns what |
| [`docs/diagrams/general-architecture.md`](docs/diagrams/general-architecture.md) | How data moves between systems |
| [`docs/diagrams/lead-lifecycle.md`](docs/diagrams/lead-lifecycle.md) | The states a lead passes through |
| [`docs/diagrams/reliability.md`](docs/diagrams/reliability.md) | Where failures happen and who handles them |

**Decisions:**

| Document | What it answers |
|---|---|
| [ADR-001](docs/decisions/ADR-001-integration-hierarchy.md) | Which integration layer, and why |
| [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) | How duplicates are prevented |
| [DECISION-001](docs/decisions/DECISION-001-ai-boundaries.md) | What AI may and may not decide |

**Research and environment:**

| Document | What it answers |
|---|---|
| [`docs/integration-options.md`](docs/integration-options.md) | What GHL and n8n actually support, with sources |
| [`docs/environment.md`](docs/environment.md) | What the build machine can do, and how that was verified |

Diagrams are Mermaid and render directly on GitHub.

## Running this

The golden path runs live: n8n Cloud hosts the production webhook, and GHL's
`Form to Opportunity` workflow fires it on every new Opportunity. To
exercise it without a live form submission,
[`scripts/replay-webhook.ps1`](scripts/replay-webhook.ps1) replays a fixture
payload against the same webhook, and the manual-trigger test harness in
[`docs/n8n/testing.md`](docs/n8n/testing.md) covers each scenario end to end.
The reconciliation sweep runs on its own schedule and can also be triggered
manually; [`docs/n8n/operations.md`](docs/n8n/operations.md) §5 describes it.

## Reading the claims in this repository

Language is used precisely and deliberately throughout:

- **"Verified"** — a command was executed and its output observed.
- **"Configured"** — settings exist, but nothing exercised them.
- **"Not detected"** — not found in the locations inspected. Never "does not exist".
- **"Designed"** — decided and written down. **Not built, and not tested.**

The golden path, its retry and terminal-handoff behaviour, and the
reconciliation sweep are **verified** — each against a row in
[`TEST_CASES.md`](TEST_CASES.md) that names the artifact version it ran on.
Four-service routing, appointment booking and AI enrichment remain
**designed**. [`PROJECT_STATE.md`](PROJECT_STATE.md) carries the full list of
open risks and blockers, including the ones a passing matrix hides.
