# Test Cases

Behavioural test matrix for the GHL leadflow demo.

**Five scenarios pass against the currently deployed artifacts: TC-01, TC-02,
TC-03, TC-18 and TC-19**, each with live evidence in its `Actual` column.
**TC-02b passed too, but against a GHL workflow that no longer exists** — see
below. The golden path now runs end to
end — form → Contact → Opportunity → outbound webhook → n8n → Google Sheets —
and survives a redelivery, a bad secret, a formula-shaped lead name, and a
genuine second inquiry from a person who already has an open opportunity.

What remains blocked is the reliability half: retry and failure handling
(TC-09 through TC-12), reconciliation (TC-17), and everything deliberately
deferred.

**One already-passing row was demoted, not polished.** TC-02b's attribution was
wrong and its pass no longer covers the deployed GHL workflow — the artifact
changed underneath it. Both facts are recorded in place rather than rewritten,
because how a passing test can prove less than it claimed is worth more than a
clean matrix. **TC-02b needs re-running against v12** — it is next action 2 in
[`PROJECT_STATE.md`](PROJECT_STATE.md).

This file was written before the implementation so the acceptance criteria
cannot drift to match whatever happens to work. Where a pass rests on deduced
rather than directly read evidence, the `Actual` column says so.

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
- **P-N8N** — a reachable n8n instance with the inbound webhook deployed. **Satisfied (P06)** — n8n Cloud, workflow published and active on its production webhook URL.
- **P-SHEET** — a Google Sheet configured as the backup destination. **Satisfied (P06)** — `leads_backup` and `run_log` are written on the live path. `needs_human` exists with its headers and is deliberately unused until TC-08 and TC-12 are built.
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
| TC-01 | New lead, happy path | Form submission with all required fields, unseen `externalLeadId` | Contact created in GHL; opportunity created in pipeline at `New Lead`; row appended to backup sheet; a `run_log` row per stage boundary, all sharing one `correlationId`, terminating in `outcome=processed` | Live submission of a new fictional fixture (Valeria Cruz) 2026-08-09 05:30:40Z. **GHL via MCP:** exactly one Contact and one Opportunity `Valeria Cruz - Real Estate`, `status=open`, pipeline `LeadFlow Demo Pipeline`, stage `New Lead`, `source=GHL Demo Form`. **n8n production execution 6** (mode `webhook`, 05:30:46→05:30:53Z), last node executed `Respond 200 processed`. Derived `eventId=ghl:opportunity-created:cs7Ef…` matches the Opportunity id GHL returned, and no merge tag arrived unresolved. `Sheets: leads_backup` executed once with exactly one item (`lastAction=backup_written`, `status=processed`, `attempt=1`); across all six executions ever run on this workflow that node executed exactly once, so a second row for this event is not reachable. `run_log` boundaries `claim` → `leads_backup` → `complete` all executed under one `correlationId=n8n:6`, final `outcome=processed`. Ledger row `status=completed`, `attempt=1`, table row id 1 — the only row ever inserted. **Evidence basis:** the n8n execution record plus live GHL reads. The spreadsheet was not read back; row counts are deduced from node execution, not from opening the sheet | PASS |
| TC-02 | Duplicate **delivery** — webhook redelivered | The exact TC-01 webhook payload delivered a second time — same `opportunityId`, therefore the same delivery identity `ghl:opportunity-created:<opportunityId>` per ADR-002. `externalLeadId` is deliberately **not** the key here: it identifies the original submission event and nothing populates it on this path | `leads_backup` row count for this `eventId` stays at exactly 1; zero notifications; zero AI calls; zero GHL API calls on the second delivery; HTTP 200 success-shaped, never 4xx/5xx; exactly one additional `run_log` row, `outcome=duplicate_event`, same `eventId`, **different** `correlationId` | Replayed via `scripts/replay-webhook.ps1` against the production URL, 2026-08-09 07:14:23Z — n8n execution 7. Observed HTTP **200 `already_processed`**. Same `eventId` as TC-01, new `correlationId=n8n:7` (TC-01 was `n8n:6`), `attempt=2`, and `firstSeenAt` preserved from the original delivery at 05:30:48Z. Ledger lookup hit: `ledgerFound=true`, `ledgerStatus=completed`, `alreadyProcessed=true`. `Ledger: Claim` and `Sheets: leads_backup` **never executed** — zero additional backup rows proven by node absence, not by counting. `Log Duplicate Event` wrote exactly one row, `step=dedup`, `outcome=duplicate_event`. Last node `Respond 200 already_processed`. Zero GHL calls — the workflow issues none on any path. Operator-read sheet totals corroborate — **read after execution 8 at 07:15Z, not at this test's own 07:14Z timestamp** — `leads_backup` = 1 data row, `run_log` = 10, which reconciles exactly as 5 diagnostic rejections + 3 processing boundaries + 1 `duplicate_event` + 1 `unauthorized`. **Sequential only** — a redelivery minutes later is not evidence of concurrent-safety | PASS |
| TC-02b | Duplicate **form submission** — same person submits twice | The TC-01 form submitted twice in quick succession, ~1 minute apart (instructed as 5 seconds; actual observed gap) | One contact, by GHL's own upsert. A second Opportunity is expected to be blocked by GHL's native duplicate-opportunity guard (P0, P05: location setting `allowDuplicateOpportunity: false` + the `Create Opportunity` action's own toggle) — **not** by the `external_lead_id` pre-create check, which remains confirmed unbuildable and is not under test here. Sequential only; not evidence of concurrent-safety. See `docs/decisions/ADR-002-idempotency-strategy.md` "Consequences to watch". **Amended in P07 — and its pass no longer covers the deployed artifact.** The GHL workflow changed underneath this row: `Allow Re-entry` went on and the `Find Opportunity` split was added (v9 → v12). Under v12 the second submission also produces a `repeat-inquiry` tag, an internal note, and `inquiry_count = 2`, because GHL exposes no submission identity that could tell an accidental double-click from a genuine second inquiry — the accepted cost of never again swallowing a real re-inquiry (`docs/ghl-setup.md`, "The tradeoff this accepts"). **What is *not* claimed:** that "one Contact, one Opportunity" still holds under v12. That would be an assertion, not an observation, and this file's own rule is that a pass proves the artifact it ran against and nothing later. A fast double submission under v12 could plausibly put two runs at `Find Opportunity` before the first Opportunity exists, sending **both** down `Not Found` into `Create Opportunity` — where the only remaining protection is the very guard this file now records as never exercised. **TC-02b must be re-run against v12.** Until then its status covers pre-v12 only | Two sequential submissions of the fixture (David Demo, david.demo@example.com, +1 202-555-0101, Mortgage) via the live published form. Live MCP verification: exactly one Contact (upserted by GHL, matched on email+phone, not duplicated); exactly one Opportunity, `status=open`, pipeline `LeadFlow Demo Pipeline` / stage `New Lead`, `source="GHL Demo Form"`, `monetaryValue=0`, name correctly resolved to `David Demo - Mortgage`, `internalSource.source=WORKFLOW_NEW` confirming automated creation. Contact's `service_interest`/`lead_message` custom fields populated on the correct P0 field objects. First pass surfaced and required fixing three build defects (email field not mapped to the standard attribute, form auto-created two duplicate custom fields instead of reusing the P0 set, Opportunity name left as unresolved literal placeholder text) — the broken interim contact/opportunity and the orphaned duplicate fields were deleted before this final run. ~~Confirms the P0 guard holds for a quick sequential repeat of the identical fixture.~~ **Attribution retracted 2026-08-09 (P07) — the assertions stand, the explanation does not.** Building the TC-03 branch required enabling `Allow Re-entry` in the workflow's settings, which means it was **off** when this test ran. With re-entry off, the second submission never re-entered the workflow at all, so `Create Opportunity` never ran a second time and **the duplicate-opportunity guard was never exercised**. "The guard blocked it" and "the action never ran" produce byte-identical output — one Contact, one Opportunity — and the evidence captured here cannot separate them. What this row still proves is GHL's contact upsert; what it never proved is the guard. The general lesson, recorded because it shaped TC-03's design: **a negative outcome is weak evidence**, so TC-03 asserts positive artifacts instead. Sequential only, ~1 minute apart — not evidence of concurrent-safety, and does not exercise the re-inquiry branch (TC-03) | PASS — pre-P07 artifact only; re-run required |
| TC-03 | **Genuine re-inquiry — same person, different intent** | Two sequential submissions of the live form by one person. Submission 1 establishes the Contact and an open Opportunity. Submission 2 carries the **same** email and phone but a **different** service interest and a **different** message. Between them the Opportunity is moved to `Follow-up` by hand, so the stage pull-back arm is actually exercised rather than assumed | Rewritten in P07. The old Expected asserted "a new opportunity is created **or** the existing one is flagged" — a disjunction that passes on either outcome and therefore asserts nothing — and additionally demanded the lead be "marked as a suspected duplicate for human review". That clause has been **removed**: it belongs to ADR-002's `possible-duplicate-person` case, which is a *name* match with *differing* contact details. TC-03's input is an email-and-phone match, which ADR-002 says must be resolved automatically and amplified, not queued for a human. What TC-03 asserts now, deterministically: exactly **one** Contact; exactly **one** Opportunity — and note precisely *why*, because it is easy to get wrong: the `Found` path never reaches `Create Opportunity` at all, so the single opportunity is explained by **routing**, not by the duplicate-opportunity guard. TC-03 exercises that guard no more than TC-02b did. Tag `repeat-inquiry` present on the contact; an **internal** note carrying submission 2's *own* service interest and message plus a timestamp; `inquiry_count = 2`; the Opportunity still `status=open` and visible for human follow-up, and back at `Contacting` having been left in `Follow-up`; zero SMS, zero email, zero premium action. **Deliberately absent, not a defect:** no `leads_backup` row and no webhook — GHL exposes no stable submission identity, so the event-grained backup of a re-inquiry is deferred and documented in `docs/ghl-setup.md`. **False-pass trap:** "one contact, one opportunity, nothing duplicated" is byte-identical to the silent-suppression bug this test exists to catch. A pass requires positively observing the amplification artifacts, and the note and fields must carry submission **2's** distinct values — matching submission 1's content proves nothing about which submission wrote them | Two sequential live form submissions, 2026-08-09, fictional fixture Priya Chandran. **Submission 1, 17:21:36Z:** exactly one Contact; exactly one Opportunity `Priya Chandran - Real Estate`, `status=open`, stage `New Lead`, `internalSource.source=WORKFLOW_NEW`; `inquiry_count=1`, proving the `Not Found` branch's initialiser ran; **`tags: []`** — a first inquiry is **not** marked as repeated, read rather than inferred. n8n execution 12 succeeded 6s later, so the P06 golden path survived the edit. **Drift step, 21:47:48Z:** the Opportunity was moved to `Follow-up` via `update-opportunity` so the pull-back arm would be exercised rather than assumed. **Submission 2, 21:49:5xZ** — same email and phone, service `Mortgage`, different message. **Observed:** Contact `total: 1`, still one. Exactly one Opportunity — same id, `createdAt` still 17:21:39Z, so no second was created and none was recreated. `tags: ["repeat-inquiry"]`. `inquiry_count = 2`. `service_interest = "Mortgage"` and `lead_message` = submission 2's text, so submission 2's own values landed. Exactly **one** note on the contact, title `Repeat Inquiry`, body carrying `Service Interest: Mortgage`, submission 2's message verbatim, and `Received at: 8/9/2026 03:49 PM` — one note total confirms submission 1 wrote none. Opportunity `status=open` with `lastStatusChangeAt` unchanged at 17:21:39Z, stage now `Contacting`, `lastStageChangeAt` 21:49:59Z — pulled back from the `Follow-up` set two minutes earlier. Zero SMS, zero email, zero premium action. **Falsifiable prediction, recorded before the run and held:** n8n execution count stayed at **12** — no opportunity created means no webhook, so the re-inquiry leaves no `leads_backup` row, exactly as designed and documented. Observed against published workflow **version 12** (was 9 before the P07 edit) | PASS |
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
| TC-18 | Unauthorized webhook rejected | Request to the webhook URL with a missing or wrong shared secret | Rejected with 401 synchronously; zero GHL API calls issued by n8n; zero backup rows; exactly one `run_log` row recording the rejection, with an `outcome` distinct from the validation-failure value; no node after the secret check executes | Observed on **five live GHL deliveries** — n8n executions 1–5, 2026-08-09 04:31–05:17Z — during which the secret the normalizer resolved was empty, because it read the wrong payload path. Observationally this is the "missing secret" arm of this case. Every one of the five terminated at `Respond 401` (`responseCode: 401`). `Sheets: leads_backup` and `Ledger: Claim` never executed in any of them, so zero backup rows and zero ledger writes are proven by node absence rather than by counting rows. `Log Unauthorized` wrote exactly one row per delivery, `step=authorize`, `status=rejected`, `outcome=unauthorized` — distinct from the `invalid_payload` outcome TC-09 uses. The rejection row carries **no caller-supplied value**: `eventId`, `contactId` and `opportunityId` are deliberately empty, so an unauthenticated caller cannot write chosen content into the audit log. Zero GHL mutations — the workflow issues no GHL call on any path, and MCP reads confirm the records were untouched by n8n. These were real webhook deliveries from GHL, not scripted replays. **Both arms are covered.** Those five prove the absent-secret arm — the resolved value was empty. The wrong-value arm was then run deliberately via `scripts/replay-webhook.ps1 -Mode WrongSecret` (executions 8 and 10): same 401, same single `unauthorized` row, `Ledger: Claim` and `Sheets: leads_backup` again never executed. Execution 10 logged `n8n variable resolved: true`, which distinguishes a mismatched value from an unset variable and rules out the two failing for the same reason | PASS |
| TC-19 | **Formula injection through the public form** | A lead submits a name beginning with `=`, delivered over the normal authorized path with GHL's own correct shared secret | The value is stored in `leads_backup` as literal text, never evaluated. The attacker holds no secret and needs none — this is reachable by anyone who can submit the public form, so path secrecy and the shared secret are both irrelevant to it | Live submission `=1+1 Testcase` 2026-08-09 15:33Z — n8n execution 11. The normalizer passed `name: "=1+1 Testcase"` to `Sheets: leads_backup`, the write succeeded, and `Respond 200 processed` was the last node. Operator read of the sheet shows the **literal text** `=1+1 Testcase` in the `name` column, not `2`. Confirms `options.cellFormat: "RAW"` is in effect on the published workflow. Note the boundary this does **not** cover: `RAW` governs storage only, so exporting `leads_backup` to CSV or XLSX and opening it in Excel or LibreOffice re-parses the leading `=` at import time regardless — see `docs/n8n-setup.md` | PASS |

---

## Which artifact each pass was observed against

A passing test proves the version it ran against, not the version currently
deployed. n8n keeps a draft and an active version, and saving changes only the
draft — see [`docs/n8n-setup.md`](docs/n8n-setup.md) §5.

| Evidence | When (UTC) | Active version then |
|---|---|---|
| TC-18, five live rejected deliveries | 04:31–05:17 | pre-`b162ad3f` (`b4aa5cf4` / `b8fa1e5e`) |
| TC-01, execution 6 | 05:30 | `b162ad3f` |
| TC-02, execution 7 | 07:14 | `b162ad3f` |
| TC-18 wrong-value, execution 8 | 07:15 | `b162ad3f` |
| **TC-02 + TC-18 re-verification, executions 9 and 10** | 15:26 | published fix — debug object removed, `customData` fallback, normalised expressions |
| **TC-19, execution 11** | 15:33 | published `cellFormat: RAW` fix |
| **TC-03, both submissions** | 17:21 and 21:49 | n8n unchanged (`cellFormat: RAW` fix, no P07 edit); **GHL** `Form to Opportunity` **v12** |
| **TC-02b — superseded, not re-run** | ran pre-P07 | **GHL v9 with `Allow Re-entry` off.** The deployed artifact is now v12 with re-entry on. This row's pass does **not** cover v12 |
| **TC-01 — partially re-covered by TC-03's submission 1** | 17:21 | TC-01's own run (05:30) predates GHL v12 and faces the same demotion as TC-02b. It is **not** demoted, and the reason is narrower than "it still passes". The artifact that changed is the **GHL** workflow, so only TC-01's GHL-dependent assertions needed re-observing, and both were: a new Contact, and an Opportunity created at `New Lead`. Its other two assertions — the `leads_backup` row, and one `run_log` row per boundary sharing a `correlationId` and ending `outcome=processed` — ride on the **n8n** workflow, which this table records as unchanged since execution 11. **What was not re-observed:** those two. Execution 12 is recorded only as `status=success`; no node record, `correlationId`, ledger row or sheet read was captured for it. TC-02b gets no equivalent rescue because its assertion is about a *second* submission's behaviour, and nothing has run that under v12 |

TC-03 is the first row whose artifact is a **GoHighLevel** workflow rather than
an n8n one, and GHL has the same trap: an edit can sit unpublished while the
old version keeps serving. `get-workflow` exposes only id, name, status and
**version** — no step detail — so the version number is the only
machine-checkable proof that a UI edit shipped. It was read at `9` after the
branch was first reported built, and at `12` after the corrected build was
published. That gap is why TC-03 was not executed against the first build.

The re-verification covers every line changed by the security fix: the
normalizer, the secret comparison, the dedup branch, and the rejection row's
new diagnostic column. Execution 10 logged
`n8n variable resolved: true`, which additionally proves the rejection came
from a genuinely mismatched value rather than an unset variable.

The later `cellFormat: RAW` change on the eight Google Sheets nodes was
initially covered by nothing — neither TC-02 nor TC-18 writes to
`leads_backup` at all. It is now covered by **TC-19** (execution 11, 15:33Z), a
live submission whose name begins with `=`, verified both in the execution
record and by reading the stored cell.

## Evidence policy

When a scenario is executed, the `Actual` column records what was observed —
the created record identifiers, the log correlation id, and the screenshot or
export used as proof. Scenarios move to `PASS` only with that evidence
attached. Test data is fictional throughout; no real person's contact details
are used at any point.
