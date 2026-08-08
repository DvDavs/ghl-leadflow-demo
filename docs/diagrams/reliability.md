# Diagram — Reliability

Where the pipeline fails, what happens next, and which system owns each
function. Subgraphs are ownership boundaries.

```mermaid
flowchart TB
  subgraph S1["Capture and raw event"]
    A1["Lead submitted"]
    A2{"externalLeadId present"}
    A3["Derive id from email, phone, form and submittedAt"]
  end

  subgraph S2["GoHighLevel - owns business state"]
    B1["Contact upserted"]
    B2["Opportunity created in New Lead"]
    B3["GHL Workflow fires outbound webhook"]
  end

  subgraph S3["n8n - owns integration state"]
    C1["Webhook received - verify secret and payload, then ack 200"]
    C2{"Shared secret valid"}
    C3{"Payload contactable"}
    C4{"Ledger says already completed"}
    C5["Claim event in ledger"]
    C6["Write back to GHL - read before rewrite"]
    C7["Retry with exponential backoff and jitter"]
    C8["Mark event completed in ledger"]
    C9["Reconciliation sweep every 10 minutes"]
  end

  subgraph S4["Downstream - owns durability and humans"]
    D1["Sheets leads_backup"]
    D2["Sheets run_log - structured events"]
    D3["Sheets needs_human"]
    D4["Sheets dead_letter"]
    D5["Notification to lead owner"]
    D6["AI enrichment - advisory only"]
  end

  A1 --> A2
  A2 -->|"no"| A3
  A2 -->|"yes"| B1
  A3 --> B1
  B1 --> B2
  B2 --> B3
  B3 --> C1
  C1 --> C2
  C2 -->|"no - reject 401"| D2
  C2 -->|"yes"| C3
  C3 -->|"no - unreachable lead"| D3
  C3 -->|"yes"| C4
  C4 -->|"yes - zero GHL calls"| D2
  C4 -->|"no"| C5
  C5 --> C6
  C6 -->|"429 or 5xx - may have succeeded"| C7
  C7 --> C6
  C7 -->|"budget exhausted"| D4
  C6 -->|"401 or permanent 4xx"| D4
  C6 -->|"success"| C8
  C8 --> D1
  C8 --> D6
  C8 --> D5
  D6 -->|"low confidence or financial judgment"| D3
  D4 --> D5
  C9 -->|"recover lost webhooks"| C4

  C1 -.-> D2
  C4 -.-> D2
  C6 -.-> D2
  C8 -.-> D2
```

## Ownership

Note on the first subgraph: it is labelled *Capture and raw event*, not
*Source*, because the id-derivation step (`A2`/`A3`) is **n8n's work** drawn at
its logical position in the flow rather than inside its owning system. The
source never owns identity — see the table below.

| Function | Owner | Why not elsewhere |
|---|---|---|
| **Capture** | Source | The only system that sees the submission |
| **Event identity** | Integration layer | A fact about our deliveries, not about the business, so the CRM cannot own it |
| **Person identity** | GoHighLevel | Its contact upsert is what stops one human becoming two contacts **[ASSUMPTION]** — matching semantics unverified |
| **Business state** | GoHighLevel | It is what the salesperson works |
| **Validation** | n8n | Rejecting at the boundary keeps malformed data out of the CRM entirely |
| **Retry and backoff** | n8n | A mechanism, never a CRM-visible fact |
| **Durability** | Sheets backup | Append-only and independent of the CRM, so it survives a CRM misconfiguration |
| **Observability** | `run_log` | Separate from backup on purpose: different trust level, different lifetime |
| **Human decisions** | A named person | A queue with no owner is a graveyard |

## Failure classes and what happens

| Failure | Retry | Safe to retry | Terminal behaviour |
|---|---|---|---|
| Bad or missing shared secret | **Never** | n/a | Reject, log, **no CRM artifact** |
| Payload has no email and no phone | **Never** | n/a | Human review. A lead nobody can contact is a human problem, not a technical one |
| GHL 401 — token expired or revoked | **Never** | n/a | Dead-letter plus immediate notification. Backoff cannot fix authorization |
| GHL 429 — rate limited | Backoff with jitter, honour `Retry-After` | **Yes** — ledger claim plus pre-check make the create repeatable | Dead-letter after budget |
| GHL 5xx or timeout | Backoff with jitter | **Only in read-before-rewrite mode** — the write may already have succeeded | Dead-letter after budget |
| Sheets append fails | Backoff, few attempts | Append is **not** idempotent | **At-least-once by choice.** A duplicate backup row is harmless; a missing one is not |
| AI timeout or malformed output | At most one | Yes — no side effects | **Degrade**: mark unknown, flag for human. The lead is created even if AI is entirely down |
| Notification fails | One | Yes | Log and continue. The Sheets queue is the durable artifact; the ping is best-effort |
| n8n crashes mid-flow | Recovered by the sweep | Read-before-rewrite | `integration-error` plus `needs-human` — the one CRM-visible error case |
| **Webhook never arrives at all** | n/a | n/a | **Reconciliation sweep.** No retry logic catches this, because nothing arrived to retry |

## Three decisions worth defending

**The ledger is claimed before the CRM write, not after.** Writing it after
means a crash in between produces a duplicate. Writing it before means a GHL
failure permanently suppresses the retry — a lost lead, which is worse. So the
claim is two-phase: `claimed` before, `completed` after. A redelivery seeing a
*stale* `claimed` proceeds, but in read-before-rewrite mode.

**Retry safety is a property of the operation, not a global setting.** Backoff
is applied where the operation is repeatable and withheld where it is not.
Blanket retry on a non-idempotent append is how one lead becomes six rows.

**The backup path accepts duplicates and refuses loss.** The two failure modes
are not symmetric: a duplicate row is a nuisance a reader can dedupe by
`externalLeadId`; a missing row is unrecoverable. The design chooses the
recoverable failure on purpose.

## What this diagram does not solve

- **A source that silently stops sending.** Absence of events is the hardest
  failure in this class and needs volume baselining, which is out of scope.
- **True exactly-once.** See [ADR-002](../decisions/ADR-002-idempotency-strategy.md) §Race window.
- **Automated dead-letter replay.** Replay is manual in demo scope.

## Related

- [`../architecture.md`](../architecture.md) — reliability section
- [ADR-002](../decisions/ADR-002-idempotency-strategy.md) — why retry safety depends on identity
- [`../../TEST_CASES.md`](../../TEST_CASES.md) — TC-09 through TC-12
