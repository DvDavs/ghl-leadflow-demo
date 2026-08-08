# Architecture

How the lead pipeline is put together, what each part is responsible for, and
where it is designed to fail safely.

> **Nothing here is built.** This document describes an intended design. No
> GoHighLevel, n8n, or Google resource exists yet. Where a claim rests on an
> unverified assumption, it is marked **[ASSUMPTION]**.

Throughout, **[DEMO]** marks what ships in the two-day sprint and **[LATER]**
marks what a real deployment would additionally need. The split is deliberate:
a demo that quietly pretends to be production is worse than one that states its
limits.

---

## 1. The organising principle

One sentence generates most of the decisions in this document:

> **GoHighLevel owns business state. n8n owns integration state.**

The CRM is a board a salesperson works. Every stage on it costs a human a
mental slot and distorts stage-duration metrics if it does not represent real
forward progress. Retries, webhook redeliveries, and backoff are facts about
our plumbing, not facts about the lead — so they never appear there.

Section 3 applies this rule case by case. It is the most consequential judgment
in the design.

## 2. Components and responsibilities

Each component owns exactly one thing. Where a responsibility could plausibly
sit in two places, the table names where it does **not** sit, because that
boundary is what keeps the design from drifting into two competing CRMs.

| Component | Owns | Does **not** own |
|---|---|---|
| Facebook Lead Ads / landing page / web form | **Capture** — producing a raw submission event | Identity, validation, state |
| GHL Contact | The **person** record | Event identity — a contact is not a lead event |
| GHL Opportunity | The **deal** — one inquiry that can be won or lost | Person attributes, integration mechanics |
| GHL Pipeline stage | **Business state** — where the deal sits in the human sales process | Integration state |
| GHL Workflow | **Speed-to-lead outreach**, and emitting the outbound webhook | Routing decisions requiring enrichment |
| GHL Calendar | **Scheduling** — system of record for appointments | Qualification |
| Public tunnel | **Ingress** — the only inbound surface we operate | Anything semantic |
| n8n | **Orchestration** — validate, normalize, dedup, route, retry, log | Business truth |
| Dedup ledger | **Event identity** — has this `externalLeadId` been processed | Person identity |
| AI enrichment | **Summarize, extract, classify**, with a confidence score | Any approve or reject decision — see [DECISION-001](decisions/DECISION-001-ai-boundaries.md) |
| Sheets `leads_backup` | **Durable append-only backup**, event-grained | Being read back into GHL as truth |
| Sheets `run_log` | **Observability** | Correctness |
| Sheets `needs_human` | **Human work queue** | Resolving anything itself |
| Notification channel | Getting a human's attention **once** | Durability — it is best-effort |

## 3. Lifecycle model: stages, flags, and things the CRM must never see

### The rule

> **Changes what a human does next → STAGE.**
> **Changes what the system does next → FLAG on the record.**
> **Only describes how the plumbing behaved → never reaches the CRM at all.**

### Pipeline stages

```
New Lead → Contacting → Contacted → Qualified → Appointment → Follow-up → Closed
```

**Won and Lost are not stages.** A GHL Opportunity carries a native `status`
(`open` / `won` / `lost` / `abandoned`). Using status keeps the board showing
only live work while preserving win-rate reporting. Two terminal stages would
split one concept across two mechanisms.

**Follow-up is a genuine stage**, because a rep works `Contacting` daily and
`Follow-up` weekly, with different messaging. The rule passes.

### The exceptional conditions

