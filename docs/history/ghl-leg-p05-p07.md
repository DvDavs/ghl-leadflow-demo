# History — the GoHighLevel leg (P05, P07)

How the CRM half was built: the pipeline, form and workflow in P05, and the
genuine re-inquiry branch in P07 — including the retraction P07 forced on an
already-passing test.

This is the historical record. Current state lives in
[`../../PROJECT_STATE.md`](../../PROJECT_STATE.md); do not read this file to
find out what is true today.

Sibling milestones: [foundation (P01–P04)](foundation-p01-p04.md) ·
[n8n leg (P06, P08)](n8n-leg-p06-p08.md)

---

## P05 — the GHL tramo, built and proven

Form → Contact → Opportunity → Pipeline runs live. 7 P0 custom fields, 5 P0
tags, the `LeadFlow Demo Pipeline` (7 exact stages), the
`LeadFlow Demo — Service Inquiry` form, and the
`LeadFlow Demo — Form to Opportunity` workflow all exist and are published.
Custom fields and tags were created via MCP; pipeline, form, and workflow are
UI-only — confirmed by exhaustive registry search, no write operation exists
for any of the three (see [`../ghl-setup.md`](../ghl-setup.md) "Registry gaps
confirmed live").

**Trial location identity — partially sanitized.** Location/business name
fields are fictional (`LeadFlow Demo` / `Northstar Demo Services`). David
explicitly approved leaving the pre-existing email, phone, website, and address
as-is rather than requiring full fictional replacement. This is a deliberate
scope decision, not an oversight.

The business contact fields (email, phone, address, city, state, postal,
country) were later made fictional. **The owner's `firstName`/`lastName` are
still real** in `get-location`. Three UI correction requests did not fix it —
likely a different settings screen (team/user profile, not Business Profile)
than the one already fixed for email, phone and address. Not committed to git
and not part of the interview-facing fixture, so not blocking, but still open.

**Three build defects surfaced by TC-02b's first attempt**, all three fixed and
re-verified before the final run: email not mapped to the standard attribute,
the form builder forking two duplicate custom fields instead of reusing the P0
set, and an Opportunity name left as unresolved placeholder text. The broken
interim contact/opportunity and the orphaned duplicate fields were deleted
before the final run. See [`../ghl-setup.md`](../ghl-setup.md) "Gotchas".

**Opportunity-side P0 guard — a different mechanism than ADR-002 planned.**
GHL's native duplicate-opportunity block (location setting + workflow-action
toggle) is confirmed configured. It is person-scoped, not event-scoped, so it
does not close the gap ADR-002 originally described — see
[ADR-002](../decisions/ADR-002-idempotency-strategy.md) "Consequences to watch".

## P07 — the genuine re-inquiry branch

`LeadFlow Demo — Form to Opportunity` now opens with a `Find Opportunity` step
scoped to `Status = open` on the demo pipeline. `Not Found` is the untouched
original path plus `inquiry_count = 1`; `Found` applies `repeat-inquiry`,
appends an internal note carrying the new intent, increments `inquiry_count`,
and pulls the opportunity back to `Contacting` — gated by a second
`Find Opportunity` filtered to `Follow-up`, so that a lead sitting at
`Qualified` is not dragged backwards. Built in the UI (workflows remain
write-less over MCP), published as **version 12**, and proven by **TC-03** with
live MCP reads.

**What TC-03 did not exercise:** the `Not Found` arm of that second step — the
arm that actually protects a `Qualified` or `Appointment` deal — is designed and
published but unobserved.

Procedure, scope limits and rejected alternatives in
[`../ghl-setup.md`](../ghl-setup.md).

### The retraction P07 forced

**TC-02b was demoted twice over, and the reasoning is the point.**

First, its attribution to the duplicate-opportunity guard is **retracted**.
Building the TC-03 branch required enabling `Allow Re-entry`, which means it was
**off** when TC-02b ran — so the second submission never re-entered the workflow
at all, `Create Opportunity` never ran a second time, and the guard was never
exercised. "The guard blocked it" and "the action never ran" produce
byte-identical output. The captured evidence cannot separate them.

Second, the GHL workflow it ran against **no longer exists** (v9 → v12). A pass
proves the artifact it ran against and nothing later.

The general lesson, recorded because it shaped TC-03's design: **a negative
outcome is weak evidence**, so TC-03 asserts positive artifacts instead. Full
evidence and both demotions in
[`../evidence/ghl-tests.md`](../evidence/ghl-tests.md).

### A trap P07 discovered

**A GHL workflow edit can sit unpublished, exactly like an n8n one.** P07 read
`version: 9` after the branch was reported built, and `12` after it was
published. `get-workflow` exposes no step detail, so **the version number is the
only machine-checkable proof a UI edit shipped**. Always re-read it before
executing a test against the change.

## Readability gaps this leg left open

**The Opportunity name is a snapshot from creation time.** After the TC-03
re-inquiry the contact's service interest reads `Mortgage` while the opportunity
is still named `... - Real Estate`. A rep sees the original intent on the board
and the new one only in the note. Left as-is deliberately — renaming would
overwrite the deal's own identity — but it is a real readability gap worth
naming before a demo walkthrough.

**`Sofia  Bennett - Real Estate` carries a double space**, so the Opportunity
Name merge template has a spacing defect. Cosmetic, unfixed.

## Related

- [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) — current state
- [`../ghl-setup.md`](../ghl-setup.md) — how the GHL leg is built, its gotchas and scope limits
- [`../evidence/ghl-tests.md`](../evidence/ghl-tests.md) — TC-01, TC-02b, TC-03 evidence
- [`../decisions/ADR-002-idempotency-strategy.md`](../decisions/ADR-002-idempotency-strategy.md) — identity and dedup strategy
</content>
