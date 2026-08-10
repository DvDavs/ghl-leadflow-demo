# Project state

Current-state snapshot, and the only file that describes what is true today.
History is in [`docs/history/`](docs/history/), test evidence in
[`docs/evidence/`](docs/evidence/), the reading route in
[`docs/INDEX.md`](docs/INDEX.md).

## Goal

Build a demonstrable, reliable lead-flow integration between a lead source, a
GoHighLevel CRM location, an n8n automation layer, and a Google Sheets backup —
and be able to explain and defend every design decision in an interview. The
deliverable is not "a workflow that fires once": it is a pipeline that survives
duplicate events, missing fields, and downstream failures, and that can prove it
did so.

## Current milestone

**Milestone 7 — failure, retry and human handoff (P08, closed out by P08B).
Complete: the retry half and reconciliation are both built, published, active
and evidenced.**

A downstream failure no longer loses the lead and no longer lies to the sender:
the write is answered `202 retry_scheduled` and retried on a bounded ladder held
by a database-persisted wait; a transient failure that clears converges on
exactly one backup row; one that does not ends in a ledger `failed`, a
`needs_human` row, and a `run_log` outcome distinct from a validation rejection.
Validation also stopped rejecting phone-only leads.

**And a webhook that never arrives is no longer unrecoverable.** The sweep runs
every 10 minutes against a read-only GHL credential; on its first live run it
recovered the six opportunities that had sat in the CRM with no backup row, and
its second run wrote nothing. It also found a defect in itself — see
"Open risks".

## What is built and live

| Leg | State |
|---|---|
| **GHL (P05, P07)** | Form → Contact → Opportunity → Pipeline runs live. 7 P0 custom fields, 5 P0 tags, `LeadFlow Demo Pipeline` (7 stages), the Service Inquiry form, and `Form to Opportunity` **v12** with the re-inquiry branch — all published. Pipeline, form and workflow are UI-only; no MCP write operation exists for any of the three |
| **n8n ingress (P06)** | Webhook → allowlist normalization → shared-secret check → ledger claim → `leads_backup` (Append or Update on `eventId`) → ledger `completed`, with deterministic 401 / 422 / 200 / 200-duplicate / 202 responses and append-only `run_log` boundaries. Published and active |
| **n8n reliability (P08)** | Bounded retry (3 attempts, 70s base, ×2, +0–20% jitter, 300s cap) on a database-persisted `Wait`; terminal `needs_human` handoff; operator-only append-only fault switch, left `off`; node-level retry on every write between the claim and a terminal state |
| **Reconciliation (P08B)** | 12-node sweep **published, active, on a 10-minute schedule**. Reads `GET /opportunities/search` with a Header Auth credential holding a sub-account PIT scoped to `opportunities.readonly`; `location_id` is **accepted** by GHL, though not proven to be *read* — the sub-account token already implies the location. TC-17 passed: 6 recovered, second run wrote nothing |
| **Test harness (P08)** | Two manual-trigger-only n8n workflows: a sender that injects the secret at send time, and an evidence reader over the three sheet tabs, the ledger and the fault switch. Neither has a public trigger |

Artifacts under [`n8n/workflows/`](n8n/workflows/) and
[`scripts/replay-webhook.ps1`](scripts/replay-webhook.ps1).

## Test status

**Ten of twenty scenarios pass against the deployed artifacts:** TC-01, TC-02,
TC-03, TC-09, TC-10, TC-11, TC-12, **TC-17**, TC-18, TC-19. **TC-02b passed
against a GHL workflow that no longer exists** and needs re-running against v12.
**TC-17's pass covers recovery and idempotence, not log accuracy** — the same
run found the `run_log` triplication below. The remaining nine are `BLOCKED` or
deliberately deferred. Per-row status, version coverage and evidence links:
[`TEST_CASES.md`](TEST_CASES.md).

## Issues and project board

The GitHub Project board (*GHL Leadflow Demo Sprint*) is the source of truth.
**Read back after P08B, observed rather than assumed:** 17 items — **ten Done,
#11 Ready, #12 Blocked, five Backlog**.

