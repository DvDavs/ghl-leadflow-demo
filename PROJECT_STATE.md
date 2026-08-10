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

**Milestone 8 — the interview demo (P09A, in progress). The golden path was
rehearsed twice, unassisted, and the script and one-pager exist. The offline
safety net is half built.**

Two full golden paths ran on fresh non-colliding fixtures with no human filling
a form and no human correcting anything: **one Contact, one Opportunity at
`New Lead`, `inquiry_count = 1`, one n8n execution answering `200 processed`, a
ledger row `completed`, and exactly one `leads_backup` row — read back from the
sheet, not deduced — in about 17 seconds each.** The record, the minute-by-minute
script, the per-system fallbacks and the 10-minute pre-interview checklist are in
[`docs/demo/runbook.md`](docs/demo/runbook.md); the leave-behind summary is
[`docs/demo/one-page.md`](docs/demo/one-page.md).

**All five screenshots are captured and sanitized:** the CRM pipeline board,
the n8n execution answering `200 processed` with its correlation row, the
`leads_backup` tab with one row per event, the `needs_human` terminal handoff
with its full reason, and the reconciliation sweep showing its 10-minute cadence
and its 1-recovered / 9-already-known split. Record identifiers are redacted to
eight characters **in the pixels**, holding the line that no full 20-character
record id has ever been committed to this repository in any form.

**Only the video is outstanding, and no login will fix it.** Playwright records
video as a browser-*context creation* option; the MCP server owns context
creation and exposes no recording tool, so a session already in flight cannot
start recording and a fresh recorded context would start logged out of
everything. It needs a recording-enabled MCP configuration or a human with a
screen recorder. Nothing was faked to fill the gap. See
[`assets/demo/`](assets/demo/).

**Milestone 7 — failure, retry and human handoff (P08, closed out by P08B and
P08C). Complete: the retry half and reconciliation are both built, published,
active and evidenced, and the two GHL-side regression gates P08 could not reach
are now closed.**

**P08C closed both of them with browser automation.** The `inquiry_count` null
on pre-P07 contacts is fixed in GHL **v13** — an `If/Else` sets `2` on an empty
field instead of incrementing a null — and proven on a real pre-P07 fixture.
**TC-02b was re-run against v13** and passes. It did **not** get the sub-second
double submission it was aimed at: Cloudflare Turnstile serialized the two
posts 4.3 s apart, so it proves duplicate-submission safety at that separation
and nothing about concurrency. It did answer *why* the duplicate-opportunity
guard stays unexercised — at 4.3 s the second run finds the first's
opportunity and never reaches `Create Opportunity`.

**And the branch v13 added is now evidenced on both sides. TC-03 was re-run
against v13** on a brand-new fixture whose `inquiry_count` was already `1`, so
the `If/Else` was forced down the arm nothing had ever taken. It came out at
`2` — only `+1` on an existing value explains that — and the opportunity still
came back from `Follow-up` to `Contacting`, which is the only way to observe
that the **`Go To`** reaches the second `Find Opportunity`. The last construct
in either GHL workflow resting on nothing but a build report is now observed.

A downstream failure no longer loses the lead and no longer lies to the sender:
the write is answered `202 retry_scheduled` and retried on a bounded ladder held
by a database-persisted wait; a transient failure that clears converges on
exactly one backup row; one that does not ends in a ledger `failed`, a
`needs_human` row, and a `run_log` outcome distinct from a validation rejection.
Validation also stopped rejecting phone-only leads.

**And a webhook that never arrives is no longer unrecoverable.** The sweep runs
every 10 minutes against a read-only GHL credential; on its first live run it
recovered the six opportunities that had sat in the CRM with no backup row, and
its second run wrote nothing. That run also found a defect in the sweep's own
log: a retried write that was landing its row and *then* failing. It was
diagnosed **as a post-write failure — the underlying error is still unknown** —
and fixed by making the write converge instead of by disabling the retry.
**Every write in the sweep is now idempotent**, and TC-17 was re-run against the
fixed artifact.

## What is built and live

