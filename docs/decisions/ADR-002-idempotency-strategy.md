# ADR-002 — Idempotency strategy

- **Status:** Accepted
- **Date:** 2026-08-08
- **Scope:** every write this pipeline performs against GoHighLevel or a downstream store

## Context

Lead delivery is at-least-once in practice. Webhook senders retry on timeout,
users double-click submit buttons, ad platforms redeliver, and a crashed
integration re-processes on recovery. Any of these produces the same event
twice.

The consequences are not academic. Two contacts for one person means two
salespeople call them, the pipeline count is wrong, and the CRM stops being
trustworthy — which is the entire product.

The trap is that "duplicate" names two genuinely different situations that
demand opposite handling:

- The **same submission** arriving twice, because our plumbing retried.
- The **same person** submitting twice, because they are interested again.

Treating these as one problem produces one of two failures. Deduplicating on
the person suppresses real re-inquiries — silently dropping a hot lead, the
worst outcome this system can produce. Deduplicating on nothing fills the CRM
with retry noise.

A further constraint shapes everything: **the only identifiers GHL can give us
do not exist until GHL has already written the record.** `contactId` is a
result of the operation we are trying to make repeatable, so it cannot be the
key that makes it repeatable.

## Decision

### `externalLeadId` is the primary identity

**`externalLeadId` identifies exactly one submission event.** Not a person, and
not a delivery. Format: `{source}:{sourceEventId}`.

It is minted in strict preference order:

1. **A source-native id.** Facebook Lead Ads supplies `leadgen_id` →
   `fb:leadgen_1234567890`. A GHL form supplies a submission id →
   `ghlform:{submissionId}`.
2. **Generated at the source we control.** The landing page generates a UUID
   client-side into a hidden field on first render and resubmits the same value
   → `lp:8f2c1a...`. This is the best case and should be built, because it
   survives browser retries and double-clicks.
3. **Derived**, when the source supplies nothing:

```
externalLeadId = "drv:" + sha256(
    lower(trim(email)) + "|" +
    e164(phone)        + "|" +
    source             + "|" +
    formId             + "|" +
    floor(sourceSubmittedAtEpochSeconds / 300)
)
```

The five-minute bucket collapses redeliveries of one submission — which arrive
seconds apart — while letting a genuine re-inquiry three days later mint a
different id.

**The bucket has a real flaw and it is not hidden:** a boundary can split a true
duplicate (14:59:59 versus 15:00:01). The mitigation is to hash the
**source-provided** `submittedAt`, never our receive time, so a redelivery
carries the same timestamp and lands in the same bucket. The flaw then only
bites for sources that supply no timestamp at all. That case is irreducible and
is documented rather than papered over.

### `contactId` is a secondary identity, available only after persistence

The chain runs `externalLeadId` (pre-CRM) → `contactId` (post-persistence) →
`opportunityId`.

**Never key a retry on `contactId`**, because the retry may be of the exact
request that would have produced it.

The id is written back into GHL — `external_lead_id` on the Opportunity,
`last_external_lead_id` on the Contact. That makes the CRM self-describing and
allows reconciliation even if the ledger is lost entirely.

### Email and phone are secondary signals, never universal substitutes

They fail as primary identity for two independent reasons.

**They are not universal.** Facebook lead forms often return a phone and no
email. Emails get typo'd. Households share addresses. Phone formatting varies.
One person legitimately owns two email addresses.

**They are not event-scoped.** They identify a *person*, not a *submission*.
Keying dedup on them would suppress genuine second inquiries.

Where they legitimately help, and are used:

1. **Person resolution** — finding the existing contact *after* event-level dedup has already passed.
2. **Fallback derivation input**, above.
3. **Human investigation** — a person searching the CRM uses a phone number, not a hash.
4. **Soft duplicate-person detection** — name matches but contact details differ, so flag `possible-duplicate-person` and route to human review. A signal, never an automatic merge.

### Receiving the same event twice

Observable outcome, per layer:

| Layer | First delivery | Second delivery |
|---|---|---|
| HTTP response | `200 accepted` | `200 accepted` — **identical** |
| *(contrast: bad secret)* | `401` | `401` — rejected synchronously, never acked |
| *(contrast: invalid payload)* | `422` | `422` — deterministic, non-retryable |
| Ledger | insert `claimed`, then `completed` | lookup **hit**, short-circuit |
| GHL API | contact upsert, opportunity create, field writes | **zero API calls** |
| AI enrichment | called once | **not called** |
| `leads_backup` | one row | zero rows |
| `run_log` | one row, `outcome=processed` | one row, `outcome=duplicate_event` |
| Notification | one | zero |

Two details are deliberate:

**The response is 200, not a 4xx.** A duplicate is not the sender's error. A 4xx
makes senders retry harder or page someone, converting a non-event into an
incident.

**Zero GHL calls, not "idempotent writes".** The cheapest safe write is the one
never issued.

### Receiving a different event for the same person

The ledger keys **events**, so a genuine second inquiry **misses** and proceeds.
That is correct and intentional.

Person resolution then runs — normalized email, then E.164 phone — and GHL's
contact upsert converges on one contact. The business branch follows:

- **An open opportunity exists** → append a note, increment `inquiry_count`, tag
  `repeat-inquiry`, and pull it back to `Contacting` if it had drifted to
  `Follow-up`.
- **No open opportunity** → create a new Opportunity in `New Lead`.

Net state: **one contact, N opportunities, N backup rows.**

Stated plainly: *a duplicate event is an infrastructure artifact that must be
erased; a duplicate person is a business signal that must be amplified.*

### The ledger, and the race window

**Two-phase claim.** Append `claimed` **before** the first GHL write; append
`completed` **after** GHL confirms. A redelivery seeing `completed`
short-circuits. A redelivery seeing a **stale** `claimed` proceeds, but in
read-before-rewrite mode.

The ordering is forced. Writing the ledger only *after* the CRM means a crash in
between produces a duplicate. Writing it only *before* means a GHL failure
permanently suppresses the retry — a lost lead, which is worse.

**The race window, honestly.** This is a check-then-write, not a transaction.
Two truly concurrent identical events can both miss:

- A spreadsheet-backed ledger: read plus append is roughly **one to two
  seconds** of exposure. Not fixable — a spreadsheet has no compare-and-set.
- A database-backed ledger shrinks it to tens of milliseconds, and still is not
  atomic.

Two things were intended to bound the damage. **Both have now been checked
against a live trial location (2026-08-08), and the result is mixed — one
does not exist, the other partially holds:**

- **A second independent check at the GHL layer** — query opportunities by
  `external_lead_id` before creating one. **Resolved, unfavourably.**
  `describe_operation` on `search-opportunity` shows its complete parameter
  schema (`assignedTo`, `campaignId`, `contactId`, `country`, `date`,
  `endDate`, `id`, `pipelineId`, `pipelineStageId`, `q`, `status`, pagination)
  — **no parameter accepts a custom-field key or value.** This check cannot be
  built against the operation as discovered. It is not merely unverified; it
  is confirmed absent. See [`integration-options.md`](../integration-options.md)
  §5 item 12.
- **GHL's contact upsert deduplicates on email and/or phone.** **Resolved,
  favourably, for the matching question only.** A live sequential probe ran
  two scenarios against fictional fixtures: (A) same email, different phone,
  two `upsert-contact` calls; (B) same phone, different email, two calls. Both
  merged into a single contact — **the match succeeds on email OR phone
  independently, either field alone is sufficient**, and the differing field
  is overwritten with the latest call's value. **Concurrent-call behaviour
  remains [ASSUMPTION]** — the probe was strictly sequential by design (each
  call's response was confirmed via `get-duplicate-contact` before the next
  call was issued) and answers only "what field does it match on," not "what
  happens when two calls race." See [`integration-options.md`](../integration-options.md)
  §5 item 11.

**Net effect on the race window:** the ledger's check-then-write gap is now
bounded on the *contact* side (a duplicate contact from a race is prevented by
the confirmed email-or-phone match) but **unbounded on the *opportunity*
side** — the one mitigation that would have caught a raced duplicate
opportunity does not exist as discovered. This is a real design gap the next
phase should address (see Consequences), not a residual formality.

Note also **where the ledger sits** — see [`../architecture.md`](../architecture.md)
§6.0. On the GHL-native ingress path the CRM record already exists by the time
the webhook fires, so the ledger prevents duplicate *processing* rather than the
duplicate CRM record itself.

In practice webhook retries arrive seconds apart rather than truly
concurrently, which makes the window mostly theoretical here. That is an
**assumption about GHL's retry behaviour that we have not verified**, not a
guarantee.

## Alternatives considered

**Deduplicate on email or phone.** Simplest, and needs no new identifier.
Rejected because it silently swallows genuine re-inquiries — trading a visible,
tolerable problem (a duplicate record) for an invisible, expensive one (a lost
hot lead). It also fails outright for sources that supply only one of the two.

**Deduplicate on `contactId` after creating the contact.** Rejected on ordering:
the id does not exist until the operation we are protecting has already run. It
answers the question too late to be useful.

**Rely on GHL's native contact deduplication alone.** It genuinely helps and is
used — it is what makes a duplicate *contact* impossible. Rejected as the whole
answer because it operates on people, not events, so it does nothing to stop a
webhook redelivery creating a second *opportunity*.

