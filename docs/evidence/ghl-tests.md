# Evidence — GoHighLevel-side test cases

Full input, expected outcome, and observed evidence for the scenarios whose
artifact is the **GoHighLevel** leg: the golden path, the duplicate form
submission, and the genuine re-inquiry.

Summary status lives in [`../../TEST_CASES.md`](../../TEST_CASES.md). This file
is the detail; it is not a second source of truth for status.

Related evidence files:
[n8n reliability](n8n-reliability-tests.md) ·
[security](security-tests.md) ·
[reconciliation](reconciliation-tests.md)

---

## TC-01 — New lead, happy path

**Status: PASS**

**Input.** Form submission with all required fields, unseen `externalLeadId`.

**Expected.** Contact created in GHL; opportunity created in pipeline at
`New Lead`; row appended to backup sheet; a `run_log` row per stage boundary,
all sharing one `correlationId`, terminating in `outcome=processed`.

**Actual.** Live submission of a new fictional fixture (Valeria Cruz)
2026-08-09 05:30:40Z. **GHL via MCP:** exactly one Contact and one Opportunity
`Valeria Cruz - Real Estate`, `status=open`, pipeline `LeadFlow Demo Pipeline`,
stage `New Lead`, `source=GHL Demo Form`. **n8n production execution 6** (mode
`webhook`, 05:30:46→05:30:53Z), last node executed `Respond 200 processed`.
Derived `eventId=ghl:opportunity-created:cs7Ef…` matches the Opportunity id GHL
returned, and no merge tag arrived unresolved. `Sheets: leads_backup` executed
once with exactly one item (`lastAction=backup_written`, `status=processed`,
`attempt=1`); across all six executions ever run on this workflow that node
executed exactly once, so a second row for this event is not reachable.
`run_log` boundaries `claim` → `leads_backup` → `complete` all executed under
one `correlationId=n8n:6`, final `outcome=processed`. Ledger row
`status=completed`, `attempt=1`, table row id 1 — the only row ever inserted.
**Evidence basis:** the n8n execution record plus live GHL reads. The
spreadsheet was not read back; row counts are deduced from node execution, not
from opening the sheet.

---

## TC-02b — Duplicate form submission, same person submits twice

**Status: PASS — pre-P07 artifact only; re-run required**

**Input.** The TC-01 form submitted twice in quick succession, ~1 minute apart
(instructed as 5 seconds; actual observed gap).

**Expected.** One contact, by GHL's own upsert. A second Opportunity is
expected to be blocked by GHL's native duplicate-opportunity guard (P0, P05:
location setting `allowDuplicateOpportunity: false` + the `Create Opportunity`
action's own toggle) — **not** by the `external_lead_id` pre-create check,
which remains confirmed unbuildable and is not under test here. Sequential
only; not evidence of concurrent-safety. See
[`../decisions/ADR-002-idempotency-strategy.md`](../decisions/ADR-002-idempotency-strategy.md)
"Consequences to watch". **Amended in P07 — and its pass no longer covers the
deployed artifact.** The GHL workflow changed underneath this row:
`Allow Re-entry` went on and the `Find Opportunity` split was added (v9 → v12).
Under v12 the second submission also produces a `repeat-inquiry` tag, an
internal note, and `inquiry_count = 2`, because GHL exposes no submission
identity that could tell an accidental double-click from a genuine second
inquiry — the accepted cost of never again swallowing a real re-inquiry
([`../ghl-setup.md`](../ghl-setup.md), "The tradeoff this accepts"). **What is
*not* claimed:** that "one Contact, one Opportunity" still holds under v12.
That would be an assertion, not an observation, and this file's own rule is
that a pass proves the artifact it ran against and nothing later. A fast double
submission under v12 could plausibly put two runs at `Find Opportunity` before
the first Opportunity exists, sending **both** down `Not Found` into
`Create Opportunity` — where the only remaining protection is the very guard
this file now records as never exercised. **TC-02b must be re-run against v12.**
Until then its status covers pre-v12 only.

