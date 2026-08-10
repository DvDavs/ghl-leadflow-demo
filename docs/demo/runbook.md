# Demo runbook

The script for a 5–7 minute live walkthrough, the fallback for every system
that can fail during it, and the checklist that runs ten minutes before.

Read with [`one-page.md`](one-page.md), which is the summary to leave behind.

---

## Rehearsal record

Two golden paths were run end to end on 2026-08-10, browser-driven, with no
human filling a form and no human correcting anything.

| | Rehearsal 1 | Rehearsal 2 |
|---|---|---|
| Fixture | `Anouk Delacroix`, Real Estate | `Emeka Nwosu`, Business Loan |
| Pre-state | 0 matches on surname, email, phone | 0 matches on surname, email, phone |
| Contact | exactly 1, `VBNnzv0L…` | exactly 1, `VszU2txs…` |
| Opportunity | exactly 1, `5DUHlPTa…` | exactly 1, `mn7CL40N…` |
| Stage | `New Lead` | `New Lead` |
| `inquiry_count` | `1` | `1` |
| n8n execution | `81` — `outcome=processed`, last node `Respond 200 processed` | `83` — `outcome=processed`, last node `Respond 200 processed` |
| Ledger | row 21, `completed` | row 22, `completed` |
| `leads_backup` | exactly 1 new row (18 → 19), read back from the sheet | exactly 1 new row (19 → 20), read back from the sheet |
| Correlation | `eventId` = `ghl:opportunity-created:5DUHlPTa…`, `correlationId n8n:81`, same `contactId` in GHL and in the sheet | `eventId` = `ghl:opportunity-created:mn7CL40N…`, `correlationId n8n:83`, same `contactId` in GHL and in the sheet |
| Form click → ledger `completed` | **~17 s** | **~17 s** |
| Human intervention | none | none |

The row count was **read back from the sheet** by the internal evidence reader
after each run, not deduced from the node output. The stage was confirmed by
resolving the pipeline stage id, not by trusting the label in the payload.

**One thing to know before you submit.** Rehearsal 1 opened the public form and
found a *"Submission in progress — you have an unfinished submission"* prompt
left over from an earlier session, with **Start over** and **Continue**. Take
**Start over**. Continue resumes stale field values, and on a shared screen you
will not notice until the CRM shows the wrong name.

---

## The demo — 5 to 7 minutes

Budget 6 minutes of speaking and keep the last minute in reserve. Every
"expected" below was observed in both rehearsals.

| Min | Action | Expected on screen | Say |
|---|---|---|---|
| **0:00** | Nothing. Two tabs visible: the public form, the CRM pipeline. | Pipeline board, `New Lead` column | "A home-services business buys leads. Each one decays by the hour — first caller usually wins. The demo is not that a lead arrives; it is that the pipeline stays correct when the input misbehaves." |
| **0:30** | Fill the form live with a fresh fictional lead. Submit. | Turnstile pause, then the thank-you panel | "There is a Cloudflare challenge in front of this form. It takes a few seconds and it is not mine to skip — I will talk over it." |
| **1:00** | Switch to the CRM pipeline and refresh. | One new Contact, one Opportunity in `New Lead`, `Source: GHL Demo Form` | "One contact, one opportunity, stage `New Lead`. The CRM created both before my automation saw anything — that matters in a minute." |
| **1:30** | Switch to the n8n execution list. | One new execution, `success` | "The CRM fired one webhook. One execution. Validate, authorize, claim, write, respond." |
| **2:00** | Open the execution; point at the final node. | `Respond 200 processed`, `correlationId n8n:<id>` | "It answers `200 processed` and carries a correlation id end to end. Every hop logs that id, so 'did we ever receive it' is answerable." |
| **2:30** | Switch to `leads_backup`. | Exactly one new row, same `eventId` and `contactId` | "One row. Same event id, same contact id as the CRM. From form to durable backup: about seventeen seconds." |
| **3:00** | **Duplicate / re-inquiry.** Show the `repeat-inquiry` tag and `inquiry_count = 2` on an existing contact. | Tag, counter, one note, one opportunity | "Same person inquires again. No second contact, no second opportunity — the existing one is *amplified*: a tag, a counter, a note with the new intent. And I will tell you what this costs, because it does cost something." |
| **3:45** | **Retry and human handoff** — from recorded evidence, not live. Open `docs/evidence/n8n-reliability-tests.md` (TC-10/TC-11/TC-12) and the `needs_human` tab. | `202 retry_scheduled`, one converged row, then the terminal case: ledger `failed` + `needs_human` row | "Break the downstream write and the caller gets `202 retry_scheduled` — not a lie, not a `200`. The execution sleeps in the database, three attempts, 70 seconds doubling with jitter, capped at 300. If it clears, exactly one row. If it doesn't, a terminal `failed` plus a `needs_human` row with a reason and an owner. Failure is a state I reach on purpose." |
| **4:45** | **Reconciliation.** Open the sweep's execution history. | Scheduled runs every 10 minutes; the run that recovered six, and the next that wrote nothing | "Retry cannot help you when *nothing arrived*. A sweep runs every ten minutes, asks the CRM for recent opportunities, and asks my own ledger which of them it has never seen. Its first live run found six real orphans and recovered all six. Running it again wrote nothing at all." |
| **5:30** | Stay on the sweep. | — | "That run also failed at something, and it is the better story: its log wrote every recovery three times. The write was landing and *then* failing. I fixed it by making the log write idempotent instead of switching the retry off — and proved it under the same failure." |
| **6:00** | Close. | — | Limitations, below. Then: "Everything I just claimed maps to a row in `TEST_CASES.md`, and every row names the artifact version it was observed against." |

