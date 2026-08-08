# Diagram — Lead lifecycle

The states a lead passes through, and — just as importantly — the conditions
that are deliberately **not** modelled as states.

## Pipeline stages

Only these appear on the board a salesperson works.

```mermaid
stateDiagram-v2
    state "New Lead" as NewLead
    state "Contacting" as Contacting
    state "Contacted" as Contacted
    state "Qualified" as Qualified
    state "Appointment" as Appointment
    state "Follow-up" as FollowUp
    state "Closed - status won or lost" as Closed

    [*] --> NewLead
    NewLead --> Contacting
    Contacting --> Contacted
    Contacted --> Qualified
    Qualified --> Appointment
    Appointment --> FollowUp
    Contacted --> FollowUp
    Qualified --> FollowUp
    FollowUp --> Contacting
    Contacting --> Closed
    Contacted --> Closed
    Qualified --> Closed
    Appointment --> Closed
    FollowUp --> Closed
    Closed --> [*]

    Contacting --> Contacting: no response - attempts incremented
    NewLead --> NewLead: repeat inquiry - note appended
    Qualified --> Qualified: needs human - automation paused
```

**Won and Lost are not stages.** A GHL Opportunity carries a native `status`
field. Keeping the outcome in `status` rather than in two terminal stages means
the board shows only live work while win-rate reporting still works.

**Self-transitions are flags, not movement.** A lead that gets no response stays
in `Contacting` — a counter changes, the stage does not. Modelling it as a stage
would force a lead that answers on day four to be dragged *backwards*, which
corrupts stage-duration metrics and teaches reps to distrust the board.

## Where each exceptional condition lives

```mermaid
flowchart TB
  subgraph STAGE["Pipeline stages - the human works these"]
    S1["New Lead"]
    S2["Contacting"]
    S3["Contacted"]
    S4["Qualified"]
    S5["Appointment"]
    S6["Follow-up"]
    S7["Closed"]
  end

  subgraph FLAG["Flags on the CRM record - visible, filterable, not stages"]
    F1["no-response plus contact_attempts"]
    F2["repeat-inquiry - a returning person"]
    F3["needs-human - blocks automatic stage advance"]
    F4["integration-error - only after a partial CRM write"]
  end

  subgraph NEVER["Never reaches the CRM - integration layer only"]
    N1["Duplicate event - webhook redelivered"]
    N2["Retry and backoff attempts"]
    N3["Transient failure before any CRM write"]
    N4["Unauthorized or malformed request"]
  end

  subgraph EVID["Where the invisible things are visible instead"]
    L1["Sheets run_log"]
    L2["Sheets needs_human"]
    L3["Sheets dead_letter"]
  end

  S2 -.->|"after N attempts"| S6
  F1 -.-> S2
  F3 -.-> S4
  F2 -.-> S1
  F4 -.-> S5

  N1 --> L1
  N2 --> L1
  N3 --> L1
  N3 --> L3
  N4 --> L1
  F3 --> L2
  F4 --> L2
```

## The rule that produced this split

> **Changes what a human does next → STAGE.**
> **Changes what the system does next → FLAG on the record.**
> **Only describes how the plumbing behaved → never reaches the CRM at all.**

Applying it to the hard cases:

| Condition | Call | Reasoning |
|---|---|---|
| **No Response** | Flag | The human keeps doing the same thing — calling. Nothing about their work changes, so nothing on the board should. After N attempts the *cadence* genuinely changes, and that transition to `Follow-up` is a real stage change. |
| **Duplicate event** | Never in the CRM | A webhook retry is our plumbing. A rep must not be able to tell from the CRM that our infrastructure was flaky. Zero artifacts — not even a note. |
| **Duplicate person** | Flag, and business-meaningful | A returning lead is a hot buying signal, the opposite of noise. It is amplified, not suppressed. Still not a stage: it describes how the deal *arrived*, not where it *is*. |
| **Requires Human** | Flag plus queue | It is orthogonal to position — it can fire at qualification, at pricing, or at document review. As a stage it would erase where the lead actually was, and you would have to guess on return. |
| **Error** | Integration layer, with one exception | Failing before touching GHL leaves nothing in GHL to mark, and a phantom "failed lead" is not something a rep can act on. But a failure *after* a partial write means the CRM itself is now inconsistent — and then a human must see it there. |
| **Retry** | Never in the CRM | Retry is a mechanism, not a state. The lead does not know it is being retried, and neither should the salesperson. |

The two hardest calls are **duplicate event** and **error**, and they share a
shape: the CRM is told only what a human can act on. Everything else is
observable in the log, where the people who maintain the pipeline look.

## Related

- [`../architecture.md`](../architecture.md) — the full lifecycle rationale
- [`reliability.md`](reliability.md) — what happens to the conditions on the right
- [`../../TEST_CASES.md`](../../TEST_CASES.md) — TC-02, TC-03, TC-08, TC-15
