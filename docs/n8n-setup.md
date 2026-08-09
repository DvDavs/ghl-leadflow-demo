# n8n and Google Sheets setup

Rebuildable checklist for the second half of the pipeline: GHL Opportunity →
GHL Outbound Webhook → n8n Cloud → Google Sheets.

Contains no secrets, no IDs, no URLs, and no real data. Every instance-specific
value is a placeholder you fill in through the UI.

## Why the payload contract is declared, not discovered

GoHighLevel's **free** `Webhook (Outbound)` workflow action sends a flat,
snake_case body. Its documented example shows contact fields, a nested
`location` object, and — when the workflow is triggered by an opportunity
event — a group of opportunity fields. **It does not document a contact-id
field at all**, and the only bare `id` in the example sits inside the
opportunity group, unlabelled.

Building against that shape would mean building against an undocumented
schema we cannot version. So we do the opposite: **the payload contract is
declared through Custom Data**, and n8n reads *only* the keys we declared.
GHL's native fields still arrive; the workflow ignores every one of them.

That choice buys three things: the contract is explicit and reviewable, the
n8n allowlist has something stable to allowlist, and a schema change on GHL's
side cannot silently alter what we persist.

## Constraint that shapes everything downstream

The free action supports **no custom headers, no auth, and no signature**. The
Custom Webhook action that does is premium and billable. So the shared secret
travels **in the body**.

Two consequences, both load-bearing:

1. Any payload captured from a real delivery is **secret-bearing**. It must
   never be committed. `.gitignore` denies `payloads/*.local.json` and
   `payloads/captured*.json` for exactly this reason. The versioned fixture,
   [`payloads/ghl-opportunity-created.example.json`](../payloads/ghl-opportunity-created.example.json),
   carries a redacted placeholder instead.
2. Replay tooling injects the secret at send time —
   [`scripts/replay-webhook.ps1`](../scripts/replay-webhook.ps1) — and never
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

`needs_human` is created now and **deliberately unused in this phase**. It is
the destination for TC-08 and TC-12 routing, which are not built yet. An empty
tab is honest; a tab quietly written to by nothing is not.

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
> If Variables are unavailable, see "Fallback" at the end of this document.

## 4. n8n Data Table — the ledger

Create a Data Table named `leadflow_event_ledger` with these columns:

| Column | Type | Meaning |
|---|---|---|
| `eventId` | String | `ghl:opportunity-created:<opportunityId>`. The dedup key. |
| `correlationId` | String | The delivery that most recently touched this row. |
| `opportunityId` | String | For reconciliation back into GHL. |
| `firstSeenAt` | String | ISO-8601. Set on first claim, never overwritten. |
| `updatedAt` | String | ISO-8601. Rewritten on every transition. |
| `status` | String | `claimed` \| `completed` \| `failed` |
| `attempt` | Number | Incremented per delivery of the same `eventId`. |

The ledger is deliberately **separate from `run_log`**. `run_log` is an
append-only narrative for humans; the ledger is queried state that decides
control flow. Mixing them would mean a logging failure could change behaviour.

## 5. Import the workflow

Import [`n8n/workflows/ghl-opportunity-to-sheets.sanitized.json`](../n8n/workflows/ghl-opportunity-to-sheets.sanitized.json).

The export is sanitized, so four things are placeholders and **must** be
re-picked in the UI after import. This is not import breakage — it is the
sanitization working:

| Placeholder | Where | What to do |
|---|---|---|
| `REPLACE_WITH_UNGUESSABLE_PATH` | `Webhook` node, `path` | Replace with a freshly generated UUID. Not a guessable word. |
| `REPLACE_WITH_SHEET_ID` | all 8 Google Sheets nodes | Pick the spreadsheet from the credential-backed dropdown. |
| `REPLACE_WITH_DATA_TABLE_ID` | all 4 Data Table nodes | Pick `leadflow_event_ledger` from the dropdown. |
| *(no credential bound)* | all 8 Google Sheets nodes | Select `GHL LeadFlow Demo — Google Sheets`. |

Then **Save and Activate**, and copy the **Production** webhook URL. The Test
URL expires after 120 seconds and will die mid-demo.

### What the workflow does, in order

