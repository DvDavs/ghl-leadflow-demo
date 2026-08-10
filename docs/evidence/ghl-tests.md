# Evidence — GoHighLevel-side test cases

Full input, expected outcome, and observed evidence for the scenarios whose
artifact is the **GoHighLevel** leg: the golden path, the duplicate form
submission, the genuine re-inquiry, and the `inquiry_count` null-safety fix.

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

**Status: PASS — re-run against GHL v13 on 2026-08-10 (P08C)**

### Re-run — two browser-driven submissions 4.3 seconds apart

**Input.** A brand-new fictional fixture — `Ines Marchetti`,
`ines.marchetti@example.com`, `+1 202-555-0119`, `Financial Services` — with
**pre-state confirmed zero**: contact search on `Marchetti` returned
`total: 0`, the form's submission counter stood at **12**, and the n8n ingress
workflow had **24** executions, latest id `42`. Two instances of the public
form were opened in **two isolated browser contexts** (distinct sessions —
GHL recorded `sessionId` `79d9d66d…` and `6cd8f8e9…`), filled identically, and
both `Submit` buttons were clicked from one `Promise.all`. No human filled a
form.

**Expected.** Exactly one Contact, exactly one Opportunity, two observable
submissions — and, per this file's own rule that a negative outcome is weak
evidence, an explicit answer to *which* mechanism produced the single
opportunity: both runs reaching `Create Opportunity` with the
duplicate-opportunity guard blocking one, or one run finding the other's
opportunity and taking `Found`.

**Actual — the intended concurrency was not achieved, and the number is
reported as measured.** Both clicks were dispatched together (the two
`click()` calls returned 92 ms and 114 ms after `t0 = 03:29:34.121Z`), but each
page then had to clear its own **Cloudflare Turnstile** challenge before the
form would post, and the two challenges resolved at different speeds. The
`POST /forms/submit` calls left the browser at **+107 ms** and **+4483 ms** —
a **4.376 s** separation. GHL's server-side stamps agree: the two submission
records carry `createdAt` `03:29:33.492Z` and `03:29:37.818Z`, a **4.326 s**
separation. (The ~0.7 s absolute offset between the two clocks is skew; the
two independently measured *separations* agree within 50 ms, and that is the
figure this row rests on.) **Everything below is therefore evidence about two
submissions 4.3 seconds apart, and nothing more. It is not a concurrency
result.**

**Observed, all read live over MCP:**

| Assertion | Observed |
|---|---|
| Exactly one Contact | `total: 1` — `7pprKWbD…`, `dateAdded 03:29:33.132Z` |
| Exactly one Opportunity | `vX04hv8q…`, `Ines Marchetti - Financial Services`, `status=open`, stage `New Lead`, `createdAt 03:29:36.275Z`, `internalSource.source=WORKFLOW_NEW`, `internalSource.id=a291c99f…` |
| Two submissions observable | Counter **12 → 14**; `submissionId` `85556563…` at `03:29:33.492Z` and `a380e849…` at `03:29:37.818Z`, from two different session ids and two different egress IPs |
| Amplification artifacts | `tags: ["repeat-inquiry"]`; `inquiry_count = 2`; exactly **one** note `Mc8z6UCt…` at `03:29:40.787Z` carrying `Financial Services` and the fixture message |
| Downstream | n8n executions **24 → 25** — exactly one new execution, id `72`, `03:29:40.722Z`. One opportunity created, one webhook. Its node record also re-covers TC-01 at the current n8n active version: `Sheets: leads_backup` ran once with one item, ledger row 19 `completed`, last node `Respond 200 processed`, `correlationId=n8n:72` |

**What actually happened, and it is the second of the two possibilities.**
Submission 2's post landed **1.54 s after the Opportunity already existed**
(`03:29:37.818Z` vs `03:29:36.275Z`), so its `Find Opportunity` returned
**Found** and the run went down the re-inquiry arm. The positive evidence for
that attribution — rather than the absence of a second opportunity, which
proves nothing — is the **single note**: `Add to Notes` exists only on the
`Found` branch, so exactly one note means exactly one run took `Found` and
exactly one took `Not Found`.

**The duplicate-opportunity guard is therefore still not exercised.**
`Create Opportunity` was reached **once**, not twice. This run narrows the
window in which the guard could ever be reached — it is under 1.5 s, not under
4.3 s — and that is all it does. The guard remains, as it has since P05, a
**[DOCUMENTED]** backstop with no observation behind it.

