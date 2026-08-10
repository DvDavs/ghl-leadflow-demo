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

| File | Shows | Verified |
|---|---|---|
| `01-ghl-contact-opportunity.png` | The CRM pipeline board — the two rehearsal leads (`Emeka Nwosu`, `Anouk Delacroix`) sitting in `New Lead` with `Source: GHL Demo Form`, alongside the two re-inquiry fixtures in `Contacting`. This is the golden path's CRM half: one Contact, one Opportunity, correct stage | Read visually — no ids, no URL bar, notification banner and profile menu masked before capture. Binary-scanned clean for the location id, Sheet id, form id, workflow id, instance host and agency name |

## Not captured — blocked, with the reason

Four of the five planned captures need an authenticated browser session that
the automation profile does not have. The Playwright profile is signed in to
**GoHighLevel only**; n8n Cloud and Google both redirect it to a sign-in page.

Supplying those credentials to the automation is not something to improvise, so
the captures were left undone rather than faked. **No screenshot in this
directory is a mock-up, and none will be** — a rendered stand-in that looks
like a product screenshot would be indistinguishable from evidence, and this
repository does not do that.

| Planned | Needs | Where the evidence lives meanwhile |
|---|---|---|
| `02-n8n-execution-200-processed` | n8n Cloud session | [`docs/evidence/n8n-reliability-tests.md`](../../docs/evidence/n8n-reliability-tests.md) |
| `03-leads-backup-correlation` | Google session | [`docs/evidence/n8n-reliability-tests.md`](../../docs/evidence/n8n-reliability-tests.md), and the internal evidence-reader workflow, which reads the same tabs with no browser at all |
| `04-retry-needs-human` | Google session | [`docs/evidence/n8n-reliability-tests.md`](../../docs/evidence/n8n-reliability-tests.md) — TC-10, TC-11, TC-12 |
| `05-reconciliation` | n8n Cloud session | [`docs/evidence/reconciliation-tests.md`](../../docs/evidence/reconciliation-tests.md) |

Closing this needs one manual step, tracked for **P09B**: sign the Playwright
MCP browser profile in to n8n Cloud and to the Google account holding the backup
sheet, then leave the tabs open. The same step unblocks the recorded video
fallback, which is blocked on exactly the same sessions.