| Condition | Representation | Lives in | Why |
|---|---|---|---|
| **No Response** | Flag: tag `no-response`, fields `contact_attempts`, `last_attempt_at` | GHL, record stays in `Contacting` | Reversible, and the human keeps doing the same thing. As a stage, a lead answering on day 4 must be dragged *backwards* — which corrupts stage-duration metrics and trains reps to distrust the board. After N attempts a workflow moves it to `Follow-up`, and *that* is a real stage change because the cadence genuinely changes. |
| **Duplicate event** (same `externalLeadId` twice) | **Nothing. Zero CRM artifacts.** One `run_log` row, `outcome=duplicate_event` | Integration layer only | A webhook retry is our plumbing, not a business fact. If redelivery produced a note or a tag, the CRM would become a record of our infrastructure's flakiness. A rep must not be able to tell from the CRM that a webhook was retried. |
| **Duplicate person** (real re-inquiry) | Business-meaningful. Reuse the Contact. Open opportunity exists → append a note, tag `repeat-inquiry`, pull back to `Contacting` if it had drifted. No open opportunity → create a new one | GHL | A returning lead is a hot buying signal. Suppressing it is the worst failure this system can produce. Still not a stage: it describes *how the deal arrived*, not where it is. |
| **Requires Human** | Flag + queue: tag `needs-human`, field `human_review_reason`, assigned owner, `needs_human` row, one notification. **While set, automation must not advance the stage** | GHL flag + Sheets queue | Orthogonal to position — it can fire at qualification, at pricing, or at document review. As a stage it would *erase where the lead actually was*. As a flag it is a filterable list, and it composes with the AI boundary. |
| **Error** | Integration layer by default. **One exception:** failure *after* a partial GHL write tags `integration-error` + `needs-human` | n8n / Sheets, rarely GHL | If we failed before touching GHL there is nothing in GHL to mark, and a "failed lead" record would be a ghost a rep cannot act on. But if the CRM is now *itself* inconsistent, the CRM is the broken thing and a human must see it there. That asymmetry is the whole judgment. |
| **Retry** | **Never in the CRM, under any condition.** Only `attempt: n` in the log | Integration layer only | Retry is a mechanism, not a state of the lead. The lead does not know it is being retried, and neither should the salesperson. |

Diagram: [`diagrams/lead-lifecycle.md`](diagrams/lead-lifecycle.md).

## 4. Boundary contracts

| Boundary | Trigger | Data crossing | Receiver guarantees |
|---|---|---|---|
| Sources → GHL | User submits | Name, email, phone, service interest, source event id if any | GHL persists a Contact and creates an Opportunity. **This happens before n8n sees anything** — see §6.0 |
| GHL Workflow → n8n | Opportunity created in `New Lead` | `externalLeadId`, `contactId`, `opportunityId`, contact fields, `source`, `submittedAt`, `locationId` | n8n validates the secret and required fields **synchronously**, rejecting with 401 or 422; otherwise acks 200 and continues asynchronously. At-least-once assumed **[ASSUMPTION]** |
| n8n → dedup ledger | Every accepted delivery | `externalLeadId`, state, timestamps | Returns hit or miss. **Not atomic** — see §6.3 |
| n8n → GHL | After dedup passes | Opportunity update, custom fields, tags, notes, stage moves | Mutations to records GHL already created. n8n creates a Contact itself only on the direct-ingress variant in §6.0 |
| n8n → AI | After GHL persist | Free text plus form fields | Structured JSON with a confidence score. Bounded timeout, **no side effects** |
| n8n → `leads_backup` | After GHL persist | Normalized event plus raw payload | At-least-once append; duplicate rows tolerated by design |
| n8n → `run_log` | Every stage boundary | Log event, §7 | Best-effort. A failed log write must never fail the lead |
| GHL Calendar → n8n | Appointment booked | `contactId`, `appointmentId`, start time | n8n advances the stage and logs |
| Reconciliation → GHL | Every 10 min | Query recent opportunities lacking `external_lead_id` | Recovers leads whose webhook was lost |

Diagram: [`diagrams/general-architecture.md`](diagrams/general-architecture.md).

## 5. Where state lives

- **System of record — person and deal:** GHL. The client works in the CRM, so anything the CRM does not know is invisible to the business.
- **System of record — person-level deduplication:** GHL. Its contact upsert is what stops one human becoming two contacts, and it runs at capture, before n8n exists in the story. **[ASSUMPTION]** — the matching semantics are unverified, see [`integration-options.md`](integration-options.md) §5.
- **System of record — event processed-ness:** the dedup ledger. GHL cannot own this, because it is a fact about *our deliveries*, not about the business.
- **System of record — appointments:** GHL Calendar.
- **Derived copy:** `leads_backup`. Append-only, never authoritative, never automatically read back into GHL.
- **Queue, not truth:** `needs_human` — authoritative only for what a human still owes an answer on.

One deliberate asymmetry: **Sheets is event-grained, GHL is person-grained.** One
person with three inquiries is 1 contact and N opportunities in GHL, but 3 rows
in backup. That is correct, not a defect.

## 6. Identity and idempotency

Full reasoning in [ADR-002](decisions/ADR-002-idempotency-strategy.md). Summary:

### 6.0 Where the ledger actually sits — and what it cannot do

