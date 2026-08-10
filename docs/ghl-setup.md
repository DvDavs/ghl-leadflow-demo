# GoHighLevel setup — MCP OAuth access

Reproducible checklist for connecting Claude Code to the official HighLevel MCP
server and scoping it to a single disposable trial sub-account. Contains no
secrets, tokens, or account/location identifiers.

## Method chosen: OAuth, not a Private Integration Token

The developer portal documents OAuth as available and recommended for the v2
MCP endpoint, exposing a broader scope set than a PIT. See
[`integration-options.md`](integration-options.md) §1. A PIT was **not**
created for this setup.

## Endpoint

```
https://services.leadconnectorhq.com/mcp/anthropic/v2
```

Configured in the repo's `.mcp.json` as a project-scoped HTTP MCP server named
`leadconnector`. `.mcp.json` holds only `{ "type": "http", "url": "..." }` —
never a token, header, or location id.

## Steps

1. Add the server (project scope, URL only):

   ```
   claude mcp add --transport http leadconnector https://services.leadconnectorhq.com/mcp/anthropic/v2 -s project
   ```

2. Approve the project-scoped MCP server. A freshly added or changed
   `.mcp.json` server is not trusted automatically — run `claude` inside the
   repository directory and accept the trust prompt for `leadconnector`
   before it will connect.

3. Authenticate:

   ```
   claude mcp login leadconnector
   ```

   This opens the HighLevel authorization screen in a browser. **Select only
   the disposable trial sub-account** — do not grant agency-wide access or
   select any other sub-account. Approve the narrowest scope group the
   screen offers for: Contacts, Opportunities (view), Custom Fields (view),
   and Locations (view). Decline Forms edit, Conversations, Messages,
   Payments, and Calendars unless a later phase specifically requires them.

4. Verify:

   ```
   claude mcp list
   ```

   `leadconnector` should show `✔ Connected`.

## Isolation check (run this before anything else)

Call the `list_locations` operation immediately after connecting. It must
return **exactly one** location — the trial sub-account. If it returns more
than one, or an agency-level result, revoke and re-authorize before issuing
any other call:

```
claude mcp logout leadconnector
claude mcp login leadconnector
```

## Capability discovery

Use the meta-toolset rather than assuming coverage — the effective catalog is
grant-dependent:

- `search_operations` — discover operations by keyword/area.
- `describe_operation` — inspect an operation's parameter schema before
  calling it.
- `execute_operation` — the only way to actually call a discovered operation.

Never treat "operation discovered" as "operation works." Confirm each
capability by executing it once, or by schema inspection when a live call
would require building scope-excluded resources (see
[`integration-options.md`](integration-options.md) §5 for the classification
of what was actually confirmed).

## Revocation

To fully remove access:

```
claude mcp logout leadconnector
claude mcp remove leadconnector -s project
```

Revoking in the HighLevel marketplace/app-authorization settings on the
sub-account side also invalidates the grant immediately, independent of the
local CLI state.

## What must never appear in this repository

- Access or refresh tokens.
- The trial location's location id or account id.
- Authorization headers of any kind.
- Real contact, business, or personal data — fixtures are fictional only
  (`@example.com` emails, `+1 202-555-01xx` phones, names containing a
  `P04 Capability Probe`-style marker for anything created during capability
  verification).

## Registry gaps confirmed live (P05)

Checked by exhaustive `search_operations` queries, not assumption — none of
these have a write (or, for the first one, any) operation in the connected
registry:

- **No `update-location` write operation.** The location's `firstName`,
  `lastName`, `email`, `phone`, `address`, `city`, `state`, `postalCode`,
  `country`, and `business.*` fields can be read (`get-location`) but not
  written via MCP. Full Business Profile sanitization is UI-only.
- **No `create-pipeline` operation.** Pipelines (and their stages) can only
  be listed (`get-pipelines`), never created or edited, via MCP.
- **No form-builder write operation.** Forms can only be listed
  (`get-forms`); building one is UI-only.
- **No workflow-builder write operation**, confirming the constraint already
  recorded on Issue #7. Workflows can only be listed (`get-workflow`).

