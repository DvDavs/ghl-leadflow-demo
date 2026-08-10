# Evidence — reconciliation test case

Full input, expected outcome, and what was observed when TC-17 was executed.

Summary status lives in [`../../TEST_CASES.md`](../../TEST_CASES.md). This file
is the detail; it is not a second source of truth for status.

Related evidence files:
[GHL](ghl-tests.md) ·
[n8n reliability](n8n-reliability-tests.md) ·
[security](security-tests.md)

---

## TC-17 — Reconciliation recovers a lost webhook

**Status: PASS — executed 2026-08-10 against the live sweep, then re-run the
same day after the defect that first run exposed was diagnosed and fixed. The
first run is kept below in full, because how the defect was found matters as
much as that it is gone.**

**Input.** An opportunity created in GHL whose outbound webhook never reached
n8n. Six such opportunities were already sitting in the demo location.

**Expected.** ~~The scheduled sweep detects the opportunity has no
`external_lead_id` record~~ **Corrected in P08.** That was never buildable:
`search-opportunity` has no custom-field filter, so GHL cannot be asked that
question. The sweep asks GHL for recent opportunities and then asks **our own
ledger** whether it has ever seen the derived
`ghl:opportunity-created:<opportunityId>`. It processes only the absent ones and
produces one backup row, not two. **Additionally asserted:** running the sweep
twice must change nothing the second time; and neither Valeria Cruz (TC-01) nor
the `=1+1` formula fixture (TC-19) may be touched, since both already hold
`completed` ledger rows.

**Actual.** **PASS on every assertion above.** The sweep was bound to the
existing n8n Header Auth credential *GHL LeadFlow Demo — Opportunities Read
Only*, which holds a sub-account Private Integration Token scoped to
`opportunities.readonly`. The credential was bound over the n8n MCP API by name
and id; its value was never read, displayed, exported or logged.

**Version the pass covers.** Both runs executed the node graph as it stood
immediately after the credential was bound, which was published as `90830f62`.
**That version is no longer deployed** — the fix below replaced it. The recovery
and idempotence assertions were re-established against the current active
version `060c3ca1` in the re-run further down; the two runs recorded here now
document how the defect was found, not what production does.

### The location parameter — accepted, but not proven to be *read*

Run 1's
`GET https://services.leadconnectorhq.com/opportunities/search?location_id=…&order=added_desc&limit=100`
(`Version: 2021-07-28`) succeeded and returned the location's opportunities with
`meta.total: 13`.

**What is established:** `location_id` is accepted. The node's old
`UNVERIFIED` warning — that the sweep might be sending a parameter name GHL
rejects — is disproved. The sweep works as sent.

**What is NOT established, and the earlier draft of this file wrongly claimed:**
that GHL *parses and filters on* `location_id`. The credential is a
**sub-account** Private Integration Token, so the location is already implied by
the token itself; GHL may be scoping the query on the token alone and ignoring
the parameter entirely. `meta.nextPageUrl` echoing `location_id=` proves only
that GHL echoed the query string back, not that it read it. Distinguishing the
two needs a control that was **not** run — the same call with `locationId`, or
with the parameter omitted, or with a deliberately wrong value.

This does not weaken the TC-17 result: the sweep queried the right location and
recovered the right rows either way. It means the `location_id` vs `locationId`
question is **closed for this sweep and open in general**, and it must not be
quoted elsewhere as "GHL's opportunity search takes `location_id`".

**On the status code:** the node does not request the full response, so no
numeric code is in persisted execution data. n8n's HTTP Request node raises on
any non-2xx, and the node succeeded returning a parsed GHL body, so the call was
a 2xx. The exact code was not read and is not claimed.

### Run 1 — recovery (execution 45, 01:09:04 → 01:11:07 UTC, success)

GHL returned 13 opportunities. `Select Candidates` kept **9**: the four
`(Example)` seed opportunities created 2026-08-04 in a different pipeline fell
outside the 24-hour lookback, exactly as designed.

**Three skipped, with positive evidence rather than assumed absence.** Each
reached `Missing From Ledger?` and came out `needsRecovery: false`,
`recoveryReason: "ledger row present and healthy"`, then took the
`Already Known - Skip` branch:

| Fixture | opportunityId | Ledger status | Quiet |
|---|---|---|---|
| Priya Chandran (TC-03) | `VZ70B…` | `completed` | 467 min |
| `=1+1 Testcase` (TC-19) | `9qTtI…` | `completed` | 576 min |
| Valeria Cruz (TC-01) | `cs7Ef…` | `completed` | 1178 min |