| Leg | State |
|---|---|
| **GHL (P05, P07, P08C)** | Form → Contact → Opportunity → Pipeline runs live. 7 P0 custom fields, 5 P0 tags, `LeadFlow Demo Pipeline` (7 stages), the Service Inquiry form, and `Form to Opportunity` **v13** — the re-inquiry branch plus the `inquiry_count` null-safety `If/Else` — all published. Pipeline, form and workflow are UI-only; no MCP write operation exists for any of the three, so `version` is the only machine-checkable proof an edit shipped |
| **n8n ingress (P06)** | Webhook → allowlist normalization → shared-secret check → ledger claim → `leads_backup` (Append or Update on `eventId`) → ledger `completed`, with deterministic 401 / 422 / 200 / 200-duplicate / 202 responses and append-only `run_log` boundaries. Published and active |
| **n8n reliability (P08)** | Bounded retry (3 attempts, 70s base, ×2, +0–20% jitter, 300s cap) on a database-persisted `Wait`; terminal `needs_human` handoff; operator-only append-only fault switch, left `off`; node-level retry on every write between the claim and a terminal state |
| **Reconciliation (P08B)** | 12-node sweep **published, active, on a 10-minute schedule**, active version `060c3ca1`. Reads `GET /opportunities/search` with a Header Auth credential holding a sub-account PIT scoped to `opportunities.readonly`; `location_id` is **accepted** by GHL, though not proven to be *read* — the sub-account token already implies the location. All three writes are idempotent: `leads_backup` Append-or-Update on `eventId`, ledger upsert on `eventId`, `run_log` Append-or-Update on `correlationId + eventId + step`. TC-17 passes on this version |
| **Test harness (P08)** | Two manual-trigger-only n8n workflows: a sender that injects the secret at send time, and an evidence reader over the three sheet tabs, the ledger and the fault switch. Neither has a public trigger |

Artifacts under [`n8n/workflows/`](n8n/workflows/) and
[`scripts/replay-webhook.ps1`](scripts/replay-webhook.ps1).

## Test status

**Eleven of twenty scenarios pass, and all eleven cover the deployed
artifacts:** TC-01, TC-02, **TC-02b**, **TC-03**, TC-09, TC-10, TC-11, TC-12,
TC-17, TC-18, TC-19. **TC-02b and TC-03 were both re-run against GHL v13**;
neither covers a workflow that no longer exists, and the demoted column is
empty for the first time. **TC-01 also got stronger**: TC-02b's first
submission re-observed its GHL side at v13 *and* its n8n side on the active
`4ab773e2` (execution 72 — backup row, ledger `completed`,
`outcome=processed`), making it the only row covering both legs at their
deployed versions. The remaining nine are `BLOCKED` or deliberately deferred.
Per-row status, version coverage and evidence links:
[`TEST_CASES.md`](TEST_CASES.md).

## Issues and project board

The GitHub Project board (*GHL Leadflow Demo Sprint*) is the source of truth.

**#18 — *Fix reconciliation run_log triplication*** was opened for the defect
TC-17 found, worked, and closed the same day. **#10 was not reopened**: it had
already been closed on evidence that stands, and the log defect was a distinct,
separately tracked fault.

**#11 — *Add E2E tests and evidence*** is **Done**, closed after TC-03's v13
re-run. It is closed on what it can honestly claim: every scenario that has a
deployed artifact to run against now passes against that artifact, and no
passing row covers a workflow that no longer exists. The nine scenarios still
`BLOCKED` or deferred are gated on prerequisites that do not exist (`P-CAL`) or
on a service-routing design deliberately deferred — not on missing test work.
The one thing #11 wanted and did **not** get is named rather than buried: the
sub-second double submission is not reachable through the browser, and it is
tracked as a standing risk, not as an open task.

Re-read the board rather than trusting this section; the repository has twice
been bitten by treating a change that *should* have landed as one that did.

## Blocked

- **A sub-second double submission is not reachable by browser automation.**
  Cloudflare Turnstile sits in front of the public form and each page solves
  its own challenge, which pushed two simultaneously-dispatched submissions
  4.3 s apart. Getting inside the ~1.5 s window the guard needs would take a
  different injection point than the browser, and none is documented.
- **Docker engine is stopped**, so container-level inventory is undetermined.
  Only relevant if the Docker + ngrok fallback is ever needed.

## Open risks

**Evidence and coverage**

