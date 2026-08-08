# DECISION-001 — AI decision boundaries

- **Status:** Accepted
- **Date:** 2026-08-08
- **Type:** business and compliance boundary, not a technical preference
- **Scope:** every AI-assisted step in this pipeline

## Context

The lead flow handles enquiries for home services that are frequently financed.
Lead payloads therefore carry free-text intent, budget signals, and sometimes
explicit financing requests. Language models are genuinely good at reading that
text: summarizing it, pulling structured fields out of it, and sorting it into
categories.

That competence is exactly what makes the boundary necessary. A model that can
classify "wants financing, budget around X" is one prompt away from being asked
"should we approve this?" — and it will answer, fluently and confidently,
whether or not it should.

Three reasons this line is drawn before any AI step is built rather than after:

- **Regulatory.** Credit and lending decisions carry adverse-action and
  explainability obligations. A model's output is not a defensible basis for
  denying someone financing.
- **Fairness.** A classifier trained on historical outcomes reproduces
  historical bias. Applied to who gets money, that is discrimination with a
  technical alibi.
- **Accountability.** When an automated decision harms someone, "the model
  decided" identifies no one who can answer for it.

## Decision

**AI is permitted to describe. AI is not permitted to decide.**

### Permitted

- **Summarization** — condensing free-text enquiries or call notes for a human.
- **Extraction** — pulling structured fields (service type, timeframe, stated
  budget, location) out of unstructured text.
- **Classification** — sorting a lead into a service category or an urgency
  band, as a routing hint.
- **Suggestion** — proposing a next action, a reply draft, or a priority, for a
  human to accept or discard.

Every one of these produces an **advisory artifact**. It is stored as a
suggestion, attributed to the model, and it never mutates a record on its own
authority.

### Prohibited

- **Approving or rejecting any financial request** — financing, credit,
  qualification for a payment plan, or any decision that grants or denies money.
- **Assigning a creditworthiness, risk, or eligibility score** used to gate a
  financial outcome. Renaming a decision as a score does not make it advisory.
- **Silently discarding a lead.** A model's low confidence is a reason to escalate, never a reason to drop.
- **Sending anything to a customer unreviewed** where the content commits the
  business to terms, pricing, or an approval.

### Uncertainty routes to a human

When the model's confidence is low, its output is malformed, its extraction is
incomplete, or the text touches a financial decision at all, the lead is flagged
for human review with the raw input preserved alongside the model's output.

Two properties of that rule matter:

- **Escalation is a success path, not an error path.** A lead in human review is
  correctly handled, and should not be logged, counted, or displayed as a
  failure.
- **The raw input is always preserved.** A human reviewing the model's summary
  must be able to check it against what the customer actually wrote. A summary
  that replaces its source is unreviewable.

## The test that decides ambiguous cases

> **Does the output, if acted on automatically, change whether a person gets
> money or a service they asked for?**

If yes, a human decides. If it only changes what a human sees first, AI may
produce it. When the answer is unclear, it is treated as yes.

## Consequences

**Good.**

- The pipeline stays defensible under scrutiny, which is the point of showing it
  in an interview.
- Human review capacity becomes a visible, designed-for path with its own test
  cases, rather than an unplanned overflow.
- The failure mode of a bad model output is a wasted human glance, not a wrongly
  denied applicant.

**Costs, accepted deliberately.**

- Less end-to-end automation than a demo that lets the model decide. That
  ceiling is intentional.
- Human review is a throughput constraint, and the design has to show what
  happens when the queue grows.

**How this is enforced, not just stated.**

- Model output is written to advisory fields only. No AI step holds write access
  to a stage transition or an approval field.
- Any AI-touched lead carries a marker showing which fields are model-derived.
- [TC-15 and TC-16](../../TEST_CASES.md) exist specifically to demonstrate this
  boundary holds — including the case where the model is asked to cross it.

## Related

- [ADR-001](ADR-001-integration-hierarchy.md) — integration hierarchy
- [ADR-002](ADR-002-idempotency-strategy.md) — identity and idempotency
- [`architecture.md`](../architecture.md) — where AI enrichment sits in the flow