**Six recovered**, each with `ledgerFound: false` and
`recoveryReason: "no ledger row; webhook never arrived"`:

| Contact | opportunityId | Ledger row created |
|---|---|---|
| Sofia Bennett | `I0NzO…` | `id=12` |
| Camila Torres 02 | `YJh2D…` | `id=13` |
| Camila Torres | `7ywF7…` | `id=14` |
| Tobias Lind | `AZtJO…` | `id=15` |
| Marisol Vega | `BmoXW…` | `id=16` |
| David Demo | `b1goo…` | `id=17` |

Observed state change, read through the P08 Evidence Reader before and after:

| Store | Before | After | Delta |
|---|---|---|---|
| `leads_backup` | 8 rows | 14 rows | **+6 — exactly one per recovered event** |
| ledger | 11 rows | 17 rows | +6, all `status: completed`, `attempt 1`, `backupAttempt 1`, `correlationId n8n:sweep:45` |
| `run_log` | 52 rows | 70 rows | **+18 — see the defect below** |
| `needs_human` | 1 row | 1 row | unchanged |

Every recovered backup row carries `lastAction: reconciled`, so no recovered row
can be mistaken for a first-class delivery.

### Run 2 — idempotence (execution 49, 01:18:05 → 01:18:08 UTC, success)

**Zero additional rows in any store**, and the proof is positive rather than an
assumed absence:

- The same 9 candidates were selected. **All 9** left `Needs Recovery?` through
  output 1 — output 0 is empty in every one of the nine runs — and
  `Already Known - Skip` executed 9 times.
- `Sheets: leads_backup (recovered)`, `Log Reconciled` and
  `Ledger: Record Recovery` **do not appear in the execution's `runData` at
  all**. They were never invoked. That is the positive evidence: not "no new
  rows appeared", but "the nodes that write rows did not run".
- The six events recovered 7–9 minutes earlier now report
  `ledgerFound: true`, `ledgerStatus: "completed"`,
  `recoveryReason: "ledger row present and healthy"` — the first run's own
  ledger write is what closes the second run's door.
- Run 2 finished in 2.3 s against run 1's 2 m 03 s, because it wrote nothing.

### No modification to GHL

- The sweep contains exactly one GHL node and it is a `GET`. No other node in
  the workflow touches GHL.
- Positive check: every opportunity's `updatedAt` is byte-identical across three
  separate observations — an independent read before run 1, the sweep's own read
  in run 1, and its read in run 2. For example Priya Chandran stayed
  `2026-08-09T21:49:59.773Z` and David Demo stayed `2026-08-09T02:39:02.371Z`
  throughout.
- **What is NOT claimed:** that the credential was proven incapable of writing.
  Proving that would require attempting a write, which is exactly what this test
  forbids. The scope is `opportunities.readonly` as created, and the only call
  the sweep makes is a read.

---

## Defect found by this test — `Log Reconciled` tripled its rows

**Six recoveries produced 18 `reconciled` rows in `run_log`, not six** — rows
53–70, exactly three per recovered event.

`Log Reconciled` appears **six** times in the execution's `runData`, once per
recovery, each with `executionStatus: "success"`, **one output item**, and an
execution time of 14–18 s. The node was configured `operation: append`,
`retryOnFail: true, maxTries: 3, waitBetweenTries: 5000`.

### Diagnosis — three attempts, three commits, one reported success

The trio timestamps are the evidence, and they were read out of the sheet rather
than reasoned about. Every recovered event's three rows are spaced ~7 seconds
apart:

| Event (last 8 of `opportunityId`) | Three `timestamp` values |
|---|---|
| `NgrXI7I4` | `19:09:10.851`, `19:09:17.794`, `19:09:25.233` |
| `Q76bW6wi` | `19:09:31.747`, `19:09:39.152`, `19:09:46.058` |
| `JhvPTGKE` | `19:09:52.111`, `19:09:59.539`, `19:10:06.467` |
| `Qx9Hrtg0` | `19:10:11.776`, `19:10:19.712`, `19:10:26.279` |
| `NGkZdIhy` | `19:10:31.440`, `19:10:38.383`, `19:10:44.888` |
| `yFeCngi2` | `19:10:50.247`, `19:10:58.240`, `19:11:05.827` |

Two facts follow, and neither needs an assumption:

1. **The three rows were written by three separate attempts, not by one attempt
   emitting three items.** The column is `{{ $now.toISO() }}`, so identical
   timestamps would mean one evaluation. They differ by ~7 s — one attempt plus
   the configured 5 s `waitBetweenTries`.