**P08B closed #10** (failure, retry and observability) and moved it In Progress
→ Done: TC-09 through TC-12 already passed, and TC-17, its last named residual,
now passes too. **#11 moved Blocked → Ready** because #10 was its only stated
dependency. #12 stays Blocked on its own dependency, not on this work.

Re-read the board rather than trusting this section; the repository has twice
been bitten by treating a change that *should* have landed as one that did.

## Blocked

- **TC-02b — not re-run against GHL v12**, and **pre-P07 `inquiry_count` null
  safety — not addressed.** Both need live submissions of the public form. The
  form still has no documented submit endpoint, but **Playwright is now
  available**, so browser automation is no longer the missing piece it was in
  P08.
- **Docker engine is stopped**, so container-level inventory is undetermined.
  Only relevant if the Docker + ngrok fallback is ever needed.

## Open risks

**Evidence and coverage**

| Risk | Detail |
|---|---|
| **The duplicate-opportunity guard has never been exercised.** Configured and person-scoped, sitting as a backstop behind the `Find Opportunity` split. The event-scoped mitigation ADR-002 wanted still does not exist — `search-opportunity` cannot filter by `external_lead_id` | [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) "Consequences to watch" |
| **All evidence is sequential.** Nothing anywhere in this repository says anything about concurrency | [`TEST_CASES.md`](TEST_CASES.md) |
| **TC-12's hardened exhaustion branch is unexercised**, and TC-09, TC-18 and TC-19 cover active version `c1225347`, one publish before the deployed `4ab773e2` | [`TEST_CASES.md`](TEST_CASES.md) |
| **`Log Reconciled` writes three `run_log` rows per recovery, not one.** Six recoveries left 18 rows. Node time 14–18 s each against `maxTries: 3 / waitBetweenTries: 5000` — two failed attempts that each still landed a row, then a success. **Cause unknown**: n8n does not persist a retried node's intermediate errors. `leads_backup` and the ledger are unaffected (both converge; both deltas were exactly +6). Do **not** disable `retryOnFail` to hide it | [evidence](docs/evidence/reconciliation-tests.md) · [operations](docs/n8n/operations.md) §5 |
| **TC-17 has no unconsumed test data left.** The six orphaned opportunities were the scenario's fixtures and run 1 recovered all six. Re-running it needs a fresh opportunity whose webhook does not reach n8n | [evidence](docs/evidence/reconciliation-tests.md) |
| **`README.md` is now factually wrong and is the first thing a public reader sees.** Its banner still says reconciliation is blocked on a missing credential, the sweep is "built and published, inactive", and "nine of twenty" scenarios pass. P08B's scope was explicitly limited to four files, so it was left untouched **deliberately, not by oversight** — but it contradicts this file and must be corrected in a follow-up commit | `README.md` lines 6, 9, 12–14, 82, 176 |
| **`location_id` is accepted by GHL but not proven to be read.** The sub-account token already implies the location, so the parameter may be ignored; `meta.nextPageUrl` echoing it proves an echo, not a parse. No control run was made. Settled for this sweep, open as a general claim — do not quote it as "GHL's opportunity search takes `location_id`" | [evidence](docs/evidence/reconciliation-tests.md) |

**Silent-loss paths still open**

