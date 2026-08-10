# History — the n8n leg (P06, P08)

How the automation half was built: ingress, dedup and the durable backup in
P06, then the whole reliability layer in P08 — retry, terminal handoff, fault
injection and reconciliation.

This is the historical record. Current state lives in
[`../../PROJECT_STATE.md`](../../PROJECT_STATE.md); do not read this file to
find out what is true today.

Sibling milestones: [foundation (P01–P04)](foundation-p01-p04.md) ·
[GHL leg (P05, P07)](ghl-leg-p05-p07.md)

---

## P06 — ingress and the Sheets backup

Webhook → allowlist normalization → shared-secret check →
`leadflow_event_ledger` Data Table claim → `leads_backup` (Append or Update on
`eventId`) → ledger `completed`, with deterministic 401 / 422 / 200 /
200-duplicate / 500 responses and append-only `run_log` boundaries. Published
and active. Artifacts:
[`../../n8n/workflows/ghl-opportunity-to-sheets.sanitized.json`](../../n8n/workflows/ghl-opportunity-to-sheets.sanitized.json),
[`../../scripts/replay-webhook.ps1`](../../scripts/replay-webhook.ps1),
[`../n8n-setup.md`](../n8n-setup.md).

### Vendor documentation corrected against observation

GHL nests declared Custom Data under `customData`, not at the payload root as
its own example shows, and the real payload carries `contact_id` at the root
although the example omits it. **The first error cost six rejected
deliveries.** Both are written up rather than quietly worked around — see
[`../n8n/setup.md`](../n8n/setup.md). GHL also misspells its own field as
`pipleline_stage`.

The general rule this produced: **vendor documentation is a hypothesis, and a
captured payload is evidence.**

### The publishing trap, learned here

A security fix was applied and verified by reading the workflow's nodes back
through the API; the read returned the *draft*, so the fix looked live. An
execution more than an hour later still ran the old code, which is the only
reason it was caught. Full account and the two rules that follow in
[`../n8n/operations.md`](../n8n/operations.md) §1.

## P08 — failure, retry and human handoff

### Bounded retry with backoff

A failed `leads_backup` write now answers **202 `retry_scheduled`**, not 500,
because the workflow owns the outcome and 500 would be a lie. The retry is held
inside the original execution by a **database-persisted** `Wait` that loops back
through the fault gate, so the switch is re-read on every attempt and a
transient failure can genuinely clear. Budget: **3 attempts, base 70s, ×2,
additive-only jitter 0–20%, cap 300s** — every constant in one Code node.
Observed live: 80s then 166s, terminal at 4m03s. The 70-second base and the
one-sided jitter are both forced by an n8n behaviour, not taste: a wait under 65
seconds is held in memory rather than persisted, and symmetric jitter would drop
the first retry under that line. See
[`../n8n/operations.md`](../n8n/operations.md) §3.

### Terminal handoff

Exhaustion writes ledger `failed`, one `needs_human` row (`status=open`,
`owner=unassigned`, `lastAction=retry_exhausted`) and a `run_log`
`outcome=retry_exhausted` distinct from both `invalid_payload` and
`unauthorized`. The `needs_human` tab is written for the first time. Manual
replay needed no new tooling: `Ledger State` short-circuits only on `completed`,
so a `failed` row is re-claimed on the next delivery of the same `eventId`.

### Validation contract loosened

`email` alone is no longer required. The rule is `opportunityId` + `contactId` +
**at least one of** email or phone, and the 422 names the rule
(`email_or_phone`) rather than blaming one field. The old rule rejected a
phone-only lead the business could have called back, which is the one thing
`architecture.md` §7's invariant forbids.

### Operator-only fault injection

The `leadflow_test_controls` Data Table arms the downstream failure for
TC-10/11/12. It is deliberately not a payload field — a public form must never
be able to steer the pipeline into its own failure path or into the
human-review queue. Append-only (n8n exposes no row update), so the switch
carries its own history. Fails open by construction. **Left `off`.**

### Reconciliation sweep — built and inactive

12 nodes, schedule every 10 minutes, one candidate at a time. Asks GHL for
recent opportunities and asks *our own ledger* whether it has seen each derived
`eventId` — the question moved to the only side that can answer it, because
`search-opportunity` has no custom-field filter. Safe to run twice by
construction. Artifact:
[`../../n8n/workflows/reconciliation-sweep.sanitized.json`](../../n8n/workflows/reconciliation-sweep.sanitized.json).

### Internal test harness

Two manual-trigger-only n8n workflows made the whole reliability suite
executable without a browser and without anyone handling the shared secret: a
sender that injects `$vars.GHL_WEBHOOK_SHARED_SECRET` in the HTTP node's own
expression at send time — so it never enters an item or execution data — and an
evidence reader over the three sheet tabs, the ledger and the fault switch.
Neither has a public trigger. See [`../n8n/testing.md`](../n8n/testing.md) §2.

### The adversarial review that returned FAIL

**It ran before the push, returned FAIL, and the findings were fixed rather
than argued with.**

Three findings were contradictions the session had introduced: the docs claimed
the reconciliation sweep was the backstop for a dead retry while the sweep's own
rule said it skipped any event with a ledger row.

Two were real holes:

- Only the backup write was error-guarded, so a transient Sheets error on a
  *bookkeeping* node would abort a run into a `claimed` row with no backup row,
  no `needs_human` row and no HTTP response — and the sweep was forbidden to
  touch it.
- `Sheets: needs_human`, the terminal safety net, was the least protected node
  in the graph, which is exactly the failure that had already been observed
  once.

Fixes: node-level retry on every write between the claim and a terminal state;
`needs_human` made idempotent per `eventId`; the fault scope narrowed from a
substring on a caller-supplied `eventId` to a prefix on `opportunityId`; and the
sweep now also recovers a ledger row that is not `completed` and has been quiet
for more than 30 minutes.

The golden path and TC-10/TC-11 were re-run against the hardened artifact;
**TC-12's hardened exhaustion branch is unexercised** and says so.

### Three defects found by the tests they were meant to pass

- The 422 body named no field.
- Every node on the failure branch read `$json`, which by then held the row the
  previous write had returned rather than the decision item.
- The `needs_human` append had an empty `columns.schema`, so the terminal
  handoff silently did not happen while the ledger said `failed`.

All three fixed and re-run. **The third is the one worth remembering** — it is a
silent loss produced by the very test meant to disprove it, and ledger row
`id=7` is left as standing evidence that a `failed` ledger row is not proof a
human was told.

### Four earlier rows re-run rather than assumed

The rebuild spliced a retry loop into the happy path, rewrote
`Normalize and Authorize`, and reparameterized `Sheets: leads_backup` — so
TC-01, TC-02, TC-18 and TC-19 were all covering a workflow that no longer
existed. Each was re-executed against the P08 artifact and each held. That is
the discipline TC-02b's demotion taught the project, applied before it could
bite a second time.

## Related

- [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) — current state
- [`../n8n-setup.md`](../n8n-setup.md) — the n8n documentation entry point
- [`../evidence/n8n-reliability-tests.md`](../evidence/n8n-reliability-tests.md) — TC-02, TC-09 through TC-12 evidence
- [`../evidence/security-tests.md`](../evidence/security-tests.md) — TC-18, TC-19 evidence
- [`../evidence/reconciliation-tests.md`](../evidence/reconciliation-tests.md) — TC-17
</content>
