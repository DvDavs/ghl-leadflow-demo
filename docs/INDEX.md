# Documentation index and reading route

This repository is documentation-heavy on purpose — every reliability claim is
meant to be defensible. That only works if a reader can find the one page they
need instead of loading all of it.

**Read in this order. Stop as soon as you have what you came for.**

1. [`../PROJECT_STATE.md`](../PROJECT_STATE.md) — what is true today: what is
   built, what passes, what is blocked, what the open risks are, and the next
   three actions. **Always read this first.**
2. [`../TEST_CASES.md`](../TEST_CASES.md) — the status matrix. One row per
   scenario: purpose, status, the artifact version the pass covers, and a link
   to its evidence.
3. **This file** — where everything else is.
4. Evidence and history — **open only when you actually need them.**

## By question

| Question | File |
|---|---|
| What is done, blocked, and next? | [`../PROJECT_STATE.md`](../PROJECT_STATE.md) |
| Does scenario X pass, and against which version? | [`../TEST_CASES.md`](../TEST_CASES.md) |
| What was actually observed when X ran? | [`evidence/`](evidence/) |
| Components, boundaries, who owns what | [`architecture.md`](architecture.md) |
| Why was this decided? | [`decisions/decision-log.md`](decisions/decision-log.md) |
| How do I rebuild the n8n leg? | [`n8n/setup.md`](n8n/setup.md) |
| How does the deployed pipeline behave? | [`n8n/operations.md`](n8n/operations.md) |
| How do I run the tests again? | [`n8n/testing.md`](n8n/testing.md) |
| Everything returns 401 — why? | [`n8n/troubleshooting.md`](n8n/troubleshooting.md) |
| How do I rebuild the GHL leg? | [`ghl-setup.md`](ghl-setup.md) |
| What can the build machine do? | [`environment.md`](environment.md) |
| What do GHL and n8n actually support? | [`integration-options.md`](integration-options.md) |
| How do I run the interview demo? | [`demo/runbook.md`](demo/runbook.md) |
| What is the one-page summary? | [`demo/one-page.md`](demo/one-page.md) |
| How did we get here? | [`history/`](history/) |

## Evidence

Observed output for every executed scenario. These files are the detail behind
`TEST_CASES.md`; they are not a second source of truth for status.

| File | Scenarios |
|---|---|
| [`evidence/ghl-tests.md`](evidence/ghl-tests.md) | TC-01, TC-02b, TC-03 |
| [`evidence/n8n-reliability-tests.md`](evidence/n8n-reliability-tests.md) | TC-02, TC-09, TC-10, TC-11, TC-12 |
| [`evidence/security-tests.md`](evidence/security-tests.md) | TC-18, TC-19 |
| [`evidence/reconciliation-tests.md`](evidence/reconciliation-tests.md) | TC-17 |

## n8n

[`n8n-setup.md`](n8n-setup.md) is the entry point and routes to four pages:

| File | Contents |
|---|---|
| [`n8n/setup.md`](n8n/setup.md) | The declared payload contract, the sheet, the credential, the variable, the ledger and fault-switch Data Tables, importing the workflow, the GHL webhook workflow, the Variables fallback |
| [`n8n/operations.md`](n8n/operations.md) | Publishing vs saving, the node graph, the response contract, the retry budget, manual replay, the reconciliation sweep and its credential, known limitations |
| [`n8n/testing.md`](n8n/testing.md) | Per-scenario procedures and the internal test harness |
| [`n8n/troubleshooting.md`](n8n/troubleshooting.md) | Permanent 401s, a fix that looks applied but is not, a `failed` row nobody was told about |

## Demo

| File | Contents |
|---|---|
| [`demo/runbook.md`](demo/runbook.md) | The rehearsal record, the 5–7 minute script minute by minute, the phrases that state each limitation out loud, the fallback for every system that can fail, and the 10-minute pre-interview checklist |
| [`demo/one-page.md`](demo/one-page.md) | The leave-behind: problem, architecture, defensible decisions and what each one costs, evidence, risks and limitations |
| [`../assets/demo/`](../assets/demo/) | The five sanitized fallback captures, the captioned walkthrough video built from them, and the capture and redaction rules both are held to |

## Design and decisions

| File | Contents |
|---|---|
| [`architecture.md`](architecture.md) | Components, lifecycle model, boundary contracts, where state lives, identity and idempotency, reliability, trust boundaries |
| [`diagrams/general-architecture.md`](diagrams/general-architecture.md) | How data moves between systems |
| [`diagrams/lead-lifecycle.md`](diagrams/lead-lifecycle.md) | The states a lead passes through |
| [`diagrams/reliability.md`](diagrams/reliability.md) | Where failures happen and who handles them |
| [`decisions/decision-log.md`](decisions/decision-log.md) | Every decision in one table |
| [`decisions/ADR-001-integration-hierarchy.md`](decisions/ADR-001-integration-hierarchy.md) | Which integration layer, and why |
| [`decisions/ADR-002-idempotency-strategy.md`](decisions/ADR-002-idempotency-strategy.md) | How duplicates are prevented |
| [`decisions/DECISION-001-ai-boundaries.md`](decisions/DECISION-001-ai-boundaries.md) | What AI may and may not decide |

## History

Milestone narratives, moved out of `PROJECT_STATE.md` so the current-state
snapshot stays a snapshot. **These describe the past, not the present.**

| File | Milestones |
|---|---|
| [`history/foundation-p01-p04.md`](history/foundation-p01-p04.md) | Environment inventory, repository hardening, architecture and decision baseline, GHL MCP access, the four capability probes |
| [`history/ghl-leg-p05-p07.md`](history/ghl-leg-p05-p07.md) | The GHL tramo (P05) and the re-inquiry branch (P07), including TC-02b's double demotion |
| [`history/n8n-leg-p06-p08.md`](history/n8n-leg-p06-p08.md) | Ingress and the durable backup (P06), then retry, terminal handoff, fault injection and reconciliation (P08) |

## Conventions this documentation holds itself to

- **Never mark a capability or test `PASS` without observed evidence attached.**
- **Distinguish discovered / executed / absent / unknown.** A schema-level
  inference ("the operation exists") is never presented as a verified capability
  ("the operation works").
- **A passing test proves the artifact it ran against and nothing later.** Both
  n8n and GHL keep a draft alongside a published version.
- **A sequential test proves sequential behaviour only.** It is never
  generalized into a claim about concurrency.
- **All data is fictional.** No secrets, tokens, location or account IDs, or
  real customer data anywhere in this repository.
</content>
