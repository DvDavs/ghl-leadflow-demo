# ADR-001 — Integration hierarchy

- **Status:** Accepted
- **Date:** 2026-08-08
- **Scope:** every integration point in this demo — GoHighLevel, n8n, Google Sheets

## Context

Each system in this pipeline can be driven through several different layers.
GoHighLevel can be reached through an MCP server, a documented REST API, its
own web UI, a browser driven programmatically, or a human clicking. The same
spread exists for the automation layer and for Google.

Under a two-day deadline the tempting move is to pick whichever layer produces a
visible result fastest. That reliably produces a demo that works once on one
machine and cannot be explained, rerun, or handed to anyone else.

Three forces are actually in tension:

- **Speed.** The demo must exist within the sprint.
- **Durability.** Anything built on an undocumented or scraped surface breaks
  when the vendor changes markup, and cannot be defended in an interview.
- **Honesty.** Some configuration in a SaaS CRM genuinely has no API. Pretending
  otherwise produces a plan that silently fails on day two.

## Decision

Integrations are chosen in strict preference order. A lower layer is used only
when every layer above it has been checked and ruled out **with evidence**:

1. **Official, appropriate MCP** — a Model Context Protocol server published by
   the vendor itself, when one exists and covers the operation.
2. **Official API** — the vendor's documented REST API, with documented
   authentication.
3. **UI** — a human configuring the product through its own interface.
4. **Browser automation** — programmatic control of that interface.
5. **Manual** — a documented human step, performed at demo time.

Two qualifiers carry most of the weight:

**"Official" excludes community projects.** A third-party MCP server for a
vendor's product is not the vendor's MCP server, regardless of how well it
works. It may be used, but it is classified at the level its transport actually
sits on — usually layer 2, since it wraps the public API — and it is labelled as
community-maintained wherever it appears.

**"Appropriate" is a real filter, not decoration.** An official MCP that does not
support the operation we need is not the right layer for that operation. The
hierarchy is applied per operation, not once for the whole vendor. Reading
contacts through an MCP while creating a pipeline through the UI is a correct
outcome, not an inconsistency.

Rejecting a layer requires a citation — an official document showing the
capability is absent or unsuited — recorded in
[`integration-options.md`](../integration-options.md) with the URL and the date
it was consulted. "I could not find it" is a research result to be written down,
not a licence to drop a level.

## Alternatives considered

**API-only, skip MCP entirely.** Fewer moving parts and the most stable
contract. Rejected as a blanket rule because it discards a vendor-supported
layer without checking it, and because "did you evaluate the newer integration
surface?" is exactly the question this demo should be able to answer. It remains
the correct choice per-operation whenever MCP coverage is absent.

**UI-first, automate later.** Fastest possible visible progress. Rejected as the
default because it produces no reproducible artifact: a pipeline configured by
clicking cannot be diffed, reviewed, or rebuilt, and nothing survives the demo.
It stays legitimate for the operations that genuinely have no API surface.

**Browser automation as a general-purpose fallback.** Superficially attractive
because it can drive anything. Rejected because it is the most brittle option
available, it breaks on markup changes the vendor is free to make without
notice, and it is disproportionate effort inside a two-day window. It is kept at
layer 4 rather than removed, for the narrow case where a required step has no
API and must nonetheless be repeatable.

## Applying it — the first resolution

The hierarchy was written before the research, then applied to it. Full evidence
in [`integration-options.md`](../integration-options.md); the outcome:

| Operation | Layer selected | Basis |
|---|---|---|
| Contacts, opportunities, pipelines, calendars, locations | **Layer 1 — official MCP** | HighLevel publishes an official MCP server, and its coverage list names every object the demo needs |
| Operations the runtime grant does not cover | **Layer 2 — official REST API** | Same vendor, documented authentication |
| **Workflow authoring and the outbound webhook step** | **Layer 3 — UI** | Workflows are **absent** from MCP coverage, and the REST API documents retrieval only. No automatable path exists |
| Enabling premium workflow features | **Layer 3 — UI** | No documented API |
| Everything else | **Not layer 4** | The only UI-bound task is one-time workflow authoring, which a human does faster and more reliably than a script |

A single vendor-level decision would have been wrong in both directions: "use
the MCP" strands workflow creation with no path, and "use the UI" discards a
supported API surface for every data operation. Hence the per-operation split
above.

Two things follow, and both are practical rather than self-congratulatory:

**Workflow configuration must be written up as a reproducible checklist**, or
the demo cannot be rebuilt on a fresh location. That checklist does not exist
yet and is a known gap.

**The layer-1 assignments are provisional.** The MCP's effective catalog is
grant-dependent and only fully discoverable at runtime with a real token.
Anything that fails there falls to layer 2 — which is the hierarchy working, not
the plan breaking.

## Consequences

**Good.**

- Every integration choice has a written, dated justification, so the
  architecture can be defended rather than asserted.
- Research happens before implementation, which surfaces missing capabilities
  while there is still time to route around them.
- The layer split makes the boundary between "the product's job" and "our code's
  job" explicit.

**Costs, accepted deliberately.**

- Research time is spent before any code. In a two-day sprint that is real cost,
  taken because discovering an API gap on day two is worse.
- Mixed layers across operations produce a less uniform system, and the
  documentation has to state clearly which layer each operation uses.

**Consequences to watch.**

- **UI steps do not disappear.** CRM configuration — pipelines, custom fields,
  forms, calendars — is likely to require the UI regardless of what the API
  supports. Every such step must be written down as a reproducible checklist, or
  the demo becomes unrebuildable on a fresh location.
- The hierarchy constrains *how* we integrate, not *what* the system does. It
  never justifies dropping a required capability because the preferred layer
  lacks it — that is an escalation to the next layer, not a scope cut.

## Related

- [`integration-options.md`](../integration-options.md) — the evidence this ADR depends on
- [ADR-002](ADR-002-idempotency-strategy.md) — identity and idempotency
- [DECISION-001](DECISION-001-ai-boundaries.md) — AI decision boundaries