**If you are running long, cut in this order:** minute 5:30 (the log defect
story), then 3:00 (duplicate). Never cut 3:45 or 4:45 — retry and
reconciliation are the reason this demo exists.

---

## Stating the limitations out loud

Say these. A limitation you volunteer reads as engineering judgement; the same
limitation found by the interviewer reads as a gap you missed.

- **On concurrency:** "Everything I have shown you is sequential. My closest
  attempt at a concurrency test missed by 4.3 seconds, measured twice, because
  the form's bot challenge serialized the two submissions. So I can tell you
  this is duplicate-*safe* at four seconds. I cannot tell you it is
  concurrency-safe, and I am not going to."
- **On the duplicate guard:** "There is a native duplicate-opportunity guard
  behind this and it has never once fired in my tests. The window where it
  could is under 1.5 seconds and the browser cannot get inside it. It is
  documented, not evidenced, and those are different words."
- **On re-inquiries:** "A second inquiry creates no opportunity, so it fires no
  webhook and writes no backup row. My reconciliation sweep structurally cannot
  see that — it looks for opportunities with no backup row, and here there is
  no opportunity at all. Both quick fixes make it worse, so it is deliberately
  open."
- **On an accidental double submission:** "I cannot distinguish it from a
  genuine re-inquiry, because the CRM gives me no submission id. I chose to
  treat both as real. A visible duplicate is recoverable; a swallowed hot lead
  is not."
- **On the unexplained failure:** "One thing in the reliability story has no
  named cause. A sheet write was committing and then reporting failure. I made
  it converge instead of understanding it. That is a fix-around, and I would
  want to close it properly."
- **On what is not built:** "Four-service routing, appointment booking, and AI
  enrichment are designed and diagrammed. They are not built and I will not
  show you a slide that implies otherwise."

---

## Fallback, by system

Every fallback assumes the pre-interview checklist ran. Decide fast — say what
broke, switch, keep going. Narrating a recovery is not a loss.