**One thing this run deliberately does not claim.** `inquiry_count = 2` here
is **not** evidence about the P08C null-safety branch. Both arms of the new
`If/Else` produce `2` from this starting state — `Set Inquiry Count = 2` on an
empty field, and `Increment` on the `1` submission 1 had already written — and
the stored value cannot distinguish them. The `empty` arm is evidenced by the
`Marisol Vega` run below, not by this one.

**Reproducing this needs a new fixture.** `Ines Marchetti` is consumed: she now
has an open opportunity and `inquiry_count = 2`, so a third submission would
exercise the `Found` path, not TC-02b.

### Original run — superseded, retained for the attribution lesson

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
this file now records as never exercised. **TC-02b must be re-run.**
*Answered by the re-run above, against v13:* at a 4.3 s separation both runs do
**not** reach `Create Opportunity` — the second finds the first's Opportunity
and takes `Found`. The hypothesis is untested below ~1.5 s.

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

**Status: PASS — re-run against GHL v13 on 2026-08-10.** The v12 run below is
retained in full; the v13 re-run that supersedes it, and the arm it finally
traverses, are recorded after it.

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

### Re-run against v13 — the `Increment` + `Go To` arm, finally traversed

**Why it was needed.** v13 replaced the bare `Math Operation` on the
`Opportunity Found` branch with an `If/Else`, so the run above proved a shape
that no longer exists. Of the two runs that had touched v13, only one had an
identified arm — `Marisol Vega` took the **`empty`** side — and TC-02b's
[deliberately claims nothing](#tc-02b--duplicate-form-submission-same-person-submits-twice)
about which arm it took. The `Increment` arm and the `Go To` that rejoins the
stage gate had been traversed by nothing that could be named. The whole point of
this re-run was a contact whose `inquiry_count` is **already set, and read as
set before the run**, so the `If/Else` is forced down the other side and the
result is attributable.

**Fixture — brand new, and proven empty first.** `Rafael Okonkwo`,
`rafael.okonkwo@example.com`, `+1 202-555-0173`. Before submission 1, three
searches returned `total: 0` — by email, by surname, and by phone — plus zero
opportunities. The phone was chosen only after `+1 202-555-0142` came back
already bound to `Marisol Vega`; a phone collision would have merged the
fixture into an existing contact and destroyed the test silently.

**Submission 1, `04:13:43Z`** — browser-driven, `Real Estate`, first message.
Contact `9YYMaxKvwX0pEJweE65r` created at `04:13:43.031Z`; one Opportunity
`yVqNs2DDqjaxGT0vfb5G` — `Rafael Okonkwo - Real Estate`, `status=open`, stage
**`New Lead`** (`2de64cba…`), `createdAt 04:13:47.025Z`, `source=GHL Demo Form`.
`inquiry_count = 1`, **`tags: []`**, and **zero notes** — read, not assumed, so
that every amplification artifact below is provably submission 2's. n8n ingress
execution **78** started at `04:13:51.816Z`, 4.8 s after the Opportunity, taking
the count 25 → 26. Only the execution record was read — status `success`, mode
`webhook`, timings; its node detail was **not** opened, so this run makes no
claim about the `leads_backup` row beyond the fact that an execution ran.

**Drift step, `04:14:50Z`** — the Opportunity moved to **`Follow-up`**
(`ab8d09dd…`) via `update-opportunity`, so the pull-back arm is exercised rather
than assumed. `createdAt` unchanged.

**Submission 2, `04:15:21Z`** — same email, same phone, service `Mortgage`
instead of `Real Estate`, a different message.

| Assertion | Observed |
|---|---|
| One contact | `total: 1` — same `9YYMaxKvwX0pEJweE65r`, `dateAdded` still `2026-08-10T04:13:43.031Z` |
| One opportunity, same identity | `total: 1` — `yVqNs2DDqjaxGT0vfb5G`, `createdAt` still `04:13:47.025Z`. No second was created and none was recreated |
| **`inquiry_count` `1 → 2`** | `{"id":"5cawDbnm…","value":2}` — **this is the `Increment` arm** (see the note below on why that is claimable here and was not in TC-02b) |
| `repeat-inquiry` | `tags: ["repeat-inquiry"]` |
| Exactly one note, carrying submission **2** | **0 → 1** — `vQunpCWiDE3aqt5BLHfE` at `04:15:25.335Z`, title `Repeat Inquiry`, body `Service Interest: Mortgage`, submission 2's message verbatim, `Received at: 8/9/2026 10:15 PM`. One note total confirms submission 1 wrote none |
| Submission 2's own values landed | `service_interest = "Mortgage"`, `lead_message` = submission 2's text |
| Status untouched | `status=open`, `lastStatusChangeAt` still `04:13:47.025Z` |
| **`Follow-up` → `Contacting`** | `pipelineStageId` `bcd8e39a…`, `lastStageChangeAt 04:15:29.776Z` — pulled back from the `Follow-up` set 39 s earlier |
| Exactly one n8n execution in the whole scenario | Ingress count **25 → 26**, latest id **78** at `04:13:51Z` — submission 1's `Opportunity Created`. Nothing after `04:15`. The re-inquiry fired **no** webhook |
| Exactly two form submissions | `69b43ecc…` at `04:13:43.412Z` and `a740bccb…` at `04:15:21.573Z`, both bound to the same `contactId` |

**Why the arm is attributable here, when TC-02b's was not.** TC-02b reached
`inquiry_count = 2` from what looked like the same starting state and
[refused to claim an arm](#tc-02b--duplicate-form-submission-same-person-submits-twice),
correctly: its two submissions were 4.3 s apart, and the `1` is written by the
`Not Found` branch *after* `Create Opportunity`, so whether the field was
already `1` or still empty when submission 2 evaluated the condition is
genuinely racy. The stored `2` cannot settle it. **This run removes the race
rather than arguing past it.** The gap is 98 s, not 4.3 s, and `inquiry_count`
was **read live as `1`** at `04:14` — before the drift step and 90 s before
submission 2. A field holding `1` is not empty, and the `empty` arm is the only
one that writes a literal `2`; from a field that demonstrably held `1`, only
`+1` reaches `2`. The distinguishing evidence is the **pre-state**, read, not
the output value.

**What the stage move proves, and it is the point of the re-run.** The
`Increment` arm does not reach `Recheck Open Opportunity` by falling through —
it gets there through a **`Go To`**, the one construct in either GHL workflow
whose behaviour had rested on nothing but the build report and the published
version number. The stage came back from `Follow-up` to `Contacting`, so
execution reached the second `Find Opportunity` **after** taking the increment
side. `Go To` is now observed, not asserted. Note what carries which half: the
stage move alone would not identify the arm — both arms converge on that same
gate — and the pre-state alone would not prove the `Go To` fired. The two
together do.

**What this run still does not prove.** The duplicate-opportunity guard, exactly
as in the v12 run and in TC-02b: the `Found` path never reaches
`Create Opportunity`, so the single opportunity is explained by **routing**.
Observed against published workflow **version 13**.

---

## P08C — `inquiry_count` null safety on a pre-P07 contact

**Not a TC row.** This closes the gap
[`../ghl-setup.md`](../ghl-setup.md) build rule 3 recorded as *"known,
unclosed"*: `Math Operation` running on a field nothing had ever written.

**The change (GHL v12 → v13).** On the `Opportunity Found` branch the bare
`Math Operation` was replaced by an `If/Else` on the contact field
`Inquiry Count`:

- `Inquiry Count is empty` → `Set Inquiry Count = 2`
- else → `Increment Inquiry Count` (+1), then a **Go To** back to the existing
  `Recheck Open Opportunity`

Both arms converge on the same second `Find Opportunity` and the same
`Follow-up → Contacting` gate, so a historical contact and a post-P07 contact
get identical stage treatment. The `Opportunity Not Found` branch,
`Create Opportunity`, its `Duplicate Opportunity: Disabled` toggle, the tag and
the note were all left untouched. `get-workflow` read `version: 13`,
`status: published` afterwards — the only machine-checkable proof a GHL UI edit
shipped.

**Why `2` and not `1`.** A contact that already holds an open opportunity has
by definition inquired at least once before; writing `1` on the second inquiry
would under-count it.

**Input.** `Marisol Vega` (`qCgLyA0I…`) — created 2026-08-09
04:31:09Z, therefore pre-P07. **Pre-state read live, not assumed:**
`customFields` held only `service_interest` and `lead_message`, with **no
`5cawDbnm…` entry at all** — `inquiry_count` genuinely unset, not
zero; `tags: []`; **zero** notes; exactly one open Opportunity
`BmoXWNiS…` in `LeadFlow Demo Pipeline`. One browser-driven
submission at `03:21:15Z` with the **same** email and phone and a **different**
intent — `Mortgage` instead of `Real Estate`, and a new message.

**Actual.**

| Assertion | Observed |
|---|---|
| One contact | `total: 1` — same `qCgLyA0I…`, `dateAdded` unchanged at `2026-08-09T04:31:09.061Z` |
| One opportunity, same identity | `total: 1` — `BmoXWNiS…`, `createdAt` **and** `updatedAt` still `2026-08-09T04:31:10.669Z`, `status=open` |
| `inquiry_count = 2` | `{"id":"5cawDbnm…","value":2}` — written where nothing existed |
| `repeat-inquiry` | `tags: ["repeat-inquiry"]` |
| One new note | **0 → 1** — `m1CAZWSN…` at `03:21:26.177Z`, carrying `Service Interest: Mortgage` and this submission's message verbatim |
| Zero new opportunity | Opportunity count for the contact unchanged at 1 |
| Zero webhook / zero n8n execution | Ingress executions stayed at **24**, latest still id `42` — no opportunity created, so no `Opportunity Created` webhook |

Exactly one form submission was recorded (`55bd7f61…`, `03:21:22.260Z`), so the
two writes above came from one run, not two.

**This is the `empty` arm, unambiguously.** The field had no entry before the
run and held `2` after it. An `Increment` on an unset field could not have
produced `2`.

**Two things this run does not prove.** The `Follow-up → Contacting` gate was
**not** exercised — the opportunity sat in `New Lead`, so the second
`Find Opportunity` (filtered to `Follow-up`) returned `Not Found` and left the
stage alone, `lastStageChangeAt` unchanged. That is the correct behaviour and
it is the `Not Found` arm, which had been designed-but-unobserved since P07; it
is now observed, on the `empty` path only. And the **Go To** on the `else` arm
was unexercised at the time of this run: nothing had yet entered the `Increment`
branch since v13 shipped. **TC-03's re-run closed that same night** — see
[TC-03](#tc-03--genuine-re-inquiry-same-person-different-intent), where
`inquiry_count` went `1 → 2` and the stage still came back from `Follow-up`.

**`Marisol Vega` is consumed** as a null-safety fixture — her `inquiry_count`
is now `2`. Re-running this needs another pre-P07 contact with an open
opportunity and no `inquiry_count`; `David Demo`, `Sofia Bennett`,
`Camila Torres`, `Camila Torres 02`, `Tobias Lind` and `Valeria Cruz` all still
qualify.

---

## Which artifact each of these passes was observed against

A passing test proves the version it ran against, not the version currently
deployed.

| Evidence | When (UTC) | Active version then |
|---|---|---|
| TC-01, execution 6 | 05:30 | `b162ad3f` |
| **TC-03, both submissions** | 17:21 and 21:49 | n8n unchanged (`cellFormat: RAW` fix, no P07 edit); **GHL** `Form to Opportunity` **v12** |
| **TC-03 — re-run** | 2026-08-10 04:13 and 04:15 | **GHL `Form to Opportunity` v13.** Two browser-driven submissions on the new fixture `Rafael Okonkwo`, 98 s apart, with an MCP drift step to `Follow-up` between them. The first run against v13 to take the **`Increment`** arm and therefore the only observation of the **`Go To`**. n8n active `4ab773e2` and untouched by submission 2 — the count moved once, on submission 1 |
| **TC-02b — re-run** | 2026-08-10 03:29 | **GHL `Form to Opportunity` v13.** Two browser-driven submissions of the public form, 4.3 s apart. The original pre-P07 run against **v9 with `Allow Re-entry` off** is retained above for its attribution lesson and covers nothing deployed |
| **P08C `inquiry_count` null safety** | 2026-08-10 03:21 | **GHL v13**, the first run against it. n8n untouched and unexercised — the whole point is that a re-inquiry fires no webhook |
| **TC-01 — fully re-covered by TC-02b's submission 1** | 2026-08-10 03:29 | TC-01's own run (05:30 on 2026-08-09) predates both GHL v12 and v13, and faced the same demotion as TC-02b. It is **not** demoted, and the reason is narrower than "it still passes". TC-01's GHL-side assertions ride on the `Not Found` branch, which neither v12 nor v13 touched, and TC-02b's first submission re-observed both at **v13**: a new Contact, and an Opportunity created at `New Lead`. Its n8n-side assertions were re-observed in the same run, on the current active version `4ab773e2` — **execution 72** ran `Sheets: leads_backup` once with one item (`lastAction=backup_written`, `status=processed`, `attempt=1`), `Ledger: Complete` wrote ledger row id 19 `status=completed`, and the last node executed was `Respond 200 processed` with `correlationId=n8n:72`, `outcome=processed`, `eventId=ghl:opportunity-created:vX04hv8q…`. This supersedes the earlier partial re-coverage by TC-03's submission 1, where execution 12 was recorded only as `status=success` with no node record captured |

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
