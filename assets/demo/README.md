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
   workflow id, credential id, agency name, account email, or avatar initials.
   Mask the element before capturing, not after.
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
| `05-reconciliation.png` | The sweep, `Published`, execution `ID#59`. The node graph carries the whole story: `Every 10 Minutes` → `GHL: Recent Opportunities` → `Ledger: Look Up Candidate` → `Needs Recovery?`, splitting **1 recovered** into `Sheets: leads_backup (recovered)` and **9 already known** into `Already Known - Skip`. The execution list on the left shows the 10-minute cadence | Read visually — all 20-character record ids truncated before capture; trial banner masked. The `GHL: Recent Opportunities` node shows a truncated public API host with no path and no token |

## Not captured — blocked, with the reason

**Two of five, plus the video.** They need a Google session, and the browser
Playwright drives does not have one.

This is worth stating precisely, because it was misdiagnosed once: the
Playwright MCP server drives **its own browser instance with its own profile**.
Signing in to n8n or Google in an everyday Chrome window does nothing for it.
The logins have to happen in the window Playwright is driving.

Nothing was faked to fill the gap. **No screenshot in this directory is a
mock-up, and none will be** — a rendered stand-in that looks like a product
screenshot would be indistinguishable from evidence, and this repository does
not do that.

| Planned | Blocked on | Where the evidence lives meanwhile |
|---|---|---|
| `03-leads-backup-correlation` | Google session | [`docs/evidence/n8n-reliability-tests.md`](../../docs/evidence/n8n-reliability-tests.md), and the internal evidence-reader workflow, which reads the same tabs with no browser at all |
| `04-retry-needs-human` | Google session | [`docs/evidence/n8n-reliability-tests.md`](../../docs/evidence/n8n-reliability-tests.md) — TC-10, TC-11, TC-12 |
| Recorded video fallback | Two things, not one | — |

**The video has a second blocker that a login will not clear.** Playwright
records video as a *browser-context creation option*; the MCP server owns
context creation and exposes no recording tool, so a session already in flight
cannot start recording. Opening a fresh recorded context would start with no
cookies — logged out of everything, which defeats the purpose. Producing it
needs either a recording-enabled MCP configuration or an ordinary screen
recorder driven by a human.

Both remaining items are tracked for **P09B**.
