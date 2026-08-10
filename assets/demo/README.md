# Demo assets

Fallback captures for the live walkthrough in
[`docs/demo/runbook.md`](../../docs/demo/runbook.md). Every screenshot here is a
page capture with **no browser chrome and therefore no URL bar**, taken against a
throwaway sub-account with fictional data only. The one video is assembled from
those same five captures and adds no imagery of its own.

## Capture rules

These are release gates, not guidelines. No secret scanner reads pixels.

1. **Fictional data only.** Fictional names, `example.com` addresses, and
   `555-01xx` phone numbers.
2. **No URL bar, ever.** Page screenshots only — never a window or desktop
   capture.
3. **Nothing identifying on screen:** no location id, webhook path, Sheet id,
   workflow id, credential id, account email, avatar, or **the real agency
   name that owns the sub-account**. Mask the element before capturing, not
   after. The *fictional* demo business — `Northstar Demo Services`, Austin TX —
   is deliberately exempt and appears in `01`: it is invented, it is already
   named throughout the repository, and it is what makes the board legible as
   a CRM rather than an anonymised rectangle.
4. **Raw captures are never committed.** They are written to the gitignored
   Playwright scratch directory, inspected, and only then copied here.
5. **Every file is inspected twice** — read visually to enumerate what is
   actually rendered, and scanned as a binary for known sensitive strings.

## Captured

Record identifiers are **truncated to eight characters in the pixels**, before
the shot, matching the `vX04hv8q…` convention the evidence files already use.
The redaction is visible as a redaction; it is not a crop that hides that
something was removed.

| File | Shows | Verified |
|---|---|---|
| `01-ghl-contact-opportunity.png` | The CRM pipeline board — the two rehearsal leads (`Emeka Nwosu`, `Anouk Delacroix`) sitting in `New Lead` with `Source: GHL Demo Form`, alongside the two re-inquiry fixtures in `Contacting`. The golden path's CRM half: one Contact, one Opportunity, correct stage | Read visually — no ids, no URL bar; notification banner and profile menu masked before capture |
| `02-n8n-execution-200-processed.png` | One execution, `ID#83`, `Succeeded in 5.994s`, with the log panel open on `Respond 200 processed` — `Success in 3ms` — and its output row: `correlationId n8n:83`, the matching `eventId`, `step complete`, `status ok`, `attempt 1`, **`outcome processed`**. The correlation chain and the response contract in one frame | Read visually — contact and opportunity ids truncated in the DOM before capture; trial banner masked; no account email, no webhook URL (no node was opened) |
| `03-leads-backup-correlation.png` | The `leads_backup` tab, all nineteen rows: one row per event, with `correlationId` fully legible (`n8n:6` … `n8n:83`, and `n8n:sweep:45` / `n8n:sweep:59` on the reconciled ones), fictional names, `example.com` addresses and `555-01xx` numbers. The two rehearsal rows are the last two. All three tabs — `leads_backup`, `run_log`, `needs_human` — are visible at the bottom | Read visually — the Drive storage banner and the document title bar (and with it the account avatar) removed before capture; `eventId`, `contactId` and `opportunityId` covered by opaque bars leaving ~8 characters; the formula bar, which surfaced a full id when a cell got selected, covered as well |
| `04-retry-needs-human.png` | The `needs_human` tab and its terminal handoff row, with the full reason in the formula bar — *"leads_backup write failed on all 3 attempts: injected downstream failure…"* — alongside `correlationId n8n:31`, `status open`, `owner unassigned`, `lastAction retry_exhausted`. Both halves in one frame: the ladder ran three times, and a human owes an answer | Read visually — every identifier in this row is synthetic (`p08-tc12b-…`), so nothing needed redaction. No document title, no avatar, no URL bar |
| `05-reconciliation.png` | The sweep, `Published`, execution `ID#59`. The node graph carries the whole story: `Every 10 Minutes` → `GHL: Recent Opportunities` → `Ledger: Look Up Candidate` → `Needs Recovery?`, splitting **1 recovered** into `Sheets: leads_backup (recovered)` and **9 already known** into `Already Known - Skip`. The execution list on the left shows the 10-minute cadence | Read visually — all 20-character record ids truncated before capture; trial banner masked. The `GHL: Recent Opportunities` node shows a truncated public API host with no path and no token |

**Nothing in this repository has ever committed a full 20-character record id**,
in text or in pixels. The redactions above hold that line rather than decorate
it.

**The spreadsheet was never edited.** Two interactions touched it: switching
sheet tabs, and typing a cell reference into the name box to select `F2` so its
full text would show in the formula bar. No cell was opened for editing and no
column was resized — widening a column to fit the text would have been a write
to a shared document.

## The video

`06-fallback-evidence-walkthrough.mp4` — 1920×1080, H.264 High, `yuv420p`,
faststart, **no audio**, **2 min 16 s**, 3.4 MB. Container metadata stripped
(`-map_metadata -1`).

It is the five captures above, sequenced in narrative order and captioned: a
lead lands in the CRM, n8n processes the webhook, the backup correlates the
event, retry exhausts into `needs_human`, and reconciliation recovers the one
opportunity it had never seen while skipping the nine it already knew. It closes
on the four limitations that have to be said out loud — sequential evidence and
no concurrency claim, the duplicate-opportunity guard configured but never
exercised, re-inquiries producing no downstream event, and fictional fixtures on
a trial sub-account.

**It is a captioned still sequence, and its own title card says so.** It is not
a screen recording and does not pretend to be one: nothing moves, no cursor
travels, no interface is simulated or re-drawn. Every evidence pixel comes from
the five PNGs above at full size — no zoom or crop that could hide that a
redaction happened, and the bars stay visible *as* bars.

**Provenance is on the card, not implied.** Captures 1–3 are the rehearsed
golden path; captures 4 and 5 are earlier recorded failure and recovery runs.
An earlier draft of the closing card claimed all five came from the two
rehearsals — an adversarial review caught it and it was corrected before the
file was committed.

**Reach for it when the live run dies** — a lost SaaS session, a CRM board that
renders blank, an execution list that stays empty. It carries the whole argument
in about two minutes.

Built with FFmpeg from those five PNGs and nothing else: no external asset, no
stock footage, no mock-up. Verified after encoding by probing the stream,
extracting frames across the full timeline, reading every caption and header
band, inspecting the redacted regions at 2–3× zoom, scanning the container for
sensitive strings, and a full decode pass.

## Nothing here is a mock-up

**No screenshot in this directory is a mock-up, and none will be** — a rendered
stand-in that looks like a product screenshot would be indistinguishable from
evidence, and this repository does not do that. The video inherits the rule: it
sequences real captures, it does not draw new ones.

## Why there is no continuous screen recording

The note below is why the fallback is a still sequence rather than a screen
capture of a live run. It was misdiagnosed once, so the cause is recorded rather
than the symptom.

The Playwright MCP server drives **its own browser instance with its own
profile**. Signing in to a service in an everyday Chrome window does nothing
for it; the login has to happen in the window Playwright is driving. An earlier
draft of this file recorded the blocker as *"the profile is signed in to
GoHighLevel only"*, which named the symptom and not the cause.
