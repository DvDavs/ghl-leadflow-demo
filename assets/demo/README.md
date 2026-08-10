# Demo assets

Fallback captures for the live walkthrough in
[`docs/demo/runbook.md`](../../docs/demo/runbook.md). Every file here is a page
screenshot with **no browser chrome and therefore no URL bar**, taken against a
throwaway sub-account with fictional data only.

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

## Not captured — the video

**Blocked on something a login does not fix.** Playwright records video as a
*browser-context creation option*. The MCP server owns context creation and
exposes no recording tool, so a session already in flight cannot start
recording, and opening a fresh recorded context would start with no cookies —
logged out of everything, which defeats the purpose. Producing it needs either
a recording-enabled MCP configuration or an ordinary screen recorder driven by
a human. Tracked for **P09B**.

Nothing was faked to fill the gap. **No screenshot in this directory is a
mock-up, and none will be** — a rendered stand-in that looks like a product
screenshot would be indistinguishable from evidence, and this repository does
not do that.

## A note on the browser, because it was misdiagnosed once

The Playwright MCP server drives **its own browser instance with its own
profile**. Signing in to a service in an everyday Chrome window does nothing
for it; the login has to happen in the window Playwright is driving. An earlier
draft of this file recorded the blocker as *"the profile is signed in to
GoHighLevel only"*, which named the symptom and not the cause.
