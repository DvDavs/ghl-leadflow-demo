# Evidence — n8n reliability test cases

Full input, expected outcome, and observed evidence for the scenarios whose
artifact is the **n8n** workflow: delivery dedup, validation rejection, and the
bounded retry ladder through to terminal human handoff.

Summary status lives in [`../../TEST_CASES.md`](../../TEST_CASES.md). This file
is the detail; it is not a second source of truth for status.

Related evidence files:
[GHL](ghl-tests.md) ·
[security](security-tests.md) ·
[reconciliation](reconciliation-tests.md)

---

## TC-02 — Duplicate delivery, webhook redelivered

**Status: PASS**

**Input.** The exact TC-01 webhook payload delivered a second time — same
`opportunityId`, therefore the same delivery identity
`ghl:opportunity-created:<opportunityId>` per ADR-002. `externalLeadId` is
deliberately **not** the key here: it identifies the original submission event
and nothing populates it on this path.

**Expected.** `leads_backup` row count for this `eventId` stays at exactly 1;
zero notifications; zero AI calls; zero GHL API calls on the second delivery;
HTTP 200 success-shaped, never 4xx/5xx; exactly one additional `run_log` row,
`outcome=duplicate_event`, same `eventId`, **different** `correlationId`.

**Actual.** Replayed via `scripts/replay-webhook.ps1` against the production
URL, 2026-08-09 07:14:23Z — n8n execution 7. Observed HTTP **200
`already_processed`**. Same `eventId` as TC-01, new `correlationId=n8n:7`
(TC-01 was `n8n:6`), `attempt=2`, and `firstSeenAt` preserved from the original
delivery at 05:30:48Z. Ledger lookup hit: `ledgerFound=true`,
`ledgerStatus=completed`, `alreadyProcessed=true`. `Ledger: Claim` and
`Sheets: leads_backup` **never executed** — zero additional backup rows proven
by node absence, not by counting. `Log Duplicate Event` wrote exactly one row,
`step=dedup`, `outcome=duplicate_event`. Last node
`Respond 200 already_processed`. Zero GHL calls — the workflow issues none on
any path. Operator-read sheet totals corroborate — **read after execution 8 at
07:15Z, not at this test's own 07:14Z timestamp** — `leads_backup` = 1 data row,
`run_log` = 10, which reconciles exactly as 5 diagnostic rejections + 3
processing boundaries + 1 `duplicate_event` + 1 `unauthorized`. **Sequential
only** — a redelivery minutes later is not evidence of concurrent-safety.

---

## TC-09 — Required field absent

**Status: PASS**

**Input.** Payload missing a required field (e.g. no phone and no email).

**Expected.** Rejected at validation before any CRM write; nothing partially
created; rejection logged with the correlation id and the specific failing
field; the sender receives a deterministic non-retryable response.
**Contract change, P08:** `email` is no longer required on its own. The rule is
now `opportunityId` and `contactId`, plus **at least one of** `email` or
`phone`. The old rule rejected a phone-only lead the business could simply have
called back, which violates [`../architecture.md`](../architecture.md) §7's one
real invariant — a lead stays *contactable*. The 422 names the rule,
`email_or_phone`, rather than arbitrarily blaming one of the two fields.

**Actual.** Authorized fixture carrying `opportunityId` and `contactId` and
neither `email` nor `phone` (Rosalind Mbeki, Kestrel Bridge Advisory), sent
through the internal harness so the delivery carried the **real** shared secret
— proven by the fact that it reached validation at all rather than 401.
**Production execution 18, 2026-08-09 22:53:22Z.** Observed HTTP **422**, body
`{"status":"invalid_payload","missing":"email_or_phone"}`. Normalizer output
read directly: `authorized=true`, `secretConfigured=true`, `valid=false`,
`missingFields="email_or_phone"`. Exactly one `run_log` row,
`correlationId=n8n:18`, `step=validate`, `status=rejected`, `attempt=0`,
`error="missing required field(s): email_or_phone"`, `outcome=invalid_payload`
— distinct from TC-18's `unauthorized`. **Zero business writes, proven by node
absence:** `Ledger: Look Up Event`, `Ledger: Claim`, `Sheets: leads_backup`,
`Fault Gate`, `Retry Decision` and `Sheets: needs_human` returned **no run data
at all** for this execution. **No retry is possible, structurally** — the 422
branch terminates before the ledger and never reaches the retry loop. **A defect
this test found:** the first run (execution 16) answered a bare
`{"status":"invalid_payload"}` with no field named, because `Respond 422` read
`missingFields` from its input, which by then was the Google Sheets append
result. Fixed to read the normalizer explicitly, then re-run; execution 16 is
left in the record as the pre-fix observation.

---

## TC-10 — Downstream webhook temporarily failing

**Status: PASS**

**Input.** Valid lead while the downstream endpoint returns 5xx.

**Expected.** Failure detected and logged; the lead is queued for retry, not
discarded; no partial duplicate is created by the failed attempt. **How the
failure is injected:** a row in the `leadflow_test_controls` Data Table,
reachable only by an operator with n8n access, scoped to one `eventId` prefix.
Never a payload field — a public form must not be able to steer the pipeline
into its own failure path.

