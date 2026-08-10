# GHL Leadflow — one page

A lead pipeline between a lead source, a **GoHighLevel** CRM location, an
**n8n** automation layer, and a **Google Sheets** backup. Built to survive
duplicates, missing fields and downstream failure — and to prove it did.

---

## The problem

A home-services business buys leads. Each one is worth real money and decays by
the hour; the business that calls first usually wins the job. Four things go
wrong in practice, and none are exotic:

- **Leads arrive twice** — a platform retries, a customer resubmits. The CRM
  fills with doubles and two salespeople call the same person.
- **Leads arrive broken** — a required field is missing. Dropping it is
  indistinguishable from never receiving it.
- **Downstream systems fail for thirty seconds** — without retry the lead is
  lost, with careless retry it is duplicated.
- **Nobody can tell what happened** — no correlation id, no log, no way to
  answer *"did we receive it at all?"*

A demo that only shows the happy path proves none of this was handled.

## The architecture

```
Public form  →  GHL Contact  →  Opportunity (New Lead)  →  GHL Workflow
             →  outbound webhook  →  n8n
             →  normalize → shared-secret check → ledger claim
             →  Google Sheets leads_backup  →  ledger completed  →  200

failure path      →  202 retry_scheduled  →  DB-persisted Wait  →  3 attempts
                                          →  one row, or failed + needs_human

missing webhook   →  scheduled sweep every 10 min  →  ledger says "never seen"
                                                    →  same write path
```

Three stores, three different jobs: **GHL** owns the person and the deal,
the **dedup ledger** owns whether *we* processed a delivery, and
**Sheets** is a derived, never-authoritative copy plus a `needs_human` queue.

## Decisions worth defending

| Decision | Why | Cost accepted |
|---|---|---|
| **Identity is derived after the CRM write**, keyed `ghl:opportunity-created:<opportunityId>` | On this path GHL creates the Contact and Opportunity *before* n8n sees anything, so identity cannot be decided earlier. The ledger keys on what actually exists | Not exactly-once. The race window is bounded and stated, not hidden |
| **The dedup question moved to our side of the boundary** | The CRM's opportunity search has no custom-field filter, so "which of these have I never seen?" is unanswerable by the vendor. Our own ledger can answer it | The sweep must hold its own state |
| **A re-inquiry amplifies rather than creates** — tag, counter, note on the existing opportunity | A second opportunity for an open deal is noise a salesperson has to clean up | An accidental double submission is treated as a real re-inquiry. The CRM exposes no submission id to tell them apart |
| **Retry is bounded and answers `202`, never `200`** | `200` on an unwritten record is a lie to the sender. 3 attempts, 70 s base, ×2, +0–20 % jitter, 300 s cap, held by a database-persisted wait | An execution that dies mid-wait is not re-driven — a deliberate trade for keeping one copy of the write node |
| **Exhaustion is a state, not a disappearance** | Terminal `failed` in the ledger *plus* a `needs_human` row with reason and owner | The ledger alone is not proof a human was told; judge the handoff on the `needs_human` row |
| **Reconciliation over more retry** | Retry cannot help when nothing arrived. This is the highest-value reliability feature in the build | The recovered row is thinner than the delivered one — no business name, raw stage id, differently formatted phone |
| **The pipeline models the business, not the plumbing** | Retry and error states never become pipeline stages a salesperson has to look at | Operational state lives only in the ledger and the logs |
| **Sheets writes are `RAW`, not `USER_ENTERED`** | A public form can post `=1+1`. Formula injection is stored as literal text | Re-picking the node in the UI can silently reset it — a standing release check |

Full reasoning: [ADR-001](../decisions/ADR-001-integration-hierarchy.md),
[ADR-002](../decisions/ADR-002-idempotency-strategy.md),
[DECISION-001](../decisions/DECISION-001-ai-boundaries.md), and the
[decision log](../decisions/decision-log.md).

## Evidence

Eleven scenarios pass, **and all eleven were observed against the artifact
versions currently deployed** — a row is demoted here when the artifact moves
under it, and two rows were demoted and re-run rather than argued for.

- **Golden path** — one Contact, one Opportunity, one backup row, one
  correlation id, end to end in about **17 seconds**. Run twice unassisted
  during rehearsal.
- **Duplicate delivery** — a redelivered webhook produces no second row.
- **Duplicate submission** — two submissions, one Contact, one Opportunity.
- **Genuine re-inquiry** — amplified, not swallowed; counter `1 → 2` and the
  opportunity returned along the branch that proves the loop closes.
- **Rejected input** — named failing field, before any business write.
- **Unauthorized webhook** — `401`, no business write.
- **Formula injection** — stored as literal text.
- **Retry** — `202`, database-persisted wait, converges on exactly one row.
- **Exhaustion** — terminal `failed` plus a `needs_human` handoff.
- **Reconciliation** — recovered six real orphaned opportunities on its first
  live run, left the healthy ones alone, and wrote nothing on the second run.

Per-scenario status, the version each pass covers, and the observed output:
[`TEST_CASES.md`](../../TEST_CASES.md) and [`docs/evidence/`](../evidence/).

## Risks and limitations

Stated, not hidden. Each one is tracked in
[`PROJECT_STATE.md`](../../PROJECT_STATE.md).

- **All evidence is effectively sequential.** The closest concurrency attempt
  missed by 4.3 s — measured twice — because the form's bot challenge
  serializes submissions. Duplicate-safe at four seconds is what is proven.
- **The duplicate-opportunity guard has never been exercised.** The window in
  which it could fire is under 1.5 s and the browser cannot reach inside it.
  Documented, not evidenced.
- **A re-inquiry writes no backup row**, creates no opportunity, and the sweep
  structurally cannot see it — it keys on opportunities without a backup row,
  and here there is no opportunity. Deliberately open; both shortcuts are worse.
- **One failure is fixed without being understood.** A sheet write was
  committing and then reporting failure. The write was made idempotent so it
  converges under the fault; the fault itself is still unexplained.
- **Not exactly-once, no queue mode, no automated dead-letter replay**, and raw
  payloads in a spreadsheet is not a defensible privacy posture at scale.
- **Not built:** four-service routing, appointment booking, AI enrichment.
  Designed and diagrammed only.

## Where to look

| | |
|---|---|
| Current state, open risks | [`PROJECT_STATE.md`](../../PROJECT_STATE.md) |
| Status matrix | [`TEST_CASES.md`](../../TEST_CASES.md) |
| Observed evidence | [`docs/evidence/`](../evidence/) |
| Architecture and boundaries | [`docs/architecture.md`](../architecture.md) |
| Decisions | [`docs/decisions/`](../decisions/) |
| Operating the pipeline | [`docs/n8n/operations.md`](../n8n/operations.md) |
| Demo script and fallbacks | [`runbook.md`](runbook.md) |

Repository: <https://github.com/DvDavs/ghl-leadflow-demo>

**All data is fictional.** No real customer, contact, phone number, email
address or business record appears anywhere in this repository, and no
credential is stored in it.