```
Webhook
  → Normalize and Authorize        allowlist + mint eventId/correlationId + compare secret
  → Authorized?          no  → Log Unauthorized  → 401
  → Payload Valid?       no  → Log Invalid       → 422
  → Ledger: Look Up Event
  → Ledger State
  → Already Completed?   yes → Log Duplicate     → 200 already_processed
                          no ↓
  → Ledger: Claim            (status=claimed, BEFORE any backup write)
  → Log Claim
  → Sheets: leads_backup     (Append or Update, matched on eventId)
        ├─ ok    → Log Backup Written → Ledger: Complete → Log Processed → 200 processed
        └─ error → Ledger: Fail       → Log Failed       → 500
```

### Response contract

| Situation | HTTP | Body `status` | `leads_backup` | `run_log` |
|---|---|---|---|---|
| Secret missing or wrong | 401 | `unauthorized` | zero new rows | exactly one row, `outcome=unauthorized` |
| Required field missing | 422 | `invalid_payload` | zero new rows | exactly one row, `outcome=invalid_payload`, naming the field |
| New event | 200 | `processed` | exactly one row | three rows, one `correlationId`, last `outcome=processed` |
| Event already completed | 200 | `already_processed` | unchanged | exactly one row, `outcome=duplicate_event`, **new** `correlationId` |
| Backup write failed | 500 | `failed` | unchanged or one row | one row, `outcome=failed`; ledger left `failed` |

Two of these are deliberate and worth defending in an interview:

- **A duplicate answers 200, not 4xx.** A duplicate is our plumbing's artifact,
  not the sender's mistake. A 4xx makes senders retry harder or page someone,
  converting a non-event into an incident.
- **The unauthorized `run_log` row contains no caller-supplied value** — not
  the ids, not even the derived `eventId`. An unauthenticated caller must not
  be able to write attacker-chosen content into the audit log.

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

> **Gotcha, already paid for once in P05.** Merge values must be inserted from
> GHL's **merge-field picker**, never typed as the placeholder text the picker
> displays. Typing `[Opportunity Id]` by hand produces a payload whose value is
> literally that bracket text. P05 hit this on the `Create Opportunity` action's
> Name field — see [`ghl-setup.md`](ghl-setup.md).
>
> The first real delivery is the only thing that proves the tags resolved.
> Inspect the n8n execution body before declaring TC-01 anything.

### Capturing a payload safely

Read the body from the **n8n execution view**, not from a third-party echo
service. Sending this payload to a public request-bin would publish the shared
secret to a host we do not control.

To keep a captured payload for replay, save it as `payloads/captured.local.json`
— already gitignored — and redact the secret before it goes anywhere else.

## 7. Tests

| Test | Procedure |
|---|---|
| TC-01 | Submit a **new, fictional** lead through the live form. |
| TC-02 | Redeliver the exact captured payload: `.\scripts\replay-webhook.ps1 -PayloadPath payloads\captured.local.json`. **Do not resubmit the form** — that re-tests TC-02b, and the person-scoped duplicate-opportunity guard would suppress the Opportunity, so no webhook would fire at all. |
| TC-18 | Same payload, `-Mode NoSecret` and again `-Mode WrongSecret`. |

Evidence required before any of these is marked `PASS` is enumerated in
[`../TEST_CASES.md`](../TEST_CASES.md). A status code alone proves nothing
about downstream state.

## 8. Known limitations of this build

- **Not exactly-once.** A crash between the `leads_backup` write and the ledger
  reaching `completed` leaves a stale `claimed` row. A redelivery then does not
  short-circuit — it re-enters the claim branch. The `Append or Update` on
  `eventId` means it updates the same backup row instead of adding a second,
  which bounds the damage but does not eliminate the window. A claim timeout or
  a transactional store would; both are `[LATER]`.
- **Sequential evidence only.** TC-02 is a sequential redelivery. It is not
  evidence about concurrent deliveries, and must never be described as such.
- **Three Sheets writes on the happy path** — one per real stage boundary,
  plus the backup write. That costs latency in exchange for a `run_log` that
  still shows where a failed run stopped. Batching all three at the end would
  be faster and would log nothing when it mattered.
- **String comparison of the secret is not constant-time.** Over TLS, against a
  network attacker, this is not a practical exposure; it is noted rather than
  claimed to be absent.

## Fallback — if n8n Variables are unavailable on the plan

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

- [`ghl-setup.md`](ghl-setup.md) — the GHL side of this pipeline
- [`architecture.md`](architecture.md) §6 — identity and idempotency
- [`decisions/ADR-002-idempotency-strategy.md`](decisions/ADR-002-idempotency-strategy.md) — why the ledger is ordered the way it is
- [`integration-options.md`](integration-options.md) §3–4 — hosting decision
