# Test Cases

Behavioural test matrix for the GHL leadflow demo. **This file is the status
index.** Full input, expected outcome, and observed evidence for every executed
scenario live under [`docs/evidence/`](docs/evidence/).

**Ten scenarios pass against the currently deployed artifacts: TC-01, TC-02,
TC-03, TC-09, TC-10, TC-11, TC-12, TC-17, TC-18 and TC-19.** **TC-02b passed
too, but against a GHL workflow that no longer exists.** **TC-17 passed on
2026-08-10** — the sweep recovered six opportunities that had no backup row and
a second run wrote nothing — **and the run that passed it also found a defect**:
`Log Reconciled` writes three `run_log` rows per recovery instead of one. The
pass covers recovery and idempotence; it does not claim the reconciliation log
is accurate.

This file was written before the implementation so the acceptance criteria
cannot drift to match whatever happens to work. Where a pass rests on deduced
rather than directly read evidence, the evidence file says so.

## Status vocabulary

| Status | Meaning |
|---|---|
| `BLOCKED` | Cannot be executed yet — a named prerequisite does not exist. |
| `NOT RUN` | Executable in principle, but not yet attempted. |
| `PASS` | Executed, and observed output matched Expected. Never set this from reasoning alone. |
| `FAIL` | Executed, and observed output did not match Expected. |

A `PASS` with no evidence recorded in `docs/evidence/` is a defect in this
document.

## Matrix

**Version covered** records the artifact a pass was actually observed against.
A passing test proves that version and nothing later — n8n keeps a draft and an
active version, and saving changes only the draft
([`docs/n8n/operations.md`](docs/n8n/operations.md) §1); a GHL workflow edit can
sit unpublished the same way, and the version number is the only
machine-checkable proof it shipped.