This is the most easily overstated part of the design, so it is stated plainly.

**On the GHL-native ingress path** — a GHL form or a Facebook Lead Ads
connection — **GHL creates the Contact and the Opportunity before n8n receives
anything.** The webhook payload already carries `contactId` and `opportunityId`,
which is proof that those records exist by the time we get a vote. The ledger is
therefore downstream of the CRM write, and **it cannot prevent the CRM record
that triggered it.**

What each layer actually protects, on that path:

| Duplicate of… | Prevented by | Not prevented by |
|---|---|---|
| **A person** — same human, two submissions | GHL's contact upsert **[ASSUMPTION]** | The ledger — it never sees the first write |
| **A delivery** — one event, webhook sent twice | **The ledger** — zero downstream work on the second | — |
| **An opportunity** — one event, two opportunities | The pre-create query on `external_lead_id` **[ASSUMPTION]** | The ledger alone |

So the ledger's real job on this path is preventing **duplicate processing**: a
second backup row, a second AI call, a second notification, a second stage
mutation. That is genuinely worth having — it is what stops one lead becoming
three sheet rows and two pages to a salesperson — but it is a smaller claim than
"the ledger prevents duplicate CRM records", and the smaller claim is the true
one.

**On the direct-ingress variant** — a landing page *we* control, posting to the
n8n webhook first — the ordering inverts: n8n dedups, then writes to GHL, and
the ledger genuinely does gate the CRM write. This is the stronger design, and
it is available for exactly the one source whose form we own. It is **not**
available for GHL-hosted forms or a native Facebook connection, because those
write to the CRM by construction.

The demo uses the GHL-native path, because that is the realistic integration
shape for this client. The direct-ingress variant is documented so the tradeoff
is a decision rather than an accident.

### 6.1 The identity chain

`externalLeadId` exists **before** the CRM. `contactId` exists **only after**
GHL confirms persistence. Never key a retry on `contactId`, because the retry
may be of the very request that would have produced it.

`externalLeadId` identifies **one submission event** — not a person, and not a
delivery. Format `{source}:{sourceEventId}`, with a derived fallback when the
source supplies nothing.

### 6.2 Two different problems that look alike

- **Duplicate event** — an infrastructure artifact that must be *erased*.
- **Duplicate person** — a business signal that must be *amplified*.

Collapsing these into one "duplicate" concept is the classic mistake. It either
spams the CRM with retries or silently swallows real re-inquiries.

### 6.3 The race window, stated honestly

The ledger is a check-then-write, not a transaction. Two truly concurrent
identical events can both miss. With a Sheets-backed ledger the window is
roughly **one to two seconds**; a database-backed ledger shrinks it to tens of
milliseconds but still does not make it atomic.

Two things are *intended* to bound the damage, and **both rest on unverified
capabilities** — see [ADR-002](decisions/ADR-002-idempotency-strategy.md):

- A **second independent check** at the GHL layer — query opportunities by the
  `external_lead_id` field before creating one. **[ASSUMPTION]** — searching by
  a custom-field value is unconfirmed.
- GHL's contact upsert is expected to deduplicate on email and/or phone, which
  would make a duplicate *contact* impossible and leave only a duplicate
  *opportunity* exposed. **[ASSUMPTION]** — matching semantics and behaviour
  under concurrent calls are undocumented.

Verify both as soon as a token exists. Until then: one real check, and two
hoped-for ones.

**[LATER]** A real atomic claim: a unique index with insert-or-ignore, or a
queue partitioned by `externalLeadId` so identical keys serialize by
construction.

## 7. Reliability

Full failure enumeration in [`diagrams/reliability.md`](diagrams/reliability.md).

### Ordering principle

Operations are ordered so the business-critical write lands first and every
later step is purely additive:

```
GHL contact → GHL opportunity → ledger claimed → routing → ledger completed → backup → AI → notification
```

Routing precedes AI deliberately: routing reads the form's own `service` field,
and uses AI only as a fallback hint when that field is absent or unrecognized.
A pipeline whose routing depends on a model is a pipeline that misroutes when
the model is down.

A crash at any point leaves the lead **contactable**, which is the only
invariant that truly matters.

### Retry policy, by failure class

