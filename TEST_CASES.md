# Test Cases

Behavioural test matrix for the GHL leadflow demo.

**One scenario has passed: TC-02b (P05)**, with live evidence in its `Actual`
column. The GoHighLevel leg — form → Contact → Opportunity → pipeline — exists
and is proven. The Google Sheet exists with its three tabs, but no automation
writes to it yet, and no n8n webhook is deployed, so every scenario needing
P-N8N is still blocked. This file was written before the implementation so the
acceptance criteria cannot drift to match whatever happens to work.

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

Scenarios are blocked on whichever of these does not yet exist:

- **P-GHL** — a GoHighLevel test location with a pipeline, custom fields, and a lead-capture form. **Satisfied (P05)** — see [`PROJECT_STATE.md`](PROJECT_STATE.md).
- **P-N8N** — a reachable n8n instance with the inbound webhook deployed. **Not satisfied** — n8n Cloud is provisioned, no webhook workflow is published.
- **P-SHEET** — a Google Sheet configured as the backup destination. **Created** — `leads_backup`, `run_log`, and `needs_human` tabs exist with their headers; nothing writes to them yet.
- **P-CAL** — a GoHighLevel calendar configured for appointment booking. **Not satisfied.**

## Golden path scope

The first golden path is a **single service type**. Deliberately deferred until
that path is stable end to end:

- **TC-04 through TC-07** — four-service routing
- **TC-13 and TC-14** — appointments
- **TC-15 and TC-16** — AI enrichment

They are written now so the design accounts for them, not because they are next.
The reliability scenarios (**TC-09 through TC-12**, plus **TC-17** and
**TC-18**) are **not** deferred — they are the point of the demo.

---

## Matrix

| ID | Scenario | Input | Expected | Actual | Status |
|---|---|---|---|---|---|
| TC-01 | New lead, happy path | Form submission with all required fields, unseen `externalLeadId` | Contact created in GHL; opportunity created in pipeline at `New Lead`; row appended to backup sheet; a `run_log` row per stage boundary, all sharing one `correlationId`, terminating in `outcome=processed` | **GHL leg proven (P05):** form submission → Contact → Opportunity in `New Lead` confirmed live, see TC-02b Actual. Backup-sheet row and `run_log` boundary still require n8n/Sheets — not built yet | BLOCKED (P-N8N, P-SHEET) |
| TC-02 | Duplicate **delivery** — webhook redelivered | The exact TC-01 webhook payload delivered a second time — same `opportunityId`, therefore the same delivery identity `ghl:opportunity-created:<opportunityId>` per ADR-002. `externalLeadId` is deliberately **not** the key here: it identifies the original submission event and nothing populates it on this path | No second sheet row; no second notification; no second AI call; no further GHL mutation; responds 200 as already-processed, not as an error; one `run_log` row with `outcome=duplicate_event` | | BLOCKED (P-GHL, P-N8N, P-SHEET) |
| TC-02b | Duplicate **form submission** — same person submits twice | The TC-01 form submitted twice in quick succession, ~1 minute apart (instructed as 5 seconds; actual observed gap) | One contact, by GHL's own upsert. A second Opportunity is expected to be blocked by GHL's native duplicate-opportunity guard (P0, P05: location setting `allowDuplicateOpportunity: false` + the `Create Opportunity` action's own toggle) — **not** by the `external_lead_id` pre-create check, which remains confirmed unbuildable and is not under test here. Sequential only; not evidence of concurrent-safety. See `docs/decisions/ADR-002-idempotency-strategy.md` "Consequences to watch" | Two sequential submissions of the fixture (David Demo, david.demo@example.com, +1 202-555-0101, Mortgage) via the live published form. Live MCP verification: exactly one Contact (upserted by GHL, matched on email+phone, not duplicated); exactly one Opportunity, `status=open`, pipeline `LeadFlow Demo Pipeline` / stage `New Lead`, `source="GHL Demo Form"`, `monetaryValue=0`, name correctly resolved to `David Demo - Mortgage`, `internalSource.source=WORKFLOW_NEW` confirming automated creation. Contact's `service_interest`/`lead_message` custom fields populated on the correct P0 field objects. First pass surfaced and required fixing three build defects (email field not mapped to the standard attribute, form auto-created two duplicate custom fields instead of reusing the P0 set, Opportunity name left as unresolved literal placeholder text) — the broken interim contact/opportunity and the orphaned duplicate fields were deleted before this final run. Confirms the P0 guard holds for a quick sequential repeat of the identical fixture. Sequential only, ~1 minute apart — not evidence of concurrent-safety, and does not exercise the re-inquiry branch (TC-03) | PASS |
| TC-03 | Duplicate person, different event | New `externalLeadId`, but email and phone match an existing contact | Contact is reused, not duplicated; a new opportunity is created or the existing one is flagged; the lead is marked as a suspected duplicate for human review rather than silently merged. **P0 gap (P05):** while the P0 duplicate-opportunity guard is in effect and an opportunity is already open for the contact, the "new opportunity is created" arm is currently foreclosed — the compensating branch (note + `inquiry_count` + `repeat-inquiry` tag) is not built yet. Not executed in P05; still blocked | | BLOCKED (P-GHL, P-N8N) |
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
| TC-16 | Human review — financial boundary | Lead containing an explicit financing request | The AI may summarize and extract, and must not approve or reject; the lead is routed to a human with the extracted summary attached; no AI-written value appears in any stage or approval field | | BLOCKED (P-GHL, P-N8N) |
| TC-17 | **Reconciliation recovers a lost webhook** | An opportunity created in GHL whose outbound webhook never reached n8n | The scheduled sweep detects the opportunity has no `external_lead_id` record, processes it through the normal path, and produces exactly the TC-01 end state — one backup row, not two | | BLOCKED (P-GHL, P-N8N, P-SHEET) |
| TC-18 | Unauthorized webhook rejected | Request to the webhook URL with a missing or wrong shared secret | Rejected with 401 synchronously; **zero CRM artifacts**; zero backup rows; one `run_log` row recording the rejection; the rejection is distinguishable in logs from a validation failure | | BLOCKED (P-N8N) |

---

## Evidence policy

When a scenario is executed, the `Actual` column records what was observed —
the created record identifiers, the log correlation id, and the screenshot or
export used as proof. Scenarios move to `PASS` only with that evidence
attached. Test data is fictional throughout; no real person's contact details
are used at any point.