| Risk | Detail |
|---|---|
| **A retry that dies mid-wait is not re-driven** — the deliberate trade for keeping one copy of the backup-write node. **Live instance:** ledger row `id=5`, `ghl:opportunity-created:p08-tc10-transient`, synthetic and therefore unrecoverable by any sweep | [operations](docs/n8n/operations.md) §6 |
| **A `failed` ledger row is not proof a human was told** — ledger row `id=7` is exactly that case. Judge the handoff on the `needs_human` row, never the ledger alone | [operations](docs/n8n/operations.md) §4 |
| **A re-inquiry leaves no `leads_backup` row and reconciliation cannot find it**, so `architecture.md` §5's "Sheets is event-grained" is not yet true for re-inquiries. **Not a TC-17 instance.** Deferred deliberately; both available shortcuts are actively harmful | [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) item 2 |
| **The re-inquiry branch is pipeline-scoped; the guard it compensates for is person-scoped**, so a contact whose open opportunity sits in another pipeline still falls through to the silent swallow, now with `inquiry_count = 1` written over it. Unreachable in a single-pipeline demo; the fix is one filter removal | [ghl-setup](docs/ghl-setup.md) "Two scope limits" |
| **`Math Operation` will hit a null for every contact created before P07.** `David Demo` and `Valeria Cruz` both have an open opportunity, so a resubmission takes the `Found` path into an increment on a null — undocumented and unobserved | [ghl-setup](docs/ghl-setup.md) build rule 3 |

**Traps that have already bitten once**

| Risk | Detail |
|---|---|
| **Saving a workflow is not publishing it** — in n8n *and* in GHL. A security fix looked applied for over an hour while production served the old version. Compare `activeVersionId` against `versionId`; for a GHL workflow the version number is the only machine-checkable proof an edit shipped | [operations](docs/n8n/operations.md) §1 |
| **`cellFormat: RAW` must survive every future edit to a Sheets node.** Re-picking a node in the UI can reset it to the `USER_ENTERED` default, silently re-opening formula injection from the public form | [setup](docs/n8n/setup.md) §5 |
| **Vendor documentation was wrong twice, and both errors were load-bearing.** Custom Data arrives nested under `customData`; `contact_id` does exist at the root despite the example omitting it. The first error cost six diagnostic deliveries. GHL also misspells its own field as `pipleline_stage` | [setup](docs/n8n/setup.md) |
| **The retry attempt counter depends on an undocumented n8n resolution rule** (`$('Retry Decision').first()`) — verified live across three attempts in TC-12, but not guaranteed. If the ladder ever repeats attempt 1, check this first | [operations](docs/n8n/operations.md) §6 |

**Known weaknesses of what is built**

| Risk | Detail |
|---|---|
| **The sweep recovers a thinner row than the webhook path** — `business` empty, `service` derived by splitting the Opportunity name on `" - "`, rows marked `lastAction=reconciled`. Adding `contacts.readonly` is a defensible upgrade; taking it silently is not. **The first live run added two differences nobody predicted:** `stage` is the raw `pipelineStageId` UUID, not `New Lead`, and `phone` is E.164, not the form's formatting — so recovered and delivered rows do not sort or filter alike | [operations](docs/n8n/operations.md) §5 |
| **An accidental double submission is indistinguishable from a genuine re-inquiry** and is treated as one — GHL supplies no submission id, and HighLevel's own feature request for one is open and unshipped. Deliberate direction: a visible duplicate is recoverable, a swallowed hot lead is not | [ghl-setup](docs/ghl-setup.md) "The tradeoff this accepts" |
| **`inquiry_count` is per-opportunity, not lifetime** — when the previous opportunity is won or lost, a new inquiry resets it to `1` | [ghl-setup](docs/ghl-setup.md) "Two scope limits" |
| **The Opportunity name is a snapshot from creation time**, so after a re-inquiry the board shows the original intent and the new one lives only in the note. `Sofia  Bennett - Real Estate` also carries a double space. Both cosmetic, both unfixed | [history](docs/history/ghl-leg-p05-p07.md) |

**Fixture noise** — documented rather than hidden, none dangerous, all noise in
a demo. Cleanup pending an explicit decision; nothing has been deleted.

| Risk | Detail |
|---|---|
| **Nine fictional diagnostic contacts pollute the demo location.** All nine now have a `leads_backup` row: three fired their webhook normally (Valeria Cruz, the `=1+1 Testcase` fixture, Priya Chandran) and **six were recovered by the sweep** on 2026-08-10, so they carry `lastAction=reconciled` | [evidence](docs/evidence/reconciliation-tests.md) |
| **P08 fixtures sit in the durable backup.** `p08-regress-alpha`, `p08-tc10b-transient` and `p08-tc19-formula` have `leads_backup` rows; `p08-tc12-persistent` and `p08-tc12b-persistent` are terminal `failed` with none. All fictional, all carrying `source = P08 Internal Test Harness` — the column to filter on before a demo | [operations](docs/n8n/operations.md) §6 |
| **The trial location's owner First/Last Name is still real** — not committed to git, not part of the interview-facing fixture, so not blocking, but still open after three UI correction attempts | [history](docs/history/ghl-leg-p05-p07.md) |

