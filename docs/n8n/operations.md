# n8n operations — publishing, contracts, retry, reconciliation

How the deployed pipeline behaves, what it promises the caller, and what it
cannot do. Read [setup](setup.md) first if you are rebuilding it from scratch.

Sibling pages: [setup](setup.md) · [testing](testing.md) ·
[troubleshooting](troubleshooting.md).

---

## 1. Publishing — saving a workflow does not change what production runs

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

A GoHighLevel workflow edit can sit unpublished in exactly the same way.
`get-workflow` exposes only id, name, status and **version** — no step detail —
so the version number is the only machine-checkable proof a UI edit shipped.

## 2. What the workflow does, in order

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

## 3. The retry budget, and why these numbers (P08)

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
`retry_scheduled` and that execution will never resume.

**The sweep is the backstop, but only because it was changed to be one.** As
first built it recovered events with *no* ledger row at all, on the reasoning
that a row in any state meant the retry loop owned it. An adversarial review
found the hole: a dead execution's row is indistinguishable from a live one's
under that rule, so nothing could ever re-drive it. `Missing From Ledger?` now
also recovers a row that is **not `completed`** and has been **quiet for longer
than 30 minutes** — the full ladder is three attempts over roughly four
minutes, so half an hour of silence is a dead retry, not a slow one. See §5.

**Every write between the claim and a terminal state now carries node-level
retry** (`retryOnFail`, 3 tries, 5s apart). The same review pointed out that
only the backup write was guarded, so a transient Google Sheets error on a
*bookkeeping* node — `Log Claim`, say — would abort the run with a `claimed`
ledger row, no backup row, no `needs_human` row, and no HTTP response at all.
Node-level retry narrows that window; the sweep's staleness rule closes what is
left.

## 4. Manual replay of an exhausted event

A `failed` ledger row is not a dead end, and no new tooling was needed for it.
`Ledger State` only short-circuits on `completed`, so a `failed` or
`retry_scheduled` row is re-claimed and re-attempted on the next delivery of
the same `eventId`. Two ways to trigger that:

1. **Redeliver the captured payload** with
   [`scripts/replay-webhook.ps1`](../../scripts/replay-webhook.ps1). Same
   `eventId`, fresh `correlationId`, full budget again. `leads_backup` is
   Append-or-Update on `eventId`, so a success after replay produces one row,
   not two.
2. **Let the reconciliation sweep find it**, if the payload was never captured.
   Two conditions, and the second is the binding one: a real GHL Opportunity
   must exist behind the event, **and** the `failed` ledger row must have been
   quiet for more than 30 minutes. Inside that window the sweep deliberately
   leaves it alone, because a row that was touched recently might belong to a
   retry that is merely asleep. Recovery writes the backup row; it does **not**
   close the `needs_human` row, which stays `open` for a human to resolve.

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

## 5. Reconciliation sweep — `LeadFlow Demo — Reconciliation Sweep`

Export: [`n8n/workflows/reconciliation-sweep.sanitized.json`](../../n8n/workflows/reconciliation-sweep.sanitized.json).

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
       → Missing From Ledger?   absent, or not completed and quiet 30min+
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
- **`completed` always means skip; anything else means skip only while it is
  fresh.** The first version skipped a ledger row in *any* state, on the
  reasoning that the retry loop owned it. That was wrong in the one case that
  matters: a dead execution's `claimed` or `retry_scheduled` row looks
  identical to a live one's, so nothing could ever re-drive it. The rule is now
  `status !== 'completed'` **and** quiet for more than **30 minutes**. The
  whole ladder is three attempts over roughly four minutes, so that threshold
  cannot race a retry that is merely asleep — it can only catch one that is
  dead. Staleness is read from n8n's own `updatedAt`, which is why the ledger
  deliberately has no user column of that name.
- **A recovered `failed` event keeps its `needs_human` row open.** Recovery
  writes the backup row that a human was told was missing; it does not decide
  that the human is finished.
