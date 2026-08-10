# History — foundation and capability probes (P01–P04)

What was established before either integration leg was built: the environment
inventory, repository hygiene, the architecture and decision baseline, the
published test contract, GHL MCP access, and the four capability probes that
decided what could and could not be built.

This is the historical record. Current state lives in
[`../../PROJECT_STATE.md`](../../PROJECT_STATE.md); do not read this file to
find out what is true today.

Sibling milestones: [GHL leg (P05, P07)](ghl-leg-p05-p07.md) ·
[n8n leg (P06, P08)](n8n-leg-p06-p08.md)

---

## Milestone 1 — Environment inventory

Toolchain, GitHub access, service availability, and MCP registry audited
read-only. Published in sanitized form as
[`../environment.md`](../environment.md).

**Repository hardening.** `.gitignore` written before the first `git add`,
covering secrets, credential-shaped files, local n8n state, and cloud-sync
conflict artifacts — without blanket-ignoring `*.json`, since workflow exports
and payload fixtures will be versioned JSON.

**Inventory sanitization.** The full inventory is retained locally and
untracked; the published version keeps capabilities, versions, and
classification, and drops local security detail.

## Architecture and decision baseline

**Architecture baseline.** [`../architecture.md`](../architecture.md) plus three
Mermaid diagrams under [`../diagrams/`](../diagrams/).

**Decision records.** Integration hierarchy, idempotency strategy, and AI
boundaries recorded under [`../decisions/`](../decisions/).

**Test matrix.** [`../../TEST_CASES.md`](../../TEST_CASES.md) — 20 scenarios,
written before the implementation so the acceptance criteria could not drift to
match whatever happened to work. A coverage table records which **n8n and GHL**
workflow version each pass was observed against, because a passing test proves
the artifact it ran against and nothing later.

**Integration research.** [`../integration-options.md`](../integration-options.md),
sourced from official documentation only.

**Adversarial review.** Ran before publication. Three blockers found and fixed,
the most serious being that the idempotency claim was wrong as drawn — see the
correction commit and `architecture.md` §6.0.

**Published.** Four commits on `main`, pushed over SSH. The untracked local
inventory is confirmed absent from the remote.

## Issue backlog and sprint board

**Issue backlog.** 17 issues with priority and area labels, closed
progressively against published, verified artifacts as each phase landed.

**Sprint board.** *GHL Leadflow Demo Sprint* — statuses Backlog, Ready, In
Progress, Testing, Done, Blocked, plus a P0–P3 priority field. All 17 issues
loaded and set to their real state.

The board and the closed-issue list are two views of one truth and were checked
against each other rather than assumed to agree. Re-read the board rather than
trusting any snapshot of it; the repository has twice been bitten by treating a
change that *should* have landed as one that did.

## GHL MCP access

Official HighLevel MCP connected over OAuth
(`https://services.leadconnectorhq.com/mcp/anthropic/v2`), project-scoped
`.mcp.json` holding only the endpoint URL, no PIT created. Confirmed scoped to
exactly one location. See [`../ghl-setup.md`](../ghl-setup.md).

## P04 — capability probes

Four questions were answered by live probing rather than by reading the
schema, and two of the four came back unfavourably. Both are recorded as
resolved-unfavourably rather than deferred.

**Contact upsert matching semantics — resolved.** Live sequential probe
(fictional fixtures, cleaned up after) confirms `upsert-contact` matches on
email OR phone independently; either field alone merges into the existing
contact, and the differing field is overwritten by the latest call.
Concurrent-call behaviour remains unverified by design — the probe was
sequential. See
[ADR-002](../decisions/ADR-002-idempotency-strategy.md).

**Opportunity custom-field search — resolved, unfavourably.**
`search-opportunity`'s schema (confirmed via `describe_operation`) has no
custom-field parameter. ADR-002's planned second independent dedup check cannot
be built against this operation. Flagged as a real design gap for a later
phase, not papered over.

**Custom fields capability — corrected.** Previously classified
*partial — unconfirmed*; live discovery confirms dedicated read and write
operations exist in the grant. No fixture custom field was created — the
opportunity-search question resolved by schema inspection alone.

**n8n hosting — decided.** Primary: n8n Cloud (provisioned, ready). Fallback:
Docker local + ngrok. VPS and any existing server ruled out. See
[`../integration-options.md`](../integration-options.md) §3–4.

## Related

- [`../../PROJECT_STATE.md`](../../PROJECT_STATE.md) — current state
- [`../environment.md`](../environment.md) — the sanitized inventory
- [`../decisions/`](../decisions/) — ADR-001, ADR-002, DECISION-001
</content>