| ID | Purpose | Status | Version covered | Evidence |
|---|---|---|---|---|
| TC-01 | New lead, happy path — one Contact, one Opportunity, one backup row, one `correlationId` | PASS | n8n `b162ad3f` (exec 6); n8n-side re-run on the P08 build (exec 20); GHL side partially re-covered at v12 by TC-03's submission 1 | [GHL](docs/evidence/ghl-tests.md#tc-01--new-lead-happy-path) |
| TC-02 | Duplicate **delivery** — webhook redelivered, must not produce a second row | PASS | n8n `b162ad3f` (exec 7); re-verified exec 10, and on the P08 build as exec 22 | [n8n](docs/evidence/n8n-reliability-tests.md#tc-02--duplicate-delivery-webhook-redelivered) |
| TC-02b | Duplicate **form submission** — same person submits twice | PASS — pre-P07 artifact only; re-run required | **GHL v9 with `Allow Re-entry` off.** The deployed artifact is v12 — this pass does **not** cover it | [GHL](docs/evidence/ghl-tests.md#tc-02b--duplicate-form-submission-same-person-submits-twice) |
| TC-03 | **Genuine re-inquiry** — same person, different intent, amplified rather than swallowed | PASS | GHL **v12**; n8n unchanged since exec 11 | [GHL](docs/evidence/ghl-tests.md#tc-03--genuine-re-inquiry-same-person-different-intent) |
| TC-04 | Service routing — service A | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable | — | — |
| TC-05 | Service routing — service B | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable | — | — |
| TC-06 | Service routing — service C | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable | — | — |
| TC-07 | Service routing — service D | BLOCKED (P-GHL, P-N8N) — deferred until TC-01 is stable | — | — |
| TC-08 | Unknown or missing service value | BLOCKED (P-GHL, P-N8N) | — | — |
| TC-09 | Required field absent — rejected before any business write | PASS | P08 n8n `c1225347` (exec 18) — **not** re-run against the hardened `4ab773e2` | [n8n](docs/evidence/n8n-reliability-tests.md#tc-09--required-field-absent) |
| TC-10 | Downstream write temporarily failing — detected, persisted, retry scheduled | PASS | P08 hardened `4ab773e2` (exec 42) | [n8n](docs/evidence/n8n-reliability-tests.md#tc-10--downstream-webhook-temporarily-failing) |
| TC-11 | Retry succeeds after transient failure — converges on exactly one record | PASS | P08 hardened `4ab773e2` (exec 42) | [n8n](docs/evidence/n8n-reliability-tests.md#tc-11--retry-succeeds-after-transient-failure) |
| TC-12 | Retry exhausted — terminal failed state, human handoff, not silent loss | PASS — retry ladder and terminal state observed pre-hardening; the hardened exhaustion branch is unexercised | P08 n8n `c1225347` (exec 31) — **not** re-run against the hardened `4ab773e2` | [n8n](docs/evidence/n8n-reliability-tests.md#tc-12--retry-exhausted) |
| TC-13 | Appointment booked | BLOCKED (P-GHL, P-CAL) — deferred until TC-01 is stable | — | — |
| TC-14 | Appointment no-show or cancellation | BLOCKED (P-GHL, P-CAL) — deferred until TC-01 is stable | — | — |
| TC-15 | Human review — AI declines to classify | BLOCKED (P-GHL, P-N8N) | — | — |
| TC-16 | Human review — financial boundary | BLOCKED (P-GHL, P-N8N) | — | — |
| TC-17 | **Reconciliation recovers a lost webhook** | PASS — six recovered, second run wrote nothing; one defect found in `run_log` | Sweep `LbfiJvlXEWvVGhzh` version `09f0c52c` (exec 45 recovery, exec 49 idempotence) | [reconciliation](docs/evidence/reconciliation-tests.md#tc-17--reconciliation-recovers-a-lost-webhook) |
| TC-18 | Unauthorized webhook rejected — 401, no business write | PASS | P08 n8n `c1225347` (exec 37, wrong-value arm); the absent-secret arm's evidence is pre-`b162ad3f` and was **not** re-run | [security](docs/evidence/security-tests.md#tc-18--unauthorized-webhook-rejected) |
| TC-19 | **Formula injection through the public form** — stored as literal text | PASS | P08 n8n `c1225347` (exec 35) | [security](docs/evidence/security-tests.md#tc-19--formula-injection-through-the-public-form) |

Four things are weaker than this matrix alone suggests, and each is stated in
its evidence file rather than buried: **TC-02b's pass no longer covers the
deployed GHL workflow**; **the duplicate-opportunity guard has never been
exercised** by any test; **TC-17's pass came with a defect in the same run** —
`run_log` overstates reconciliation three-fold, cause not yet known; and **all
evidence is sequential** — nothing here says anything about concurrency.

## Prerequisites

Scenarios are blocked on whichever of these does not yet exist:

- **P-GHL** — a GoHighLevel test location with a pipeline, custom fields, and a
  lead-capture form. **Satisfied (P05)** — see [`PROJECT_STATE.md`](PROJECT_STATE.md).
- **P-N8N** — a reachable n8n instance with the inbound webhook deployed.
  **Satisfied (P06)** — n8n Cloud, workflow published and active on its
  production webhook URL.
- **P-SHEET** — a Google Sheet configured as the backup destination.
  **Satisfied (P06)** — `leads_backup` and `run_log` are written on the live
  path. `needs_human` is **written for the first time in P08** — TC-12's
  retry-exhaustion handoff lands there. TC-08's routing still does not.
- **P-CAL** — a GoHighLevel calendar configured for appointment booking.
  **Not satisfied.**

## Deferred scenarios — input and expected outcome

The first golden path is a **single service type**. These are written now so the
design accounts for them, not because they are next. The reliability scenarios
(**TC-09 through TC-12**, plus **TC-17** and **TC-18**) are **not** deferred —
they are the point of the demo.

| ID | Input | Expected |
|---|---|---|
| TC-04 | Valid lead, `service = A` | Opportunity lands in the pipeline path designated for A; assignment and notification match A's rule |
| TC-05 | Valid lead, `service = B` | Opportunity lands in the pipeline path designated for B |
| TC-06 | Valid lead, `service = C` | Opportunity lands in the pipeline path designated for C |
| TC-07 | Valid lead, `service = D` | Opportunity lands in the pipeline path designated for D |
| TC-08 | Valid lead, `service` absent or not in the known set | Lead is not dropped and not guessed into a service; it is routed to human review with the raw value preserved |
| TC-13 | Qualified lead books a slot on the connected calendar | Appointment is created; the opportunity advances to the appointment stage; the backup record reflects the appointment |
| TC-14 | A booked appointment is cancelled | Opportunity does not remain stuck in the appointment stage; it returns to follow-up rather than being marked lost automatically |
| TC-15 | Lead whose free-text intent is ambiguous to the classifier | AI output is recorded as a suggestion only; the lead is flagged for human review; no financial approve/reject decision is taken by the AI |
| TC-16 | Lead containing an explicit financing request | The AI may summarize and extract, and must not approve or reject; the lead is routed to a human with the extracted summary attached; no AI-written value appears in any stage or approval field |

## Evidence policy

When a scenario is executed, the evidence file records what was observed — the
created record identifiers, the log correlation id, and the screenshot or export
used as proof. Scenarios move to `PASS` only with that evidence attached. Test
data is fictional throughout; no real person's contact details are used at any
point.

**One already-passing row was demoted, not polished.** TC-02b's attribution was
wrong and its pass no longer covers the deployed GHL workflow — the artifact
changed underneath it. Both facts are recorded in place rather than rewritten,
because how a passing test can prove less than it claimed is worth more than a
clean matrix. **TC-02b needs re-running against v12** — it is next action 2 in
[`PROJECT_STATE.md`](PROJECT_STATE.md).

**P08 re-verified four earlier rows rather than assuming them.** The rebuild
spliced a retry loop into the happy path, rewrote `Normalize and Authorize`, and
reparameterized `Sheets: leads_backup` — so TC-01, TC-02, TC-18 and TC-19 were
all covering an artifact that no longer existed. Each was re-run. That is the
discipline TC-02b's demotion taught this file, applied before it could bite a
second time.

## Related

- [`docs/evidence/ghl-tests.md`](docs/evidence/ghl-tests.md) — TC-01, TC-02b, TC-03
- [`docs/evidence/n8n-reliability-tests.md`](docs/evidence/n8n-reliability-tests.md) — TC-02, TC-09 through TC-12
- [`docs/evidence/security-tests.md`](docs/evidence/security-tests.md) — TC-18, TC-19
- [`docs/evidence/reconciliation-tests.md`](docs/evidence/reconciliation-tests.md) — TC-17
- [`docs/n8n/testing.md`](docs/n8n/testing.md) — how to run these scenarios again
</content>
