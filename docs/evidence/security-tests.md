# Evidence — security test cases

Full input, expected outcome, and observed evidence for the two scenarios that
test the ingress boundary: an unauthorized delivery, and formula injection
through the public form.

Summary status lives in [`../../TEST_CASES.md`](../../TEST_CASES.md). This file
is the detail; it is not a second source of truth for status.

Related evidence files:
[GHL](ghl-tests.md) ·
[n8n reliability](n8n-reliability-tests.md) ·
[reconciliation](reconciliation-tests.md)

---

## TC-18 — Unauthorized webhook rejected

**Status: PASS**

**Input.** Request to the webhook URL with a missing or wrong shared secret.

**Expected.** Rejected with 401 synchronously; zero GHL API calls issued by n8n;
zero backup rows; exactly one `run_log` row recording the rejection, with an
`outcome` distinct from the validation-failure value; no node after the secret
check executes.

**Actual.** Observed on **five live GHL deliveries** — n8n executions 1–5,
2026-08-09 04:31–05:17Z — during which the secret the normalizer resolved was
empty, because it read the wrong payload path. Observationally this is the
"missing secret" arm of this case. Every one of the five terminated at
`Respond 401` (`responseCode: 401`). `Sheets: leads_backup` and `Ledger: Claim`
never executed in any of them, so zero backup rows and zero ledger writes are
proven by node absence rather than by counting rows. `Log Unauthorized` wrote
exactly one row per delivery, `step=authorize`, `status=rejected`,
`outcome=unauthorized` — distinct from the `invalid_payload` outcome TC-09 uses.
The rejection row carries **no caller-supplied value**: `eventId`, `contactId`
and `opportunityId` are deliberately empty, so an unauthenticated caller cannot
write chosen content into the audit log. Zero GHL mutations — the workflow
issues no GHL call on any path, and MCP reads confirm the records were untouched
by n8n. These were real webhook deliveries from GHL, not scripted replays.
**Both arms are covered.** Those five prove the absent-secret arm — the resolved
value was empty. The wrong-value arm was then run deliberately via
`scripts/replay-webhook.ps1 -Mode WrongSecret` (executions 8 and 10): same 401,
same single `unauthorized` row, `Ledger: Claim` and `Sheets: leads_backup` again
never executed. Execution 10 logged `n8n variable resolved: true`, which
distinguishes a mismatched value from an unset variable and rules out the two
failing for the same reason.

---

## TC-19 — Formula injection through the public form

**Status: PASS**

**Input.** A lead submits a name beginning with `=`, delivered over the normal
authorized path with GHL's own correct shared secret.

**Expected.** The value is stored in `leads_backup` as literal text, never
evaluated. The attacker holds no secret and needs none — this is reachable by
anyone who can submit the public form, so path secrecy and the shared secret are
both irrelevant to it.

**Actual.** Live submission `=1+1 Testcase` 2026-08-09 15:33Z — n8n execution
11. The normalizer passed `name: "=1+1 Testcase"` to `Sheets: leads_backup`, the
write succeeded, and `Respond 200 processed` was the last node. Operator read of
the sheet shows the **literal text** `=1+1 Testcase` in the `name` column, not
`2`. Confirms `options.cellFormat: "RAW"` is in effect on the published
workflow. Note the boundary this does **not** cover: `RAW` governs storage only,
so exporting `leads_backup` to CSV or XLSX and opening it in Excel or
LibreOffice re-parses the leading `=` at import time regardless — see
[`../n8n/setup.md`](../n8n/setup.md) §5. **Re-run in P08, execution 35,
2026-08-09 23:19:21Z.** `Sheets: leads_backup` was reparameterized during the
retry rebuild, which is precisely how `cellFormat: RAW` gets lost, so execution
11's evidence no longer covered the deployed node. Re-submitted
`=1+1 P08 Recheck`; `Respond 200 processed` was the last node, `Retry Decision`
never ran, and an operator read of the sheet shows the stored `name` as the
**literal text** `=1+1 P08 Recheck`, not `2`.

---

## Which artifact each of these passes was observed against

A passing test proves the version it ran against, not the version currently
deployed. n8n keeps a draft and an active version, and saving changes only the
draft — see [`../n8n/operations.md`](../n8n/operations.md) §1.

| Evidence | When (UTC) | Active version then |
|---|---|---|
| TC-18, five live rejected deliveries | 04:31–05:17 | pre-`b162ad3f` (`b4aa5cf4` / `b8fa1e5e`) |
| TC-18 wrong-value, execution 8 | 07:15 | `b162ad3f` |
| **TC-02 + TC-18 re-verification, executions 9 and 10** | 15:26 | published fix — debug object removed, `customData` fallback, normalised expressions |
| **TC-19, execution 11** | 15:33 | published `cellFormat: RAW` fix |
| **TC-18 wrong-value re-verification, execution 37** | 23:19 | P08 n8n workflow. `Normalize and Authorize` was rewritten for the TC-09 validation change, so TC-18's earlier passes covered a node that no longer exists in that form. 401, one `unauthorized` row, `n8n variable resolved: true`, no caller-supplied value in the row, and `Ledger: Claim` / `Fault Gate` / `Sheets: leads_backup` all never executed. **The absent-secret arm was not re-run** — the harness has no no-secret mode and `scripts/replay-webhook.ps1 -Mode NoSecret` needs an operator |
| **TC-19 re-verification, execution 35** | 23:19 | P08 n8n workflow. `Sheets: leads_backup` was reparameterized during the rebuild, which is exactly how `cellFormat: RAW` gets lost. Re-submitted `=1+1 P08 Recheck`; operator read of the sheet shows the literal text, not `2` |

Neither TC-18 nor TC-19 was re-run against the post-hardening version
`4ab773e2`; their evidence covers active version `c1225347`, one publish earlier
— see
[n8n reliability evidence](n8n-reliability-tests.md#which-artifact-each-of-these-passes-was-observed-against).

The executions 9 and 10 re-verification covers every line changed by the
security fix: the normalizer, the secret comparison, the dedup branch, and the
rejection row's new diagnostic column. Execution 10 logged
`n8n variable resolved: true`, which additionally proves the rejection came
from a genuinely mismatched value rather than an unset variable.

The later `cellFormat: RAW` change on **the eight Google Sheets nodes the
workflow had at the time** was initially covered by nothing — neither TC-02 nor
TC-18 writes to `leads_backup` at all. It is now covered by **TC-19** (execution
11, 15:33Z), a live submission whose name begins with `=`, verified both in the
execution record and by reading the stored cell.

The count is eight here and nine in [`../n8n/setup.md`](../n8n/setup.md) §5
because P08 added a ninth Sheets node. Counted directly in the sanitized export:
8 at the formula-injection fix, 9 from P08 onward, `RAW` on every one of them at
both points.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../n8n/troubleshooting.md`](../n8n/troubleshooting.md) — diagnosing a permanent 401
- [`../n8n/setup.md`](../n8n/setup.md) §5 — why `cellFormat: RAW` must survive every edit
- [`../architecture.md`](../architecture.md) §8 — trust boundaries
</content>