## Environment

| Area | State |
|---|---|
| Toolchain | Git, GitHub CLI, Node, npm, Claude Code present and verified |
| Docker | Installed, engine stopped |
| Playwright | **Connected.** It was absent in P08, which is why everything GHL-UI-shaped stalled there. It was not needed in P08B — the credential was bound to the sweep over the n8n MCP API without opening a browser — but it unblocks the GHL-UI work (TC-02b's re-run, the `inquiry_count` null fix) |
| n8n | **n8n Cloud live** — workflow published and active on its production webhook URL. Variables and Data Tables both confirmed available on the plan. MCP server connected, tools available |
| GoHighLevel | **Connected** — official MCP over OAuth, one trial location. No PIT. Operations require an explicit `locationId` even so |
| Google | **Sheets connected to n8n** via a credential-store OAuth2 credential, bound only to the native Sheets node. Sheet is private |
| Tunnel | ngrok installed, not running, auth state unconfirmed — only needed if n8n Cloud fallback triggers |

Detail in [`docs/environment.md`](docs/environment.md).

## Decisions

All 26, including the three ADRs, in
[`docs/decisions/decision-log.md`](docs/decisions/decision-log.md).

## Next 3 actions

1. **Find out why `Log Reconciled` needs three attempts.** It is the one open
   defect in an otherwise passing reliability story, and the retry errors are
   not in the execution record — so this needs a deliberate reproduction (force
   one recovery and watch the node live) rather than more log reading. Resist
   the tempting non-fix of turning `retryOnFail` off.
2. **Re-run TC-02b against GHL v12, and exercise the duplicate-opportunity guard
   for real.** Playwright is now available, so the public form can finally be
   submitted. With re-entry on, a fast double submission can reach
   `Create Opportunity` twice for one contact — the first test that would
   actually exercise the guard.
3. **Close the `inquiry_count` null on pre-P07 contacts**, and clean up the
   fixture noise: the orphaned `retry_scheduled` ledger row, the `failed` row
   with no `needs_human` row, and the `p08-` rows in `leads_backup`.

## Demo readiness

**PARTIAL.**

**The golden path is demonstrable end to end**, and so is the reliability half.
A live form submission produces one Contact, one Opportunity, one backup row and
one `correlationId` trail; a redelivery answers `200 already_processed`; a wrong
secret answers `401`; a formula-shaped name is stored as text; a second inquiry
from the same person is amplified rather than swallowed. Break the downstream
write and the caller gets `202`, the execution sleeps in the database, and the
ladder either converges on exactly one row or exhausts into a `failed` ledger
row plus a `needs_human` handoff.

**Reconciliation is now demonstrable too, and it is the strongest story here**
precisely because it was proven on real damage rather than a fixture: six
opportunities had sat in the CRM for a day with no backup row, and the sweep's
first live run recovered all six while leaving the three healthy ones alone.
Running it again wrote nothing at all.

**What keeps this PARTIAL rather than READY:** TC-02b still does not cover the
deployed GHL workflow, the duplicate-opportunity guard has never been exercised,
all evidence is sequential, and a re-inquiry writes no backup row *and* creates
no opportunity — a gap the sweep structurally cannot see. Everything else weaker
than a clean matrix would suggest is named under "Open risks" rather than buried
— including that P08's own tests found three defects, one of which produced a
`failed` ledger row with nobody told (that row is still in the ledger), and that
P08B's own passing test found a fourth: the sweep's log counts each recovery
three times.

Full reading route: [`docs/INDEX.md`](docs/INDEX.md).
</content>
