# n8n testing — how the scenarios are executed

Procedures only. What each scenario asserts, and what was actually observed,
lives in [`../../TEST_CASES.md`](../../TEST_CASES.md) and under
[`../evidence/`](../evidence/).

Sibling pages: [setup](setup.md) · [operations](operations.md) ·
[troubleshooting](troubleshooting.md).

---

## 1. Test procedures

| Test | Procedure |
|---|---|
| TC-01 | Submit a **new, fictional** lead through the live form. |
| TC-02 | Redeliver the exact captured payload: `.\scripts\replay-webhook.ps1 -PayloadPath payloads\captured.local.json`. **Do not resubmit the form** — that re-tests TC-02b, and no webhook would fire at all. **Corrected P07:** the reason is now the `Find Opportunity` split in `Form to Opportunity`, which routes a contact with an open opportunity down the re-inquiry branch and never reaches `Create Opportunity`. It is not the duplicate-opportunity guard — that guard has never been exercised. |
| TC-18 | Same payload, `-Mode NoSecret` and again `-Mode WrongSecret`. |
| TC-09 | Harness fixture carrying `opportunityId` and `contactId` but neither `email` nor `phone`. Expect `422 {"status":"invalid_payload","missing":"email_or_phone"}`. |
| TC-10 / TC-11 | Append `mode=always, eventScope=<fixture prefix>` to `leadflow_test_controls`, send the fixture, observe `202`, then append `mode=off` **before** `nextAttemptAt` falls due. |
| TC-12 | Same, but leave it armed past the budget — roughly 4 minutes. |

Evidence required before any of these is marked `PASS` is enumerated in
[`../../TEST_CASES.md`](../../TEST_CASES.md). A status code alone proves nothing
about downstream state.

**Publish before you test.** A test proves the version it ran against, and n8n
serves the published version rather than the draft — see
[operations](operations.md) §1.

## 2. The internal test harness (P08)

TC-09 through TC-12 need an *authorized* delivery, and the shared secret is
deliberately not available outside n8n. Two internal, manual-trigger-only
workflows solve that without weakening anything:

| Workflow | What it does |
|---|---|
| `LeadFlow Demo — P08 Test Sender (internal)` | A `Fixture` Code node builds the body **without** the secret; the HTTP node injects `$vars.GHL_WEBHOOK_SHARED_SECRET` in its own expression at send time and POSTs to the production webhook. Export: [`p08-test-sender.sanitized.json`](../../n8n/workflows/p08-test-sender.sanitized.json). |
| `LeadFlow Demo — P08 Evidence Reader (internal)` | Reads `leads_backup`, `run_log`, `needs_human`, the ledger and the fault switch, so downstream state can be observed without a browser session. Five read nodes off a manual trigger; not exported, because rebuilding it is quicker than importing it. |

The secret never enters an item and is therefore never persisted in execution
data — the same discipline that removed the secret-length diagnostic in P06.
Neither workflow has a webhook or form trigger, so neither adds a public
surface: they are reachable only by someone who already has n8n access, and
therefore already has the variable.

Fixtures use synthetic `opportunityId`s prefixed `p08-`, which is what lets
`eventScope` arm the fault for one test without touching any other delivery.
They also mean these events have **no matching GHL Opportunity** — see
[operations](operations.md) §6.

## Related

- [`../../TEST_CASES.md`](../../TEST_CASES.md) — the status matrix
- [`../evidence/n8n-reliability-tests.md`](../evidence/n8n-reliability-tests.md) — what TC-09 through TC-12 actually observed
- [`../evidence/security-tests.md`](../evidence/security-tests.md) — what TC-18 and TC-19 actually observed
- [setup](setup.md) §4b — the fault switch these procedures flip
</content>