**Actual.** Fault armed (`mode=always`, `eventScope=p08-tc10`) at 22:55:16Z,
then one authorized delivery of a complete, valid fixture (Aurelio Bonetti,
Meridian Tile Works, Business Loan). **Production execution 26, 2026-08-09
22:57:02Z.** Observed HTTP **202 Accepted**, body
`{"status":"retry_scheduled","eventId":"ghl:opportunity-created:p08-tc10b-transient","attempt":1,"maxAttempts":3,"nextAttemptAt":"2026-08-09T22:58:27.221Z"}`.
**The event is demonstrably not lost:** the execution was read back at 22:57:46Z
in status **`waiting`** with `waitTill=2026-08-09T22:58:28.451Z` — a
database-persisted wait, not an in-memory timer. Ledger row `id=6` read live:
`status=retry_scheduled`, `attempt=1`, `backupAttempt=1`,
`nextAttemptAt=2026-08-09T22:58:27.221Z`,
`lastError="injected downstream failure (leadflow_test_controls.backup_fault=always, scope=\"p08-tc10\")"`.
Exactly one `run_log` row for the failed attempt: `correlationId=n8n:26`,
`step=leads_backup`, `status=retrying`, `attempt=1`, `outcome=retry_scheduled`,
error naming attempt 1/3 and the due time. **No partial duplicate:**
`Sheets: leads_backup` had not executed at all at this point — the fault gate
throws *before* it. **A defect this test found:** the first attempt (execution
24) crashed because every node on the failure branch read `$json`, which by then
held the row the ledger and `run_log` writes had returned, not the decision item
— so `Exhausted?` and `First Failure?` both saw `undefined`, the 202 was skipped
and the wait amount was invalid. All of them now reference `Retry Decision`
explicitly. Execution 24's orphaned ledger row `id=5` is left in place; see
[`../n8n/operations.md`](../n8n/operations.md) §6. **Re-verified after
hardening, execution 42, 23:32:44Z:** the adversarial review moved the fault
scope from a substring on `eventId` to a prefix on `opportunityId` and added
node-level retry to every write between the claim and a terminal state, so this
row's evidence was re-observed against the final artifact — `202`,
`nextAttemptAt=23:34:06.084Z`, same shape.

---

## TC-11 — Retry succeeds after transient failure

**Status: PASS**

**Input.** The TC-10 lead, with the downstream endpoint restored before retries
are exhausted.

**Expected.** Exactly one final downstream record, not one per attempt; the
retry count is visible in the logs; final state is identical to the TC-01
outcome.

**Actual.** Same delivery as TC-10, continued. Fault disarmed at 22:57:25Z by
appending `mode=off` — 62 seconds before the scheduled retry was due, and with
the execution already asleep. **Production execution 26 resumed and finished
`success` at 22:58:33Z**, 91 seconds after it started. **`Fault Gate` executed
exactly twice:** run 0 emitted on its *error* output (fault armed), run 1
emitted on its *success* output (fault cleared) — the transient failure
genuinely clearing between attempts, observed rather than assumed, and only
possible because the retry loop re-reads the switch on every attempt.
**`Sheets: leads_backup` executed exactly once**, on run 1 — one downstream
record, not one per attempt, proven by node run count rather than by counting
rows. Operator read of the sheet confirms a single `p08-tc10b-transient` row
(`name=Aurelio Bonetti`, `lastAction=backup_written`, `status=processed`).
Ledger row `id=6` now `status=completed`, `backupAttempt=1` — one failed attempt
recorded — with `nextAttemptAt` and `lastError` **cleared to empty**, so no
stale retry state survives success. `run_log` for `n8n:26` reads
`claim → retry_scheduled(attempt 1) → leads_backup ok → complete`, terminating
in `outcome=processed`: the retry count is visible in the log, and the terminal
state matches TC-01's. **`Respond 200 processed` deliberately did not execute**
— `Response Already Sent?` took its true branch because the 202 had already
answered the connection. Answering twice would crash the run, and this guard is
the reason it does not. **Re-verified after hardening, execution 42, finished
23:34:24Z:** `Sheets: leads_backup` again ran exactly once (sourced from
`Fault Gate` run 1), ledger row `id=11` `completed` with `backupAttempt=1` and
both `nextAttemptAt` and `lastError` cleared, `Response Already Sent?` again
took its true branch, and `Sheets: needs_human` never executed.

---

## TC-12 — Retry exhausted

**Status: PASS — retry ladder and terminal state observed pre-hardening; the
hardened exhaustion branch is unexercised**

**Input.** Valid lead while the downstream endpoint fails past the retry budget.

**Expected.** Lead moves to a terminal failed state, not silent loss; it appears
in the backup path and is surfaced for human review; the failure is
distinguishable in logs from a validation rejection.