**Actual.** Two sequential submissions of the fixture (David Demo,
david.demo@example.com, +1 202-555-0101, Mortgage) via the live published form.
Live MCP verification: exactly one Contact (upserted by GHL, matched on
email+phone, not duplicated); exactly one Opportunity, `status=open`, pipeline
`LeadFlow Demo Pipeline` / stage `New Lead`, `source="GHL Demo Form"`,
`monetaryValue=0`, name correctly resolved to `David Demo - Mortgage`,
`internalSource.source=WORKFLOW_NEW` confirming automated creation. Contact's
`service_interest`/`lead_message` custom fields populated on the correct P0
field objects. First pass surfaced and required fixing three build defects
(email field not mapped to the standard attribute, form auto-created two
duplicate custom fields instead of reusing the P0 set, Opportunity name left as
unresolved literal placeholder text) — the broken interim contact/opportunity
and the orphaned duplicate fields were deleted before this final run.
~~Confirms the P0 guard holds for a quick sequential repeat of the identical
fixture.~~ **Attribution retracted 2026-08-09 (P07) — the assertions stand, the
explanation does not.** Building the TC-03 branch required enabling
`Allow Re-entry` in the workflow's settings, which means it was **off** when
this test ran. With re-entry off, the second submission never re-entered the
workflow at all, so `Create Opportunity` never ran a second time and **the
duplicate-opportunity guard was never exercised**. "The guard blocked it" and
"the action never ran" produce byte-identical output — one Contact, one
Opportunity — and the evidence captured here cannot separate them. What this
row still proves is GHL's contact upsert; what it never proved is the guard.
The general lesson, recorded because it shaped TC-03's design: **a negative
outcome is weak evidence**, so TC-03 asserts positive artifacts instead.
Sequential only, ~1 minute apart — not evidence of concurrent-safety, and does
not exercise the re-inquiry branch (TC-03).

---

## TC-03 — Genuine re-inquiry, same person, different intent

**Status: PASS**

**Input.** Two sequential submissions of the live form by one person.
Submission 1 establishes the Contact and an open Opportunity. Submission 2
carries the **same** email and phone but a **different** service interest and a
**different** message. Between them the Opportunity is moved to `Follow-up` by
hand, so the stage pull-back arm is actually exercised rather than assumed.

**Expected.** Rewritten in P07. The old Expected asserted "a new opportunity is
created **or** the existing one is flagged" — a disjunction that passes on
either outcome and therefore asserts nothing — and additionally demanded the
lead be "marked as a suspected duplicate for human review". That clause has been
**removed**: it belongs to ADR-002's `possible-duplicate-person` case, which is
a *name* match with *differing* contact details. TC-03's input is an
email-and-phone match, which ADR-002 says must be resolved automatically and
amplified, not queued for a human. What TC-03 asserts now, deterministically:
exactly **one** Contact; exactly **one** Opportunity — and note precisely *why*,
because it is easy to get wrong: the `Found` path never reaches
`Create Opportunity` at all, so the single opportunity is explained by
**routing**, not by the duplicate-opportunity guard. TC-03 exercises that guard
no more than TC-02b did. Tag `repeat-inquiry` present on the contact; an
**internal** note carrying submission 2's *own* service interest and message
plus a timestamp; `inquiry_count = 2`; the Opportunity still `status=open` and
visible for human follow-up, and back at `Contacting` having been left in
`Follow-up`; zero SMS, zero email, zero premium action. **Deliberately absent,
not a defect:** no `leads_backup` row and no webhook — GHL exposes no stable
submission identity, so the event-grained backup of a re-inquiry is deferred and
documented in [`../ghl-setup.md`](../ghl-setup.md). **False-pass trap:** "one
contact, one opportunity, nothing duplicated" is byte-identical to the silent-
suppression bug this test exists to catch. A pass requires positively observing
the amplification artifacts, and the note and fields must carry submission
**2's** distinct values — matching submission 1's content proves nothing about
which submission wrote them.