Custom fields, tags, contacts, and opportunities all have working create /
read / delete operations and were built via MCP.

## Gotcha: the form builder can silently fork custom fields (P05)

Building a form field in the GHL UI by typing a new field name — instead of
picking an existing custom field from the dropdown — creates a **new**
custom field object, even when the label looks identical to one that
already exists. P05 hit this directly: the form's "Service Interest" and
"Message" fields were built as new fields (`contact.select_service_interest`,
`contact.message`) instead of being bound to the P0 fields already created
via MCP (`contact.service_interest`, `contact.lead_message`). The live
symptom was a Contact whose `customFields` array held the P0 field values
under the *wrong* field IDs. Always verify post-build with `get-custom-fields`
and compare `fieldKey`s against what was actually created, not just the
field labels shown in the UI.

## Gotcha: opportunity Name templates need real merge tags (P05)

The `Create Opportunity` workflow action's `Name` field must be populated
using GHL's merge-tag picker, not by typing the placeholder text the picker
displays (e.g. `[First Name] [Last Name]`) as literal characters. Doing the
latter creates an Opportunity whose `name` is literally the unresolved
bracket text — confirmed live via `get-opportunity` on the first P05 attempt,
fixed by re-inserting the tokens from the picker.

## Outbound webhook to n8n (P06)

The second GHL workflow — `LeadFlow Demo — Opportunity to n8n` — is built and
published. Its rebuildable checklist lives in
[`n8n/setup.md`](n8n/setup.md) §6, together with the declared Custom Data
contract, because the payload contract and the n8n side that consumes it have
to be read as one thing. Two constraints from that section belong here too:

- **Workflows remain UI-only.** Confirmed again in P06 — `get-workflow` reads,
  nothing writes.
- **Merge values must come from the picker**, never typed. The same defect that
  bit the `Create Opportunity` Name field in P05 would silently produce a
  payload whose `opportunityId` is literal bracket text.

## The re-inquiry branch (P07)

### The problem it fixes

The P0 duplicate-opportunity guard is **person-scoped** **[DOCUMENTED]**: while
a contact has one open Opportunity, GHL creates no second one. That comes from
the location setting and the action toggle, not from observation — the guard
has still never actually been exercised (P07). It is the load-bearing premise
for this whole branch, so it is tagged rather than asserted. That is right for an
accidental resubmission and wrong for a genuine second inquiry — and because
`LeadFlow Demo — Opportunity to n8n` triggers on *Opportunity Created*, a
suppressed re-inquiry also fires **no webhook**. The lead vanished with no
CRM artifact and no log line. ADR-002 names that as the worst outcome this
system can produce.

### The primitive that makes it buildable

`If/Else` was rejected for the existence check on **[DOCUMENTED]** grounds, not
tested ones: HighLevel's documentation states that opportunity fields are
filterable in a condition **only when the workflow has an opportunity-based
trigger**, and this workflow's trigger is a form submission. That claim was
never verified by building an `If/Else` and watching it fail. The primitive
chosen instead is **`Find Opportunity`**, which searches by contact and natively
branches into `Opportunity Found` / `Opportunity Not Found` — no condition step
required — and which **[OBSERVED]** works, via TC-03.

### Shape

Built by hand in `LeadFlow Demo — Form to Opportunity`. **Workflows remain
UI-only** — re-confirmed in P07 by exhaustive `search_operations`; the registry
exposes `get-workflow` plus `add-contact-to-workflow` /
`delete-contact-from-workflow` (which enroll a contact in an existing workflow)
and nothing that edits a workflow definition.

```
Trigger: Form Submitted — LeadFlow Demo — Service Inquiry
   │
   └─ Find Opportunity   [contact = trigger contact, Status = open,
                          Pipeline = LeadFlow Demo Pipeline, take Latest]
        │
        ├─ Not Found  →  Create Opportunity        (EXISTING — do not touch)
        │                 └─ Update Contact Field: inquiry_count = 1   (NEW)
        │
        └─ Found      →  Add Contact Tag: repeat-inquiry
                          └─ Add to Notes (internal)
                               └─ If/Else: Inquiry Count Empty?   (P08C, v13)
                                    ├─ is empty → Set Inquiry Count = 2
                                    │                └─┐
                                    └─ None     → Increment Inquiry Count (+1)
                                                     └─ Go To ──┤
                                                                │
                                    ┌───────────────────────────┘
                                    └─ Recheck Open Opportunity
                                         [contact, Status = open,
                                          Stage = Follow-up]
                                         ├─ Found     → Update Opportunity:
                                         │               Stage = Contacting
                                         └─ Not Found → end, stage untouched
```

