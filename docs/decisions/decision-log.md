# Decision log

Every decision this project is committed to, in one place. The three records
with their own file — [ADR-001](ADR-001-integration-hierarchy.md),
[ADR-002](ADR-002-idempotency-strategy.md),
[DECISION-001](DECISION-001-ai-boundaries.md) — carry the full reasoning. The
rest are recorded here because they are load-bearing but did not need a whole
document.

| ID | Decision |
|---|---|
| [ADR-001](ADR-001-integration-hierarchy.md) | Integration order: official MCP → official API → UI → browser automation → manual |
| [ADR-002](ADR-002-idempotency-strategy.md) | `externalLeadId` is the primary identity; `contactId` only after GHL persistence; email/phone are secondary signals |
| [DECISION-001](DECISION-001-ai-boundaries.md) | AI may summarize, extract, classify, and suggest — never approve or reject financial requests |
| — | Repository stays public for now; Git transport is SSH; sensitive environment detail is not published |
| — | Mermaid is the diagramming tool, in place of Excalidraw |
| — | First golden path is a single service type; four-service routing and appointments follow once it is stable |
| — | GHL integration via official MCP over OAuth, not a Private Integration Token — see [`../ghl-setup.md`](../ghl-setup.md) |
| — | n8n hosting: n8n Cloud primary, Docker local + ngrok fallback; no VPS, no existing server |
| — | Trial location identity sanitized partially (P05) — business contact fields (email, phone, address, city, state, postal, country) are now fictional; the owner's `firstName`/`lastName` are still real, unresolved after three correction attempts — see [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) "Open risks" |
| — | P0 opportunity-duplicate guard: GHL-native, person-scoped (location setting + workflow-action toggle), not the event-scoped `external_lead_id` check ADR-002 wanted — see [ADR-002](ADR-002-idempotency-strategy.md) "Consequences to watch" |
| — | Downstream delivery identity for the GHL-native path: `ghl:opportunity-created:<opportunityId>`, dedupes webhook redeliveries only, never gates whether to create the Opportunity — see [ADR-002](ADR-002-idempotency-strategy.md) |
| — | The GHL→n8n payload contract is **declared** through Custom Data merge tags, not discovered from GHL's implicit body; n8n allowlists only the declared keys — see [`../n8n/setup.md`](../n8n/setup.md) |
| — | Ingress protection is an unguessable path plus a shared secret **in the body**, because the free Outbound Webhook action supports no headers and the signed alternative is billable. Weaker than a signature, and documented as such |
| — | Every Google Sheets write forces `cellFormat: RAW`. The node default, `USER_ENTERED`, turned public form text into live formulas in the durable backup — reachable with no secret at all |
| — | The ledger is an n8n Data Table, kept separate from `run_log`: `run_log` is a narrative for humans, the ledger is queried state that decides control flow, and a logging failure must not change behaviour |
| — | The re-inquiry branch is gated by **`Find Opportunity`**, not `If/Else`. HighLevel filters opportunity fields in a condition only when the workflow has an opportunity-based trigger, and this one triggers on a form submission — see [`../ghl-setup.md`](../ghl-setup.md) |
| — | The stage pull-back is gated by a **second `Find Opportunity` filtered to `Follow-up`**, never an unconditional move. Dragging an opportunity back from `Qualified` or `Appointment` would corrupt stage-duration metrics — [`../architecture.md`](../architecture.md) §3 |
| — | `inquiry_count` is **initialised to 1 on the first inquiry, after `Create Opportunity`**, so a failure there can never block opportunity creation. This protects contacts created from P07 onward only — **pre-P07 contacts still have the field unset**, and the increment's behaviour on a null is undocumented and unobserved |
| — | **No downstream `inquiry.repeated` event.** GHL exposes no stable per-submission identity; reusing the opportunity-created key would make the ledger discard the re-inquiry as a redelivery, and a receive-time key would break retry dedup. Compensation stays in GHL and the event-grained backup is deferred — see [ADR-002](ADR-002-idempotency-strategy.md) |
| — | A failed backup answers **202 `retry_scheduled`**, not 500. The workflow owns a durable retry, so 500 — "this failed, it's yours" — would be false. 500 survives only for a one-attempt budget, which is unreachable at `maxAttempts = 3` |
| — | The retry lives **inside the original execution** on a durable `Wait`, not in a separate ledger-polling sweeper. One copy of the backup-write node means `cellFormat: RAW` cannot drift between two copies — a failure this repo has already had once. Cost: an execution lost mid-wait is not re-driven |
| — | Retry budget: **3 attempts, base 70s, ×2, jitter additive-only 0–20%, cap 300s.** The 70s base and one-sided jitter are forced by n8n holding sub-65-second waits in memory instead of persisting them |
| — | Validation requires `opportunityId` + `contactId` + **at least one of** email or phone. A phone-only lead is contactable and must not be rejected |
| — | Failure injection lives in an **operator-only, append-only Data Table** that fails open — never a payload field, because that would let an anonymous form submitter choose which leads fail |
| — | The reconciliation sweep asks **our ledger**, not GHL, whether an event was seen. `search-opportunity` cannot filter by custom field, so the vendor cannot answer the question — see [`../n8n/operations.md`](../n8n/operations.md) §5 |
| — | n8n gets its own **read-only Private Integration** scoped to `opportunities.readonly`. The Claude Code MCP OAuth grant is not a runtime credential and cannot be lent |

## Related

- [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) — current state and open risks
- [`../architecture.md`](../architecture.md) — the design these decisions shape
- [`../INDEX.md`](../INDEX.md) — reading route for the whole repository
</content>