2. **The failure happens *after* the write.** The **last** timestamp of each
   trio is byte-identical to the one output item n8n recorded for that node run
   — for example `2026-08-09T19:09:25.233-06:00`. So attempts 1 and 2 each
   committed their row to Google Sheets and then failed, and only attempt 3
   reported success.

That is a **post-write failure against a non-idempotent write**. `retryOnFail`
was doing exactly what it was told; the defect was that the operation it guarded
had no idempotency key, unlike `leads_backup` (Append-or-Update on `eventId`)
and the ledger (upsert), which is precisely why both of those converged on +6.

### What was reproduced, and what was not

A temporary manual-trigger workflow (no public surface, deleted afterwards) ran
`Log Reconciled` in isolation: same document, same `run_log` tab, same
`defineBelow` mapping, same `cellFormat: RAW`, one fictional fixture, and
`retryOnFail` **off** so a single attempt could be observed, with a row count
read before and after.

- **Five single-attempt appends, five successes, zero errors** (executions
  53–57). Each landed exactly one row in ~1.5 s.
- Three of those five were fired **concurrently** to try to force the failure.
  They did not fail — but only **one** of the three rows survived, so a
  concurrency finding fell out of it that is recorded under "Open questions"
  below rather than folded into this result.

**The error attempts 1 and 2 returned is therefore still unknown, and is not
guessed.** n8n collapses a retried node into a single `runData` entry and does
not persist intermediate attempts, and the isolated reproduction did not fail.
What *is* established is the shape: the write commits, then the attempt fails.
That is enough to choose the fix, because the fix does not depend on which error
it was.

### The fix

`Log Reconciled` became an **Append or Update** matched on
`correlationId + eventId + step`. `retryOnFail: true / maxTries: 3 /
waitBetweenTries: 5000` is unchanged — deliberately.

The key is composite because no single column is both stable and exclusive:

| Candidate | Verdict |
|---|---|
| `eventId` | **Rejected.** `run_log` holds several boundary rows per event; the ingress workflow alone writes `claim`, `leads_backup` and `complete`. Matching on `eventId` would overwrite them |
| `correlationId` | **Rejected.** The sweep's is `n8n:sweep:<executionId>` — one value for the whole run. Six recoveries would collapse into one row |
| `correlationId + eventId` | Correct today only because the sweep has exactly one log boundary; it would break the day a second is added |
| `correlationId + eventId + step` | **Chosen.** Unique per row the sweep writes, and structurally unable to hit an ingress row, whose `correlationId` is `n8n:<executionId>` |

---

## TC-17 re-run — the fix under the same failure

**Status: PASS, 2026-08-10.** Executions **59** (recovery) and **61**
(idempotence), against active version `060c3ca1` — the exact draft that was
published immediately afterwards, with no edit in between.

### The fixture, and how the webhook was made to not arrive

TC-17's original six fixtures were consumed by run 1, so a fresh one was
created: contact `Noa Feldman` (`noa.feldman@example.com`, `+12025550137`,
tagged `p08b2-fixture`, `source = P08B2 Internal Test Harness`) and one
opportunity `Noa Feldman - Real Estate` in `LeadFlow Demo Pipeline`, created
through the GHL API at `2026-08-10T01:49:15.630Z`.

Creating it through the API does **not** dodge the webhook —
`LeadFlow Demo — Opportunity to n8n` triggers on *Opportunity Created*, not on
form submission. So the loss was staged on the n8n side instead: the ingress
workflow was **deactivated** for the few minutes around creation, and the
webhook had nothing to reach. It was reactivated before this evidence was
written. That reactivation had a consequence of its own, recorded in
[`../n8n/operations.md`](../n8n/operations.md) §1.

**Positive evidence the event never arrived**, read before the sweep ran: the
derived `ghl:opportunity-created:hD95n…` was absent from the
ledger, from `leads_backup` and from `run_log`.

### Run 1 — recovery (execution 59, 01:51:10 → 01:51:30 UTC, success)

GHL returned 14 opportunities; `Select Candidates` kept **10**. Nine reached
`Already Known - Skip` with `ledgerFound: true`, `ledgerStatus: "completed"`.
One was recovered.

Measured with a read-only counter over the three stores, before and after:

| Store | Before | After | Delta |
|---|---|---|---|
| `leads_backup` | 14 | 15 | **+1** — one row, `lastAction: reconciled`, `correlationId n8n:sweep:59` |
| ledger | 17 | 18 | **+1** — row `id=18`, `status: completed`, `attempt 1`, `backupAttempt 1` |
| `run_log` — `outcome: reconciled` | 18 | 19 | **+1** — exactly one row, `step: reconcile` |
| `run_log` — total | 72 | 73 | +1 |