| Failure | Retry | Why |
|---|---|---|
| Invalid payload | **Never** | Retrying invalid data never helps. Route to human review. |
| Unauthorized request | **Never** | Reject, log, create no CRM artifact. |
| Auth failure (401) | **Never** | Backoff cannot fix authorization. Dead-letter and notify immediately. |
| Rate limited (429) | Exponential backoff with jitter, honour `Retry-After` | Safe: the ledger claim plus the pre-check make the create repeatable. |
| Server error or timeout (5xx) | Backoff with jitter, **in read-before-rewrite mode** | The write **may already have succeeded**. Re-query by `external_lead_id` before re-issuing. |
| Sheets append failure | Backoff, few attempts | Append is **not** idempotent. Deliberate choice: **at-least-once**. A duplicate backup row is harmless; a missing one is not. |
| AI failure or malformed output | At most one retry | No side effects. Then **degrade**: mark unknown, flag for human. The lead is created even if AI is entirely down. |

### Structured logging

One event per **delivery**, not per lead:

```json
{
  "ts": "2026-08-08T21:04:11.312Z",
  "correlationId": "c_01J8XQ2M5ZK",
  "externalLeadId": "fb:leadgen_1234567890",
  "source": "facebook",
  "step": "ghl_opportunity",
  "outcome": "processed",
  "attempt": 1,
  "durationMs": 412,
  "contactId": null,
  "opportunityId": null,
  "errorCode": null
}
```

The load-bearing distinction: **`correlationId` identifies this delivery;
`externalLeadId` identifies the business event.** Two deliveries of one event
share `externalLeadId` and differ in `correlationId` — which is exactly what
makes a duplicate legible in the log instead of invisible.

**[DEMO]** Logs land in n8n execution history and the `run_log` sheet, chosen
because it is screen-shareable during an interview. Honest limits: the log
write can itself fail, and a burst will throttle Sheets logging before it
throttles the CRM — the wrong failure order. **[LATER]** a real log sink.

### Reconciliation

A scheduled sweep every 10 minutes queries GHL for recent opportunities whose
`external_lead_id` is absent, and pushes them through the normal path. This
recovers leads whose webhook was lost entirely — the failure no amount of
retry logic catches, because nothing ever arrived. It is the highest-value
reliability feature in the build, and we estimate it is achievable within the
sprint. It is covered by TC-17.

## 8. Trust boundaries

Public-internet exposed: the GHL form (GHL's surface), and **the n8n webhook
URL** — the only ingress we operate. Everything else is outbound-only.

**[DEMO]** controls: a long unguessable webhook path plus a shared secret in
the payload. Note the constraint driving this: GHL's free outbound webhook
action sends **no signature**, so cryptographic verification is not available
at that layer (see [`integration-options.md`](integration-options.md)).

**[LATER]** HMAC verification via a Marketplace app, IP allowlisting, secret
rotation, least-privilege scopes, and a stable domain instead of a tunnel.

Credentials live in the n8n credential store, never in workflow JSON. Because
this repository is **public**, any exported workflow must have webhook paths,
location ids, and credential references stripped before commit. That is a
release gate, not a guideline.

## 9. Known limitations

Documented rather than faked:

1. **Not exactly-once.** Best-effort dedup with two independent checks and a bounded, quantified race window.
2. **Cannot detect the absence of leads.** A silently disconnected source needs volume baselining. This is the hardest failure in the class and we do not solve it.
3. **Single n8n instance.** No queue mode, no durable retry queue.
4. **Manual dead-letter replay only.** Automated replay with a UI is out of scope.
5. **No automated tests against live GHL.** The demo relies on replayed fixtures and manual runs.
6. **The Facebook leg is simulated** unless a live page and ad account are available — and it will be labelled as simulated. A faked integration is the fastest way to lose credibility in an interview.
7. **Untested under burst.** Rate-limit behaviour is unobserved.
8. **Raw payloads in a spreadsheet is not a defensible privacy posture.** Retention, redaction, and access control are all [LATER].
9. **GHL webhook retry semantics are unverified** **[ASSUMPTION]**. The at-least-once model and the practical race window both rest on this.

## Related

- [ADR-001](decisions/ADR-001-integration-hierarchy.md) — which integration layer, and why
- [ADR-002](decisions/ADR-002-idempotency-strategy.md) — identity and idempotency
- [DECISION-001](decisions/DECISION-001-ai-boundaries.md) — AI decision boundaries
- [`integration-options.md`](integration-options.md) — what GHL and n8n actually support
- [`../TEST_CASES.md`](../TEST_CASES.md) — how these claims get verified