- **Safe to run twice**, by construction and twice over: the first run writes a
  `completed` ledger row that every later run sees, and the backup write is
  Append-or-Update on `eventId` regardless. **Now measured, not just argued** —
  TC-17's second run sent all nine candidates down the skip branch and never
  invoked a single write node
  ([evidence](../evidence/reconciliation-tests.md#run-2--idempotence-execution-49-011805--011808-utc-success)).
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

**One further difference the first live run exposed, which was not predicted:**
`stage` on a recovered row is the raw `pipelineStageId`
(`2de64cba-…`), not the human name `New Lead` the
webhook path writes — the search response carries no stage name. `phone` also
arrives E.164 (`+12025550176`) rather than the form's `(202) 555-0193`. A
recovered row and a delivered row therefore do not sort or filter alike on
either column. Full table in
[evidence](../evidence/reconciliation-tests.md#what-a-recovered-row-does-not-carry).

### Open defect — `Log Reconciled` writes three rows per recovery

TC-17's first live run recovered six events and left **18** `reconciled` rows in
`run_log`, exactly three per event. The node ran once per recovery and reported
success, taking 14–18 s each time against a configured
`retryOnFail / maxTries: 3 / waitBetweenTries: 5000` — two failed attempts and a
successful third, with every attempt landing a row before its retry.

`leads_backup` and the ledger are untouched by this: Append-or-Update and upsert
both converge, and both deltas were exactly +6. Only the append-only log
multiplies.

**The cause is unknown and is not guessed.** n8n collapses a retried node into
one `runData` entry and does not persist the intermediate attempts, so the two
errors are gone. **Do not disable `retryOnFail` to make the symptom go away** —
that trades a triplicated log row for a possibly missing one, the opposite of
the trade the P08 hardening made everywhere else. Find the cause first.

**Two things the sweep structurally cannot do**, both already known:

- It cannot see a suppressed **re-inquiry** (TC-03's scenario). No second
  Opportunity is created, so there is nothing for an opportunity-keyed sweep to
  find, and the existing Opportunity already has its row. A different and worse
  gap — see [`../architecture.md`](../architecture.md) §5.
- It cannot see an event whose Opportunity does not exist in GHL at all. The
  synthetic P08 test fixtures are in that category by design.

### Credential — read-only Private Integration

The sweep is **published, active and running on its 10-minute schedule** since
2026-08-10. It got there by being given the one thing it was missing, and the
reason it could not borrow that thing is worth keeping rather than deleting now
that it is solved.

The GoHighLevel access this project uses everywhere else is an **OAuth grant
held by the Claude Code MCP client**. The token lives in that client's own
store, bound to that client's `client_id`/`client_secret`, and refreshing it
requires those same credentials. Nothing in this repository holds it —
`.mcp.json` is gitignored and carries only an endpoint URL, and the n8n MCP
entries carry a URL and no headers or environment at all. n8n is a different
OAuth client entirely and has no path to that token. **An MCP session is not a
runtime credential**, and treating it as one is the mistake this note exists to
prevent.

What n8n needed instead was its own credential, and it now has one: the n8n
Header Auth credential **`GHL LeadFlow Demo — Opportunities Read Only`**, bound
to `GHL: Recent Opportunities` and to nothing else. For a single sub-account the
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

> **`location_id` is accepted — and that is a smaller claim than "correct".**
> The first credentialed run succeeded and returned the location's 13
> opportunities, so the old `UNVERIFIED` worry (that the sweep sends a parameter
> name GHL rejects) is disproved. But the token is a **sub-account** PIT, so the
> location is already implied by the credential: GHL may be scoping on the token
> alone and ignoring the parameter. `meta.nextPageUrl` echoing `location_id=`
> shows an echo, not a parse. No control run — `locationId`, omitted, or wrong —
> was made. **Closed for this sweep, open in general:** do not quote this
> elsewhere as "the opportunity search takes `location_id`".

**The credential is never read from this repository, and must not be.** It was
bound to the node over the n8n MCP API by name and id; its value was not opened,
displayed, exported, logged or committed at any point, and nothing in an
execution record contains it. The scope is `opportunities.readonly` **as
created** — that it cannot write has not been *proved*, because proving it would
mean attempting a write against the live CRM, which the sweep exists to never
do. The load-bearing guarantee is structural: the workflow contains exactly one
GHL node and it is a `GET`.

## 6. Known limitations of this build

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
- **A retry that dies mid-wait is not resumed by n8n, and is recovered only by
  the sweep.** The retry lives inside the original execution; if that execution
  is lost, its ledger row stays `retry_scheduled` and nothing re-drives it
  in-process. The sweep's 30-minute staleness rule is what recovers it — but
  **only when a real GHL Opportunity exists behind the event.** There is a
  live instance that will therefore never be recovered: ledger row `id=5`,
  `ghl:opportunity-created:p08-tc10-transient`, orphaned by a P08 execution
  that died on a defect before that defect was fixed. Its `opportunityId` is
  synthetic, so no sweep will ever see it. Left in place rather than quietly
  cleaned, because it is the honest shape of this limitation.
- **A hard failure before the first Respond node leaves the caller hanging.**
  The webhook uses `responseMode: responseNode`, so a node that aborts the run
  before any Respond node executes sends nothing at all; the caller waits for
  its own timeout. Node-level retry on every write between the claim and a
  terminal state makes this much less likely, and does not make it impossible.
  A catch-all error branch answering `500` is the real fix and is `[LATER]`.
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

## Related

- [setup](setup.md) — building the sheet, the credential, the tables, the workflow
- [testing](testing.md) — executing the scenarios
- [troubleshooting](troubleshooting.md) — when every delivery returns 401
- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../architecture.md`](../architecture.md) §7 — the reliability model these choices implement
</content>