Five build rules, each paid for by an earlier defect:

1. **`Not Found` keeps the existing `Create Opportunity` action untouched**,
   including its `Duplicate Opportunity: Disabled` toggle. A brand-new contact
   must take exactly today's path.
2. **`Update Contact Field: inquiry_count = 1` goes *after* `Create
   Opportunity`, never before.** If it sat first, a failure there would block
   opportunity creation — trading a cosmetic counter for the whole golden path.
3. **The increment never runs on an uninitialised field. [CLOSED in P08C,
   v13.]** Rule 2 writes `1` on the first inquiry, so every contact created
   from P07 onward is initialised — but `inquiry_count` had never been written
   before P07, so every older contact had it unset, and a resubmission would
   take `Found` straight into an increment on a null. HighLevel does not
   document that behaviour and it was never observed; the gap was carried here
   as **known and unclosed** for a sprint rather than assumed away.
   It is now closed by branching instead of guessing: an `If/Else` on
   `Inquiry Count is empty` sets **`2`** on the empty path and increments on
   the other. `2`, not `1` — a contact that already holds an open opportunity
   has by definition inquired at least once before.
   **Observed**, not asserted: `Marisol Vega`, pre-P07 and with no
   `inquiry_count` entry at all, resubmitted once and came out at `2` with one
   tag, one note, the same opportunity id and `createdAt`, and no webhook
   ([evidence](evidence/ghl-tests.md#p08c--inquiry_count-null-safety-on-a-pre-p07-contact)).
   **Still unobserved:** the `Increment` + `Go To` arm. Nothing has taken it
   since v13 shipped, so TC-03's pass covers v12 only until it is re-run.
4. **The stage pull-back is gated by a second `Find Opportunity`, not by an
   If/Else on stage.** Same documentation constraint as above, and it reuses a
   primitive already trusted. Unconditionally setting `Contacting` would drag
   an opportunity backwards out of `Qualified` or `Appointment` — exactly the
   metric corruption `architecture.md` §3 forbids. **Evidence status:** TC-03
   exercised the `Found` arm. The `Not Found` arm — the one that actually
   protects a `Qualified` or `Appointment` deal — was **observed in P08C**:
   `Marisol Vega`'s opportunity sat in `New Lead`, the second
   `Find Opportunity` returned `Not Found`, and `lastStageChangeAt` came back
   unchanged. Both arms are now observed, but only on the `empty` path of the
   v13 `If/Else` — nothing has yet reached this step through the `Increment` +
   `Go To` arm.
5. **Every merge value comes from the picker**, never typed. Typing the
   placeholder text produces literal bracket characters — the P05 defect,
   twice paid for.

The note body carries the **new** service interest, the **new** message, and a
timestamp. The contact's custom fields are updated by the form submission
itself before these actions run, so the merge tags render submission 2's
values. If the picker exposes no "right now" custom value, GHL stamps the note
with its own creation time and that is sufficient.

No SMS, no email, no premium or billable action anywhere in either branch.

### Two scope limits of this shape, named rather than discovered later

**The fix is pipeline-scoped; the guard it compensates for is person-scoped.**
`Find Opportunity` filters on `Pipeline = LeadFlow Demo Pipeline`, but the
duplicate-opportunity guard is one-open-opportunity-per-*contact*. A contact
whose only open opportunity lives in **another** pipeline therefore takes
`Not Found` → `Create Opportunity` → blocked by the guard → and then has
`inquiry_count` **set to 1** with no tag, no note and no webhook. That is
precisely the silent swallow this branch exists to end, now with a misleading
counter written over it. Unreachable in a single-pipeline demo, and a real
defect the moment a second pipeline exists. The fix is to drop the pipeline
filter from `Find Opportunity #1` so its scope matches the guard's.

**`inquiry_count` counts inquiries against the currently open opportunity, not
lifetime inquiries.** When the previous opportunity is won or lost,
`Find Opportunity` returns `Not Found`, a new opportunity is created, and rule
2's initialiser **overwrites** the accumulated count back to `1`. Every
document that calls this an inquiry counter means it in that narrower sense.

### The tradeoff this accepts, stated plainly

**GHL exposes no stable form-submission or workflow-execution identifier.**
Confirmed in P07: no such merge tag exists, and HighLevel's own feature
request for it ("Data from each Workflow Trigger accessible within Actions'
Merge Tags") is open and unshipped.

The consequence is unavoidable and load-bearing: **at the GHL layer an
accidental double submission is indistinguishable from a genuine re-inquiry.**
There is no submission id to compare. This branch therefore errs toward
amplification — a quick accidental resubmission now also produces a
`repeat-inquiry` tag, a note, and `inquiry_count = 2`.

That is the deliberate direction, not an oversight. ADR-002 already ranks the
two errors: a duplicate CRM artifact is visible and recoverable, a silently
swallowed hot lead is neither. **TC-02b was re-run against v13 on 2026-08-10
and the direction held**: two submissions 4.3 s apart produced one Contact, one
Opportunity, two submission records, and one amplified re-inquiry — the second
run found the first's opportunity and never reached `Create Opportunity`
([evidence](evidence/ghl-tests.md#tc-02b--duplicate-form-submission-same-person-submits-twice)).
**What that re-run did not do is exercise the guard**, and it explains why: the
window in which two runs could both reach `Create Opportunity` is narrower than
1.5 s, and browser automation could not get inside it because Cloudflare
Turnstile serializes the two posts.

A time-window condition (treat as re-inquiry only if the open opportunity is
older than N minutes) would narrow the false-positive band. It is **not** built
here — it adds a second uncertain condition surface for a cosmetic gain, and it
would still be a heuristic rather than an identity. Recorded as the upgrade
path.

### Downstream: what n8n and Sheets learn about a re-inquiry

**Nothing, deliberately, in this phase.** Three options were considered and
two are actively wrong:

- **Reuse `ghl:opportunity-created:<opportunityId>`** — wrong. The n8n ledger
  would see a known `eventId` and discard the re-inquiry as a redelivery,
  reproducing the exact silence this branch exists to end.
- **Mint an identity from receive time** — wrong. An unstable key defeats the
  ledger: a genuine webhook retry would be processed twice.
- **A separate `inquiry.repeated` event with a stable key** — correct in
  principle, unbuildable today. It needs a stable per-submission identifier,
  and GHL has none (above). `ghl:inquiry-repeated:<contactId>:<inquiry_count>`
  is the obvious candidate and is **not** built, because it depends on a merge
  tag rendering the *post*-increment value, and merge-tag freshness after a
  `Math Operation` within the same run is unverified. Building on an unverified
  read-after-write ordering is how you get a ledger that silently collapses two
  inquiries into one.

So the compensation stays entirely inside GHL, and **the event-grained backup
of a re-inquiry is deferred, not delivered**. The honest consequence: a
re-inquiry produces CRM signal a human can act on, and **no `leads_backup`
row**.

**And the reconciliation sweep will not catch it either.** TC-17 looks for an
Opportunity with no backup record. A re-inquiry creates no Opportunity, and the
contact's existing one already has a row from the first inquiry — so the sweep
scans past it. This is a *different* gap from TC-17, not another instance of
it, and it is worse: neither side holds an artifact a sweep could key on. Named
here rather than filed under an existing risk that would have quietly absorbed
it.

## Related

- [`integration-options.md`](integration-options.md) §1 — MCP capability
  research this setup implements.
- [`architecture.md`](architecture.md) §6 — identity and idempotency design
  this connection exists to verify.
- [`../PROJECT_STATE.md`](../PROJECT_STATE.md) — current sprint state.