**The strongest single line of evidence here is the node's duration.**
`Log Reconciled` took **13.5 s** for one recovery — the same 14–18 s signature
as the six triplicated runs, so the post-write failure occurred again and the
node still retried. It produced **one** row anyway. The fix was not tested
against a healthy write; it was tested against the failure it exists for.

### Run 2 — idempotence (execution 61)

01:52:02 → 01:52:05 UTC, success, 2.1 s.

- All **10** candidates left `Needs Recovery?` through output 1. Output 0 was
  empty in all ten runs, and `Already Known - Skip` executed ten times.
- **`Sheets: leads_backup (recovered)`, `Log Reconciled` and
  `Ledger: Record Recovery` do not appear in the execution's `runData` at all.**
  Not "no new rows appeared" — the nodes that write rows were never invoked.
- Re-counted after the run: `leads_backup` 15, ledger 18, `run_log` 73,
  `reconciled` 19. Every figure identical to after run 1. **Zero writes.**

### No modification to GHL

The fixture opportunity's `updatedAt` is byte-identical across three separate
observations — the creation response, the sweep's own read in run 1, and its
read in run 2 — all `2026-08-10T01:49:15.630Z`, equal to its `createdAt`.

**What is NOT claimed:** that the credential was proven incapable of writing.
The scope is `opportunities.readonly` as created, and the structural guarantee
is unchanged — the workflow contains exactly one GHL node and it is a `GET`.

### Open questions this run leaves

- **The error behind the post-write failure is still unknown.** It recurred in
  execution 59 (13.5 s) and n8n still did not persist it.
- **Concurrent appends to one Sheets tab lost rows.** Three diagnostic
  executions fired at the same second each reported a successful append and each
  read back a row count consistent with success, yet only **one** of the three
  rows exists in `run_log`. This is the repository's **first** concurrency
  observation of any kind. It was seen on the throwaway diagnostic's own writes,
  **not** on any production path — the sweep is single-threaded on a schedule
  and the ingress path was not exercised this way. It is recorded as a question,
  not as a claim about the deployed system.

---

## What a recovered row does not carry

Confirmed against the real rows rather than predicted:

| Column | Webhook path | Recovered row |
|---|---|---|
| `stage` | `New Lead` | `2de64cba-…` — the raw `pipelineStageId`; the search response carries no stage name |
| `phone` | `(202) 555-0193` | `+12025550176` — E.164 as GHL stores it, not the form's formatting |
| `business` | populated | empty — lives on a contact custom field the sweep has no scope for |
| `service` | from the form | derived by splitting the Opportunity name on `" - "` |
| `attempt`, `status` | numeric / `processed` | written as the strings `"1"` / `"processed"` |

The `stage` difference was **not** previously documented and is the sharpest of
these: a recovered row and a delivered row do not sort or filter the same way on
that column.

## Two gaps the sweep structurally cannot close — one now observed

- **A suppressed re-inquiry** (TC-03's scenario). Priya Chandran's second
  inquiry produced no opportunity and no row, so an opportunity-keyed sweep
  scans straight past it. This is **not** a TC-17 instance — TC-17 sweeps for an
  Opportunity lacking a backup row, and here there is no Opportunity while the
  existing one already has its row.
- **An event whose Opportunity does not exist in GHL at all.** Now observed
  rather than reasoned: ledger row `id=5`,
  `ghl:opportunity-created:p08-tc10-transient`, sat at `retry_scheduled` and
  quiet for over two hours — comfortably past the 30-minute staleness threshold,
  so the stale-row branch *would* have recovered it. It was untouched by both
  runs, because its synthetic `opportunityId` never appears in GHL's response
  and so it never becomes a candidate. The staleness branch can only rescue a
  stuck row whose Opportunity is real.

## Ready-made test data — consumed twice over

The six fictional diagnostic contacts that had a GHL opportunity with **no**
`leads_backup` row were all recovered by the first run, and the `Noa Feldman`
fixture created for the re-run was recovered by execution 59. **This scenario
has no unconsumed test data.**

Running TC-17 again needs a fresh fictional opportunity whose webhook does not
reach n8n. The procedure that worked is above: create the contact and
opportunity through the GHL API **with the n8n ingress workflow deactivated**,
since the GHL workflow fires on *Opportunity Created* and the API route does not
avoid it. Record `activeVersionId` before deactivating and republish that exact
id — [`../n8n/operations.md`](../n8n/operations.md) §1 says why.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../n8n/operations.md`](../n8n/operations.md) §5 — the sweep's design, its
  rules, and the read-only Private Integration it uses
- [`../architecture.md`](../architecture.md) §7 — reconciliation in the
  reliability model
