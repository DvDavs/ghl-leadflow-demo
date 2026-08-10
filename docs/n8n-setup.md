# n8n and Google Sheets — entry point

The second half of the pipeline: GHL Opportunity → GHL Outbound Webhook →
n8n Cloud → Google Sheets.

This page is a router. The content moved into [`docs/n8n/`](n8n/) so a session
can load only the part it needs.

| Page | What it answers |
|---|---|
| [`n8n/setup.md`](n8n/setup.md) | How to rebuild it: the declared payload contract, the sheet, the credential, the variable, the two Data Tables, importing the workflow, the GHL webhook workflow, and the fallback if Variables are unavailable |
| [`n8n/operations.md`](n8n/operations.md) | How it behaves: publishing vs saving, the node graph, the response contract, the retry budget, manual replay, the reconciliation sweep and its credential, and the known limitations |
| [`n8n/testing.md`](n8n/testing.md) | How each scenario is executed, and the internal test harness |
| [`n8n/troubleshooting.md`](n8n/troubleshooting.md) | When every delivery returns 401, when a fix looks applied but is not, and when a `failed` row reached nobody |

Contains no secrets, no IDs, no URLs, and no real data anywhere in this tree.

**Three things worth knowing before you open any of them:**

- **Vendor documentation is a hypothesis; a captured payload is evidence.** GHL
  nests Custom Data under `customData` despite its own example showing it
  flattened, and it misspells its own field as `pipleline_stage` —
  [`n8n/setup.md`](n8n/setup.md).
- **Saving a workflow is not publishing it.** The API read returns the draft. A
  security fix looked live for over an hour while production served the old
  version — [`n8n/operations.md`](n8n/operations.md) §1.
- **`cellFormat: RAW` must survive every future edit to a Sheets node.** The
  node default turns public form text into live formulas in the durable backup
  — [`n8n/setup.md`](n8n/setup.md) §5.

## Related

- [`ghl-setup.md`](ghl-setup.md) — the GHL side of this pipeline
- [`architecture.md`](architecture.md) §6 — identity and idempotency
- [`decisions/ADR-002-idempotency-strategy.md`](decisions/ADR-002-idempotency-strategy.md) — why the ledger is ordered the way it is
- [`integration-options.md`](integration-options.md) §3–4 — hosting decision
- [`../TEST_CASES.md`](../TEST_CASES.md) — the status matrix
</content>