| Risk | Detail |
|---|---|
| **The duplicate-opportunity guard has still never been exercised**, and TC-02b's re-run explains rather than closes it. At a 4.3 s separation the second run finds the first's opportunity and takes `Found`, so `Create Opportunity` is reached once, not twice. The window in which the guard could fire is **under 1.5 s**. The event-scoped mitigation ADR-002 wanted still does not exist — `search-opportunity` cannot filter by `external_lead_id` | [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) "Consequences to watch" · [evidence](docs/evidence/ghl-tests.md#tc-02b--duplicate-form-submission-same-person-submits-twice) |
| **All evidence about the deployed system is still effectively sequential.** TC-02b is the closest attempt and it missed by 4.3 s, measured twice — 4.376 s client-side, 4.326 s from GHL's own submission stamps. The only other concurrency observation anywhere is a throwaway diagnostic: three simultaneous Google Sheets appends to one tab all reported success and only **one** row survived. Seen on the diagnostic's own writes, never on a production path | [evidence](docs/evidence/reconciliation-tests.md#open-questions-this-run-leaves) |
| ~~The `Increment` + `Go To` arm of the v13 `If/Else` is unobserved.~~ **Closed by TC-03's v13 re-run** — a fixture already holding `inquiry_count = 1` came out at `2`, and its opportunity still returned from `Follow-up` to `Contacting`, so the `Go To` demonstrably reached the second `Find Opportunity`. No construct in either GHL workflow now rests on the build report alone | [evidence](docs/evidence/ghl-tests.md#tc-03--genuine-re-inquiry-same-person-different-intent) |
| **TC-12's hardened exhaustion branch is unexercised**, and TC-09, TC-18 and TC-19 cover active version `c1225347`, one publish before the deployed `4ab773e2` | [`TEST_CASES.md`](TEST_CASES.md) |
| **`Log Reconciled`'s post-write failure is fixed but not explained.** Two of three attempts committed their `run_log` row and then failed; the write is now Append-or-Update on `correlationId + eventId + step`, so it converges. **The error itself is still unknown** — n8n discards a retried node's intermediate errors, and five isolated single-attempt appends all succeeded. It recurred during the passing re-run (13.5 s for one recovery) and still produced one row | [evidence](docs/evidence/reconciliation-tests.md#diagnosis--three-attempts-three-commits-one-reported-success) · [operations](docs/n8n/operations.md) §5 |
| **TC-17 has no unconsumed test data left**, for the second time. `Noa Feldman` was the re-run's fixture and execution 59 consumed it. Re-running needs another fictional opportunity created while the n8n ingress workflow is deactivated — the GHL webhook fires on *Opportunity Created*, so the API route does not avoid it | [evidence](docs/evidence/reconciliation-tests.md#ready-made-test-data--consumed-twice-over) |
| **A GHL contact and opportunity now exist that no form created.** `Noa Feldman` was made through the API as the TC-17 re-run fixture, so its `source` is empty where a form lead carries `GHL Demo Form`. Filter on the contact tag `p08b2-fixture` before a demo | [evidence](docs/evidence/reconciliation-tests.md#tc-17-re-run--the-fix-under-the-same-failure) |
| **`location_id` is accepted by GHL but not proven to be read.** The sub-account token already implies the location, so the parameter may be ignored; `meta.nextPageUrl` echoing it proves an echo, not a parse. No control run was made. Settled for this sweep, open as a general claim — do not quote it as "GHL's opportunity search takes `location_id`" | [evidence](docs/evidence/reconciliation-tests.md) |

**Silent-loss paths still open**

| Risk | Detail |
|---|---|
| **A retry that dies mid-wait is not re-driven** — the deliberate trade for keeping one copy of the backup-write node. **Live instance:** ledger row `id=5`, `ghl:opportunity-created:p08-tc10-transient`, synthetic and therefore unrecoverable by any sweep | [operations](docs/n8n/operations.md) §6 |
| **A `failed` ledger row is not proof a human was told** — ledger row `id=7` is exactly that case. Judge the handoff on the `needs_human` row, never the ledger alone | [operations](docs/n8n/operations.md) §4 |
| **A re-inquiry leaves no `leads_backup` row and reconciliation cannot find it**, so `architecture.md` §5's "Sheets is event-grained" is not yet true for re-inquiries. **Not a TC-17 instance.** Deferred deliberately; both available shortcuts are actively harmful | [ADR-002](docs/decisions/ADR-002-idempotency-strategy.md) item 2 |
| **The re-inquiry branch is pipeline-scoped; the guard it compensates for is person-scoped**, so a contact whose open opportunity sits in another pipeline still falls through to the silent swallow, now with `inquiry_count = 1` written over it. Unreachable in a single-pipeline demo; the fix is one filter removal | [ghl-setup](docs/ghl-setup.md) "Two scope limits" |
| ~~`Math Operation` will hit a null for every contact created before P07.~~ **Closed in P08C (v13)** — an `If/Else` sets `2` on an empty `inquiry_count` instead of incrementing a null, observed live on `Marisol Vega` | [ghl-setup](docs/ghl-setup.md) build rule 3 |

**Traps that have already bitten once**

| Risk | Detail |
|---|---|
| **Saving a workflow is not publishing it** — in n8n *and* in GHL. A security fix looked applied for over an hour while production served the old version. Compare `activeVersionId` against `versionId`; for a GHL workflow the version number is the only machine-checkable proof an edit shipped | [operations](docs/n8n/operations.md) §1 |
| **Publishing with no `versionId` ships whatever the draft has drifted into — including somebody else's open editor tab.** Reactivating the ingress workflow after a 3-minute deactivation published a draft carrying **18 autosaved browser-session versions**, replacing the evidenced `4ab773e2`. No execution ran on it and the active version was restored explicitly, but the rule is now: record `activeVersionId` before deactivating and republish that exact id | [operations](docs/n8n/operations.md) §1 |
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
| **Twelve fictional diagnostic contacts pollute the demo location.** All twelve have a `leads_backup` row: **five fired their webhook normally** (Valeria Cruz, the `=1+1 Testcase` fixture, Priya Chandran, `Ines Marchetti` on execution 72, and `Rafael Okonkwo` on execution 78) and **seven were recovered by the sweep** on 2026-08-10 — six on its first run, then `Noa Feldman` on the re-run — so those seven carry `lastAction=reconciled` | [evidence](docs/evidence/reconciliation-tests.md) |
| **P08C consumed two more fixtures and added one contact.** `Marisol Vega` is no longer null-safety test data — her `inquiry_count` is `2`. `Ines Marchetti` is new (TC-02b), has an open opportunity and `inquiry_count = 2`, and is the first contact in this location created by two form submissions. Six pre-P07 contacts still qualify as null-safety fixtures: `David Demo`, `Sofia Bennett`, `Camila Torres`, `Camila Torres 02`, `Tobias Lind`, `Valeria Cruz` | [evidence](docs/evidence/ghl-tests.md#p08c--inquiry_count-null-safety-on-a-pre-p07-contact) |
| **TC-03's re-run added one more contact.** `Rafael Okonkwo` (`+1 202-555-0173`) has an open opportunity `Rafael Okonkwo - Real Estate` sitting in `Contacting`, `inquiry_count = 2`, the `repeat-inquiry` tag, one note, and one successful ingress execution (78) from submission 1 only — the sheet row is deduced from that execution, not read back. Fictional, form-created, `source = GHL Demo Form` — noise in a demo board, nothing more | [evidence](docs/evidence/ghl-tests.md#tc-03--genuine-re-inquiry-same-person-different-intent) |
| **P09A's two rehearsals added two more contacts.** `Anouk Delacroix` (Real Estate) and `Emeka Nwosu` (Business Loan), both `+1 415-555-01xx` — deliberately outside the `202-555-01xx` block every earlier fixture uses, so neither can collide. Each has one open opportunity at `New Lead`, `inquiry_count = 1`, one ingress execution and one `leads_backup` row. Fictional, form-created, `source = GHL Demo Form`. They are the two cards a demo board will show first | [runbook](docs/demo/runbook.md) |
| **P08 fixtures sit in the durable backup.** `p08-regress-alpha`, `p08-tc10b-transient` and `p08-tc19-formula` have `leads_backup` rows; `p08-tc12-persistent` and `p08-tc12b-persistent` are terminal `failed` with none. All fictional, all carrying `source = P08 Internal Test Harness` — the column to filter on before a demo | [operations](docs/n8n/operations.md) §6 |
| **The trial location's owner First/Last Name is still real** — not committed to git, not part of the interview-facing fixture, so not blocking, but still open after three UI correction attempts | [history](docs/history/ghl-leg-p05-p07.md) |

## Environment

| Area | State |
|---|---|
| Toolchain | Git, GitHub CLI, Node, npm, Claude Code present and verified |
| Docker | Installed, engine stopped |
| Playwright | **Connected, and it delivered in P08C** — both live form submissions behind TC-02b and the null-safety run were browser-driven, including a two-context `Promise.all` double submit. **Two limits found the hard way:** a GHL *admin* deep link answers `404` and renders blank until the SPA has bootstrapped once, so the admin UI stays a human job on a slow link; and the *public* form sits behind Cloudflare Turnstile, which serializes concurrent submissions |
| n8n | **n8n Cloud live** — workflow published and active on its production webhook URL. Variables and Data Tables both confirmed available on the plan. MCP server connected, tools available |
| GoHighLevel | **Connected** — official MCP over OAuth, one trial location. No PIT. Operations require an explicit `locationId` even so |
| Google | **Sheets connected to n8n** via a credential-store OAuth2 credential, bound only to the native Sheets node. Sheet is private |
| Tunnel | ngrok installed, not running, auth state unconfirmed — only needed if n8n Cloud fallback triggers |

Detail in [`docs/environment.md`](docs/environment.md).

## Decisions

All 26, including the three ADRs, in
[`docs/decisions/decision-log.md`](docs/decisions/decision-log.md).

## Next 3 actions

1. **Record the video and close #12.** Everything else the issue asks for is
   done: the script, the one-pager, two unassisted rehearsals and all five
   sanitized screenshots — see [`docs/demo/runbook.md`](docs/demo/runbook.md)
   and [`assets/demo/`](assets/demo/). The video needs a recording-enabled
   Playwright context or a human with a screen recorder; it is the only thing
   holding the issue open.
2. **Decide whether the duplicate-opportunity guard is worth chasing further.**
   TC-02b established the window is under 1.5 s and that the browser cannot
   get inside it. The honest options are to leave it `[DOCUMENTED]` and say so
   in the interview, or to find a submission path that bypasses Turnstile —
   which is a different test from the one the matrix describes.
3. **Clean up the fixture noise**: the orphaned `retry_scheduled` ledger row,
   the `failed` row with no `needs_human` row, and the `p08-` rows in
   `leads_backup`. Still pending an explicit decision; nothing has been deleted.
   The unexplained Sheets post-write failure sits behind this — the sweep
   converges under it, so it costs correctness nothing, but it is the one thing
   in the reliability story with no named cause.

## Demo readiness

**PARTIAL — and now rehearsed rather than assumed.**

**P09A ran the golden path twice, unassisted, and it held both times** — see
the milestone section above and [`docs/demo/runbook.md`](docs/demo/runbook.md).
The script, the fallbacks and the one-pager exist. **The offline safety net does
not yet**: one of five screenshots is captured, and the recorded video is not,
because the automation browser is signed in to GoHighLevel only.

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

**That run also failed at something, and the repair is the better story.** Its
log wrote each recovery three times. The trio timestamps showed three separate
attempts seven seconds apart, and the last one matching the run n8n called
successful — so the write was landing and *then* failing. The fix was to make
the log write idempotent rather than to switch the retry off, and it was proven
under the failure itself: the re-run hit the same 13.5-second retry and still
produced exactly one row.

**And a second inquiry from a contact the CRM has held since before the feature
existed no longer walks into an increment on a null.** That gap was carried in
the open for a sprint, named in `ghl-setup.md` as *known and unclosed*, and
closed in P08C by branching on the empty field rather than by assuming what
GHL does with it.

**What keeps this PARTIAL rather than READY:** the duplicate-opportunity guard
has still never been exercised — TC-02b measured the window at under 1.5 s and
showed the browser cannot reach inside it — all evidence about the deployed
system is still
effectively sequential, and a re-inquiry writes no backup row *and* creates no
opportunity, a gap the sweep structurally cannot see. Everything else weaker
than a clean matrix would suggest is named under "Open risks" rather than
buried — including that P08's own tests found three defects, one of which
produced a `failed` ledger row with nobody told (that row is still in the
ledger), and that the error behind the reconciliation log defect is
fixed-around rather than understood.

Full reading route: [`docs/INDEX.md`](docs/INDEX.md).
</content>