| If this breaks | Symptom | Do this |
|---|---|---|
| **Internet / any SaaS session** | A tab shows a sign-in screen | Stop live driving. Play `assets/demo/06-fallback-evidence-walkthrough.mp4` — 2:16, the whole argument — and say: "I'll show you the recorded evidence; the live run needs a session I've just lost." Call it what it is: captioned captures, not a screen recording. |
| **Everything visual is gone but you can still talk** | Screen share survives, every SaaS tab is dead | The video is the floor. It carries lead → webhook → correlation → exhausted retry → reconciliation, and states the limitations itself, so you can narrate over it instead of reconstructing from memory. |
| **The public form** | Submit spins past ~15 s, or Turnstile loops | Do not resubmit — a second submit on a cleared challenge produces a real second submission. Switch to the CRM and open a lead created in rehearsal; the whole downstream story is identical. |
| **The form resumes stale data** | "Submission in progress" prompt appears | Click **Start over**. Never **Continue**. |
| **The CRM board renders blank** | Sidebar and header paint, the pipeline area is empty | Full page reload — not an in-app tab click — and wait. Under automation the board took ~25 s and collapsed again afterwards; a human reload is usually enough. If it stays blank, use the CRM's Contacts list instead, which is a different render path. |
| **The CRM shows the wrong contact** | The lead you submitted is not there | Check the fixture did not collide with an existing contact on **email, phone, or surname**. A collision routes the submission down the re-inquiry branch — which fires no webhook. Say so, and pivot to the re-inquiry segment early; it is the same behaviour, just arrived at accidentally. |
| **n8n execution list is empty** | The submission succeeded, no execution appeared | Give it 20 s before calling it. Then check the workflow is still **active** and that no editor tab is open holding a draft. If it is genuinely down, switch to `docs/evidence/n8n-reliability-tests.md` — every claim in minutes 1:30–2:30 has a recorded observation there. |
| **The backup sheet will not open** | Google session expired | Use the internal evidence-reader workflow, which reads the same three tabs without a browser session, or the recorded rows in the evidence files. |
| **The reconciliation sweep shows nothing new** | Expected — it has nothing to recover | This is the correct outcome and it is worth saying: "It ran and wrote nothing, because nothing was missing. That is the second half of the test." Show the earlier run that recovered six. |
| **Everything is down** | — | The one-pager plus `TEST_CASES.md` carries the entire argument. Talk through the architecture diagram and the decision log. The design reasoning is what is actually being assessed. |

---

## Pre-interview checklist — 10 minutes

Run this in order. It is written to be done in ten minutes and it assumes
nothing is already open.

**Sessions and tabs (4 min)**

1. Open exactly five tabs, in demo order: the public form, the CRM pipeline
   board, the n8n **execution list** (not the editor), the backup sheet, the
   reconciliation sweep's execution list.
2. Confirm each one is *signed in* — load it, do not trust the tab title.
3. **Close every n8n workflow *editor* tab.** An open editor autosaves into the
   draft, and a publish or a reactivate ships whatever the draft drifted into.
   This has already cost this project a known-good active version once.
4. Turn off notifications, and put the browser in a clean window with no
   bookmarks bar and no unrelated tabs.

**State (3 min)**

5. Confirm the ingress workflow and the reconciliation sweep are both
   **active**, and record the active version of each. If a version changes
   mid-demo you want to know it was you.
6. Confirm the operator fault switch's **last** row is `mode: off`. It is
   append-only — the last row wins. If it is armed, the golden path fails on
   stage.
7. Note the current `leads_backup` row count. "Exactly one new row" is only a
   claim if you knew the number before.

**Fixture (2 min)**

8. Invent one fresh fictional lead and check **zero matches on surname, email,
   and phone**. Use a phone number well away from the existing `202-555-01xx`
   block — `415-555-01xx` was used for both rehearsals and stayed clear.
9. Open the public form and, if the *"Submission in progress"* prompt appears,
   clear it now with **Start over** so it cannot appear on stage.

**Assets (1 min)**

10. Confirm `assets/demo/` opens and the screenshots are current, and have
    `docs/evidence/` and `one-page.md` reachable in one click. **Open
    `06-fallback-evidence-walkthrough.mp4` in a player and leave it paused on
    the title card** — a fallback you have to go hunting for during a failure is
    not a fallback.

---

## Related

- [`one-page.md`](one-page.md) — the leave-behind summary
- [`../../assets/demo/`](../../assets/demo/) — the five fallback captures and
  the 2 min 16 s walkthrough video, with the rules they were held to
- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix every claim maps to
- [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) — current state and open risks
- [`../evidence/`](../evidence/) — observed output behind every passing row
- [`../n8n/operations.md`](../n8n/operations.md) — retry budget, reconciliation, known limits
