# Evidence — reconciliation test case

Full input, expected outcome, and the reason TC-17 is `BLOCKED` rather than
passing or failing.

Summary status lives in [`../../TEST_CASES.md`](../../TEST_CASES.md). This file
is the detail; it is not a second source of truth for status.

Related evidence files:
[GHL](ghl-tests.md) ·
[n8n reliability](n8n-reliability-tests.md) ·
[security](security-tests.md)

---

## TC-17 — Reconciliation recovers a lost webhook

**Status: BLOCKED — needs a read-only GHL Private Integration credential**

**Input.** An opportunity created in GHL whose outbound webhook never reached
n8n.

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

**Actual.** **NOT PASS — built, not executed, and the reason is a missing
credential, not a missing design.** The sweep exists as
[`../../n8n/workflows/reconciliation-sweep.sanitized.json`](../../n8n/workflows/reconciliation-sweep.sanitized.json),
12 nodes, deliberately **inactive**. What was established: (a) **the Claude Code
MCP OAuth grant cannot serve as n8n's runtime credential** — the token lives in
that client's own store bound to its `client_id`/`client_secret`, no repository
file holds it (`.mcp.json` is gitignored and carries an endpoint URL only, and
the n8n MCP entries carry a URL with no headers and no env), and n8n is a
different OAuth client with no path to it; (b) the read is
`GET https://services.leadconnectorhq.com/opportunities/search` with
`Version: 2021-07-28`, needing exactly **one** scope,
`opportunities.readonly`, because the response embeds
`opportunities[].contact.{name,email,phone}` — no second call and no
`contacts.readonly`. **What is NOT claimed:** that the query works. It has never
returned a live 200, so the location query-parameter spelling (`location_id` vs
`locationId`) is **unverified** and the node carries a note saying so. The
recovery half is also honestly weaker than the webhook path: `business` is left
empty and `service` is **derived** by splitting the Opportunity name on `" - "`,
both because the contact custom fields would need a scope the sweep did not ask
for. A recovered row is marked `lastAction=reconciled` so it can never be
mistaken for a first-class delivery.

---

## Ready-made test data already sitting in the location

Six fictional diagnostic contacts have a GHL opportunity with **no**
`leads_backup` row — all build artifacts predating the n8n leg — and each is a
live instance of TC-17's scenario: Marisol Vega, Tobias Lind, Camila Torres,
Camila Torres 02, Sofia Bennett, David Demo.

Three further fixtures must **not** be touched by the sweep, and asserting that
is part of the test: Valeria Cruz (TC-01), the `=1+1 Testcase` formula fixture
(TC-19) and Priya Chandran (TC-03) all fired their webhook normally and already
have rows with `completed` ledger entries.

## Two gaps the sweep structurally cannot close

- **A suppressed re-inquiry** (TC-03's scenario). Priya Chandran's second
  inquiry produced no opportunity and no row, so an opportunity-keyed sweep
  scans straight past it. This is **not** a TC-17 instance — TC-17 sweeps for an
  Opportunity lacking a backup row, and here there is no Opportunity while the
  existing one already has its row.
- **An event whose Opportunity does not exist in GHL at all.** The synthetic
  P08 test fixtures are in that category by design — including ledger row
  `id=5`, `ghl:opportunity-created:p08-tc10-transient`, whose `opportunityId` is
  synthetic, so no sweep will ever recover it.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../n8n/operations.md`](../n8n/operations.md) §5 — the sweep's design, its
  rules, and the read-only Private Integration it needs
- [`../architecture.md`](../architecture.md) §7 — reconciliation in the
  reliability model
</content>