**Actual.** Two sequential live form submissions, 2026-08-09, fictional fixture
Priya Chandran. **Submission 1, 17:21:36Z:** exactly one Contact; exactly one
Opportunity `Priya Chandran - Real Estate`, `status=open`, stage `New Lead`,
`internalSource.source=WORKFLOW_NEW`; `inquiry_count=1`, proving the
`Not Found` branch's initialiser ran; **`tags: []`** — a first inquiry is
**not** marked as repeated, read rather than inferred. n8n execution 12
succeeded 6s later, so the P06 golden path survived the edit. **Drift step,
21:47:48Z:** the Opportunity was moved to `Follow-up` via `update-opportunity`
so the pull-back arm would be exercised rather than assumed. **Submission 2,
21:49:5xZ** — same email and phone, service `Mortgage`, different message.
**Observed:** Contact `total: 1`, still one. Exactly one Opportunity — same id,
`createdAt` still 17:21:39Z, so no second was created and none was recreated.
`tags: ["repeat-inquiry"]`. `inquiry_count = 2`. `service_interest = "Mortgage"`
and `lead_message` = submission 2's text, so submission 2's own values landed.
Exactly **one** note on the contact, title `Repeat Inquiry`, body carrying
`Service Interest: Mortgage`, submission 2's message verbatim, and
`Received at: 8/9/2026 03:49 PM` — one note total confirms submission 1 wrote
none. Opportunity `status=open` with `lastStatusChangeAt` unchanged at
17:21:39Z, stage now `Contacting`, `lastStageChangeAt` 21:49:59Z — pulled back
from the `Follow-up` set two minutes earlier. Zero SMS, zero email, zero premium
action. **Falsifiable prediction, recorded before the run and held:** n8n
execution count stayed at **12** — no opportunity created means no webhook, so
the re-inquiry leaves no `leads_backup` row, exactly as designed and documented.
Observed against published workflow **version 12** (was 9 before the P07 edit).

---

## Which artifact each of these passes was observed against

A passing test proves the version it ran against, not the version currently
deployed.

| Evidence | When (UTC) | Active version then |
|---|---|---|
| TC-01, execution 6 | 05:30 | `b162ad3f` |
| **TC-03, both submissions** | 17:21 and 21:49 | n8n unchanged (`cellFormat: RAW` fix, no P07 edit); **GHL** `Form to Opportunity` **v12** |
| **TC-02b — superseded, not re-run** | ran pre-P07 | **GHL v9 with `Allow Re-entry` off.** The deployed artifact is now v12 with re-entry on. This row's pass does **not** cover v12. **Still not re-run as of P08** — the re-run needs two live submissions of the public GHL form, and no browser automation was available in the P08 session |
| **TC-01 — partially re-covered by TC-03's submission 1** | 17:21 | TC-01's own run (05:30) predates GHL v12 and faces the same demotion as TC-02b. It is **not** demoted, and the reason is narrower than "it still passes". The artifact that changed is the **GHL** workflow, so only TC-01's GHL-dependent assertions needed re-observing, and both were: a new Contact, and an Opportunity created at `New Lead`. Its other two assertions — the `leads_backup` row, and one `run_log` row per boundary sharing a `correlationId` and ending `outcome=processed` — ride on the **n8n** workflow, which is recorded as unchanged since execution 11. **What was not re-observed:** those two. Execution 12 is recorded only as `status=success`; no node record, `correlationId`, ledger row or sheet read was captured for it. TC-02b gets no equivalent rescue because its assertion is about a *second* submission's behaviour, and nothing has run that under v12 |

TC-01's n8n-side assertions were separately re-observed against the P08 rebuild
as execution 20 — see
[n8n reliability evidence](n8n-reliability-tests.md#which-artifact-each-of-these-passes-was-observed-against).

TC-03 is the first row whose artifact is a **GoHighLevel** workflow rather than
an n8n one, and GHL has the same trap: an edit can sit unpublished while the
old version keeps serving. `get-workflow` exposes only id, name, status and
**version** — no step detail — so the version number is the only
machine-checkable proof that a UI edit shipped. It was read at `9` after the
branch was first reported built, and at `12` after the corrected build was
published. That gap is why TC-03 was not executed against the first build.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../ghl-setup.md`](../ghl-setup.md) — how the GHL leg is built
- [`../decisions/ADR-002-idempotency-strategy.md`](../decisions/ADR-002-idempotency-strategy.md) — identity and dedup strategy
</content>
