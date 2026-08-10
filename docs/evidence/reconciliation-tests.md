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

**Status: PASS — executed 2026-08-10 against the live sweep. One defect found
and recorded below; it does not affect recovery, only the log that describes
it.**

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

**Actual.** **PASS on every assertion above.** The sweep
(`LbfiJvlXEWvVGhzh`, published version `09f0c52c`) was bound to the existing n8n
Header Auth credential *GHL LeadFlow Demo — Opportunities Read Only*, which
holds a sub-account Private Integration Token scoped to
`opportunities.readonly`. The credential was bound over MCP; its value was never
read, displayed, exported or logged.

### The location parameter, settled

`location_id` is the spelling GHL accepts. Run 1's
`GET https://services.leadconnectorhq.com/opportunities/search?location_id=…&order=added_desc&limit=100`
(`Version: 2021-07-28`) returned the location's opportunities with
`meta.total: 13`, and GHL's own `meta.nextPageUrl` in the response echoes
`location_id=`. The alternative spelling `locationId` was never needed and was
**not** tested — one confirmed spelling settles the question the node's note
was asking.

**What is claimed precisely:** the call succeeded and returned a real parsed
GHL body. The node does not request the full response, so the numeric status
code is not in persisted execution data; n8n's HTTP Request node raises on any
non-2xx, so a successful call is a 2xx. `location_id` being accepted is read
from the response itself, not inferred.

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

## Defect found by this test — `Log Reconciled` triples its rows

**Six recoveries produced 18 `reconciled` rows in `run_log`, not six** — rows
53–70, exactly three per recovered event, each trio 6–8 seconds apart and
carrying identical content.

`Log Reconciled` appears **six** times in the execution's `runData`, once per
recovery, each with `executionStatus: "success"` and an execution time of
14–18 s. The node is configured `retryOnFail: true, maxTries: 3,
waitBetweenTries: 5000`. Three attempts at roughly 2 s each plus two 5 s waits
accounts for that time, and every attempt landed a row before the run was
retried.

**The cause is not yet known, and is deliberately not guessed here.** n8n
collapses a retried node into a single `runData` entry and does not persist the
intermediate attempts, so the errors that triggered the two retries are not
recoverable from the execution record.

**What it does and does not damage:**

- `leads_backup` is unaffected — Append-or-Update on `eventId` converges, and
  the observed delta is exactly +6.
- The ledger is unaffected — the write is an upsert, and the observed delta is
  exactly +6.
- `run_log` is append-only by design, so it has no such convergence. It now
  overstates reconciliation three-fold. **A log that overcounts is a log you
  cannot count from**, which is the whole point of that tab.

**Do not "fix" this by turning `retryOnFail` off.** That trades a triplicated
log entry for a possibly missing one, which is the opposite of the trade P08's
hardening deliberately made. The fix needs the cause first. Recorded on the node
itself and in [`../n8n/operations.md`](../n8n/operations.md) §5.

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

## Ready-made test data — now consumed

The six fictional diagnostic contacts that had a GHL opportunity with **no**
`leads_backup` row have all been recovered by run 1, so **this scenario no
longer has unconsumed test data.** Re-running TC-17 from scratch needs a fresh
opportunity created in GHL whose webhook does not reach n8n.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../n8n/operations.md`](../n8n/operations.md) §5 — the sweep's design, its
  rules, and the read-only Private Integration it uses
- [`../architecture.md`](../architecture.md) §7 — reconciliation in the
  reliability model