**Actual.** Fault armed (`mode=always`, `eventScope=p08-tc12`) and **left
armed**. One authorized delivery of a complete, valid fixture (Naledi Okonkwo,
Copperline Interiors, Mortgage). **Production execution 31, 2026-08-09
23:05:23Z → 23:09:26Z, status `success`** — 4 minutes 3 seconds, terminating on
its own rather than being abandoned. **The attempt count is bounded and was
observed exhausting:** three `Retry Decision` runs, `backupAttempt` 1 → 2 → 3,
`exhausted` false, false, **true**; delays **80s** then **166s**, both
consistent with base 70s × 2 plus additive 0–20% jitter, both above n8n's
65-second in-memory threshold and therefore both persisted. `firstFailure` was
true only on attempt 1. **Ledger row `id=8` terminal:** `status=failed`,
`backupAttempt=3`, `nextAttemptAt=""`. **Exactly one `needs_human` row**, read
back from the sheet: `eventId=ghl:opportunity-created:p08-tc12b-persistent`,
`reason="leads_backup write failed on all 3 attempts: injected downstream failure (…)"`,
`status=open`, `owner=unassigned`, `lastAction=retry_exhausted`. **`run_log`
terminal and distinguishable:** `outcome=retry_exhausted` with `status=failed` —
distinct from TC-09's `invalid_payload` and TC-18's `unauthorized`. **No silent
loss and no partial record:** `Sheets: leads_backup` never executed in this run,
so there is no half-written row, and the event is named in `needs_human` rather
than discarded. **`Respond 500` correctly did not fire** —
`Exhausted Without Response?` took its false branch because the caller already
held the 202. Manual replay procedure in
[`../n8n/operations.md`](../n8n/operations.md) §4. **A defect this test found,
and the most instructive one in P08:** on the first run (execution 29) the
ledger reached `failed` correctly while `Sheets: needs_human` errored on a
missing `columns.schema`, so **nothing reached the human queue** — a silent loss
produced by the very test meant to disprove it. Ledger row `id=7` is left as
`failed` with no `needs_human` row as the standing evidence that *a `failed`
ledger row is not proof a human was told*. **The fault switch was disarmed after
this test** — a `mode=off` row appended at 23:11Z and a final one at 23:33Z; the
switch's append-only history is the audit trail, and production is left `off`.
**Not re-run after hardening:** the exhaustion branch's nodes gained
`retryOnFail` and `Sheets: needs_human` became `appendOrUpdate` on `eventId` (so
a replayed-then-re-exhausted event updates its handoff row instead of appending
a duplicate). Those changes are **unexercised** — TC-10 and TC-11 were re-run
against the hardened artifact, TC-12 was not.

---

## Which artifact each of these passes was observed against

A passing test proves the version it ran against, not the version currently
deployed. n8n keeps a draft and an active version, and saving changes only the
draft — see [`../n8n/operations.md`](../n8n/operations.md) §1.

| Evidence | When (UTC) | Active version then |
|---|---|---|
| TC-02, execution 7 | 07:14 | `b162ad3f` |
| **TC-02 + TC-18 re-verification, executions 9 and 10** | 15:26 | published fix — debug object removed, `customData` fallback, normalised expressions. Detail in [security evidence](security-tests.md#which-artifact-each-of-these-passes-was-observed-against) |
| **TC-09, executions 16 and 18** | 22:52 and 22:53 | P08 n8n workflow. Execution 16 is the pre-fix observation of the 422 body; **18** is the pass |
| **TC-01 and TC-02 equivalents re-run, executions 20 and 22** | 22:53 and 22:54 | P08 n8n workflow. Not new rows — the P08 rebuild spliced a retry loop into the happy path and rewrote every `$('Ledger State').item` reference to `.first()`, so the golden path and the redelivery both needed re-observing against the new artifact. Execution 20 answered `200 processed` and wrote exactly one `leads_backup` row; execution 22 answered `200 already_processed` |
| **TC-10 + TC-11, execution 26** | 22:57–22:58 | P08 n8n workflow. One execution, two test cases: 202 and a persisted `waiting` state, then a resumed success 91 seconds later |
| **TC-12, executions 29 and 31** | 22:59 and 23:05 | P08 n8n workflow. 29 is the pre-fix run whose `needs_human` write errored; **31** is the pass |
| **Post-hardening: golden path (execution 40) and TC-10 + TC-11 (execution 42)** | 23:32–23:34 | **P08 hardened workflow**, active version `4ab773e2`. An adversarial review found that only the backup write was error-guarded, that `Sheets: needs_human` — the terminal safety net — was the least protected node in the graph, and that the fault scope was a substring match on a caller-supplied id. Node-level retry was added to every write between the claim and a terminal state, `needs_human` became `appendOrUpdate` on `eventId`, and the scope became a prefix on `opportunityId`. All three touch the live path, so the golden path and the retry ladder were re-observed. **TC-09, TC-12, TC-18 and TC-19 were not re-run against this version** — their evidence covers active version `c1225347`, one publish earlier |

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../n8n/operations.md`](../n8n/operations.md) — the retry budget, replay, and known limitations
- [`../n8n/testing.md`](../n8n/testing.md) — how to run these scenarios again
</content>
