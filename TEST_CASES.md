# Test Cases

Behavioural test matrix for the GHL leadflow demo.

**Nothing in this matrix has passed.** No GoHighLevel, n8n, or Google resource
exists yet, so no scenario is currently executable. This file is the contract
the implementation will be measured against, written before the implementation
so the acceptance criteria cannot drift to match whatever happens to work.

## Status vocabulary

| Status | Meaning |
|---|---|
| `BLOCKED` | Cannot be executed yet — a named prerequisite does not exist. |
| `NOT RUN` | Executable in principle, but not yet attempted. |
| `PASS` | Executed, and observed output matched Expected. Never set this from reasoning alone. |
| `FAIL` | Executed, and observed output did not match Expected. |

`Actual` stays empty until a scenario has genuinely been executed. An empty
`Actual` column with a `PASS` status is a defect in this document.

## Prerequisites

Every scenario below is blocked on at least one of these:

- **P-GHL** — a GoHighLevel test location with a pipeline, custom fields, and a lead-capture form.
- **P-N8N** — a reachable n8n instance with the inbound webhook deployed.
- **P-SHEET** — a Google Sheet configured as the backup destination.
- **P-CAL** — a GoHighLevel calendar configured for appointment booking.

## Golden path scope

The first golden path is a **single service type**. Scenarios TC-04 through
TC-07 (four-service routing) and TC-11 through TC-12 (appointments) are
deliberately deferred until the single-service path is stable end to end. They
are written now so the design accounts for them, not because they are next.

---

## Matrix

| ID | Scenario | Input | Expected | Actual | Status |
|---|---|---|---|---|---|
| TC-01 | New lead, happy path | Form submission with all required fields, unseen `externalLeadId` | Contact created in GHL; opportunity created in pipeline at `New Lead`; row appended to backup sheet; one structured log line with the correlation id | | BLOCKED (P-GHL, P-N8N, P-SHEET) |
| TC-02 | Duplicate event, same `externalLeadId` | The exact TC-01 payload delivered a second time | No second contact; no second opportunity; no second sheet row; request acknowledged as already-processed, not as an error | | BLOCKED (P-GHL, P-N8N, P-SHEET) |
| TC-03 | Duplicate person, different event | New `externalLeadId`, but email and phone match an existing contact | Contact is reused, not duplicated; a new opportunity is created or the existing one is flagged; the lead is marked as a suspected duplicate for human review rather than silently merged | | BLOCKED (P-GHL, P-N8N) |
| TC-04 | Service routing — service A | Valid lead, `service = A` | Opportunity lands in the pipeline path designated for A; assignment and notification match A's rule | | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable |
| TC-05 | Service routing — service B | Valid lead, `service = B` | Opportunity lands in the pipeline path designated for B | | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable |
| TC-06 | Service routing — service C | Valid lead, `service = C` | Opportunity lands in the pipeline path designated for C | | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable |
| TC-07 | Service routing — service D | Valid lead, `service = D` | Opportunity lands in the pipeline path designated for D | | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable |
| TC-08 | Unknown or missing service value | Valid lead, `service` absent or not in the known set | Lead is not dropped and not guessed into a service; it is routed to human review with the raw value preserved | | BLOCKED (P-GHL, P-N8N) |
| TC-09 | Required field absent | Payload missing a required field (e.g. no phone and no email) | Rejected at validation before any CRM write; nothing partially created; rejection logged with the correlation id and the specific failing field; the sender receives a deterministic non-retryable response | | BLOCKED (P-N8N) |
| TC-10 | Downstream webhook temporarily failing | Valid lead while the downstream endpoint returns 5xx | Failure detected and logged; the lead is queued for retry, not discarded; no partial duplicate is created by the failed attempt | | BLOCKED (P-N8N, P-SHEET) |
| TC-11 | Retry succeeds after transient failure | The TC-10 lead, with the downstream endpoint restored before retries are exhausted | Exactly one final downstream record, not one per attempt; the retry count is visible in the logs; final state is identical to the TC-01 outcome | | BLOCKED (P-N8N, P-SHEET) |
| TC-12 | Retry exhausted | Valid lead while the downstream endpoint fails past the retry budget | Lead moves to a terminal failed state, not silent loss; it appears in the backup path and is surfaced for human review; the failure is distinguishable in logs from a validation rejection | | BLOCKED (P-N8N, P-SHEET) |
| TC-13 | Appointment booked | Qualified lead books a slot on the connected calendar | Appointment is created; the opportunity advances to the appointment stage; the backup record reflects the appointment | | BLOCKED (P-GHL, P-CAL) — deferred until TC-01 is stable |
| TC-14 | Appointment no-show or cancellation | A booked appointment is cancelled | Opportunity does not remain stuck in the appointment stage; it returns to follow-up rather than being marked lost automatically | | BLOCKED (P-GHL, P-CAL) — deferred until TC-01 is stable |
| TC-15 | Human review — AI declines to classify | Lead whose free-text intent is ambiguous to the classifier | AI output is recorded as a suggestion only; the lead is flagged for human review; no financial approve/reject decision is taken by the AI | | BLOCKED (P-GHL, P-N8N) |
| TC-16 | Human review — financial boundary | Lead containing an explicit financing request | The AI may summarize and extract, and must not approve or reject; the lead is routed to a human with the extracted summary attached | | BLOCKED (P-GHL, P-N8N) |

---

## Evidence policy

When a scenario is executed, the `Actual` column records what was observed —
the created record identifiers, the log correlation id, and the screenshot or
export used as proof. Scenarios move to `PASS` only with that evidence
attached. Test data is fictional throughout; no real person's contact details
are used at any point.