**A real transactional store with a unique index.** The correct answer, and
what production should use. Rejected for this sprint only because it adds
infrastructure the two-day window cannot absorb. Recorded as the known upgrade
path rather than pretended away.

**Content hashing of the whole payload.** Rejected because payloads vary in
irrelevant ways between redeliveries — timestamps, header echoes, enrichment
added in flight — so identical submissions hash differently. It produces
false negatives exactly when it matters.

## Consequences

**Good.**

- Duplicate events are erased and duplicate people are amplified — the two
  cases get opposite handling because they are opposite problems.
- Retry becomes safe to reason about, because identity exists before the write.
- Writing the id back into GHL means reconciliation works even if the ledger is
  lost entirely.
- The design degrades honestly: the race window is quantified rather than
  denied.

**Costs, accepted deliberately.**

- **Not exactly-once**, and the documentation says so.
- The derived fallback has a bucket-boundary flaw for sources with no timestamp.
- Every source integration must be checked for a native event id, which is real
  per-source work.
- A ledger read is added to the hot path of every delivery.

**Consequences to watch.**

- The ledger becomes a dependency of correctness. If it is unavailable, the safe
  behaviour is to proceed and risk a duplicate rather than to drop the lead —
  duplicates are recoverable, lost leads are not.
- A stale `claimed` entry needs a timeout, or a crash mid-flow permanently
  blocks that event's retry.
- **New, confirmed 2026-08-08: the opportunity-side race mitigation does not
  exist.** `search-opportunity` cannot filter by `external_lead_id` or any
  other custom field. A raced duplicate opportunity is caught only by the
  ledger's own check-then-write, whose window this ADR already documents as
  open. The reconciliation sweep (§7 of `architecture.md`) becomes more
  load-bearing as a result, since it is the only remaining backstop for a
  duplicate opportunity that slips the ledger. A follow-up decision — either
  fetch-and-filter client-side on `external_lead_id`, or accept the exposure
  as documented residual risk — belongs to a later phase, not P04.
- **Update, same day (P05): a different opportunity-side guard now exists for
  P0, but it does not close the gap above — it closes a different one.**
  The location's `allowDuplicateOpportunity` setting is `false`, confirmed
  live via `get-location`, and the `Create Opportunity` workflow action
  additionally carries its own `Duplicate Opportunity: Disabled` toggle. Both
  are very likely one server-side check exposed at two configuration
  surfaces, not two independent layers — treat it as one guard, not
  defense-in-depth. It is **not** the `external_lead_id` pre-create query
  this ADR wanted; that remains confirmed unbuildable. The guard GHL actually
  offers is **person-scoped** (one open opportunity per contact), not
  **event-scoped**. That distinction has a real cost: because the guard
  cannot tell a low-effort accidental resubmission from a genuine
  re-inquiry, **the compensating branch this ADR requires for a real
  re-inquiry — append a note, increment `inquiry_count`, tag
  `repeat-inquiry` — is not built in P0.** While a contact has an open
  opportunity, a genuine new inquiry currently produces no second
  opportunity and no webhook — silently. That is the exact failure this ADR
  already names as "the worst outcome this system can produce," now reached
  through a path this ADR had not anticipated. Recorded as a residual for
  the next phase (build the compensating branch, or scope the guard to a
  shorter window), not silently accepted — see
  [`architecture.md`](../architecture.md) §6.0. TC-02b (P05) proves only the
  intended case — quick, sequential duplicate submission of the identical
  fixture, ~1 minute apart, well outside this ADR's 1–2s race window and
  therefore evidence of nothing concurrent — passes. It does not exercise or
  validate the re-inquiry branch; that remains TC-03, still blocked.
  **Downstream delivery identity for this path:** the webhook payload
  already carries `opportunityId` once GHL creates it (§6.0), so the
  identity a future n8n ledger uses to dedupe *redeliveries of that webhook*
  is `ghl:opportunity-created:<opportunityId>` — distinct from
  `externalLeadId` above, which identifies the original submission event and
  is not yet populated by this phase's workflow (`external_lead_id` exists
  as a schema field on the Opportunity but nothing writes to it in P0).
  `ghl:opportunity-created:<opportunityId>` only exists once GHL has already
  created the record, so — consistent with "never key a retry on
  `contactId`" above — it must never be used to decide *whether* to create
  that Opportunity, only to dedupe deliveries of one that already exists.

## Related

- [`../architecture.md`](../architecture.md) — §6 identity and idempotency
- [`../diagrams/reliability.md`](../diagrams/reliability.md) — where the checks sit in the flow
- [ADR-001](ADR-001-integration-hierarchy.md) — integration hierarchy
- [`../../TEST_CASES.md`](../../TEST_CASES.md) — TC-02 and TC-03 exist to prove this
