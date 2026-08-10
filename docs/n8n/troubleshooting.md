# n8n troubleshooting

Sibling pages: [setup](setup.md) · [operations](operations.md) ·
[testing](testing.md).

---

## 1. Every delivery returns 401

The secret check fails closed on purpose — an unset variable must never
authorize a request:

```js
const secretConfigured = expected.length > 0;
const authorized = secretConfigured && provided === expected;
```

That means **a missing or misnamed n8n variable and a genuine value mismatch
produce the identical 401**. Observed live during the P06 build: the GHL leg
worked, merge tags resolved, the webhook fired, and n8n rejected every
delivery.

Diagnose in this order:

1. **Variable key, character-exact.** `Settings → Variables` must show
   `GHL_WEBHOOK_SHARED_SECRET` — uppercase, underscores, no prefix, no typo.
   A key that differs by one character produces a permanent 401 that looks
   exactly like a wrong password. Check this first; it costs five seconds and
   it is the highest-probability cause.
2. **No quotes, no wrapper.** In GHL's Custom Data the `sharedSecret` row must
   be *static text*. Typing `"value"` with quotes stores the quotes; the
   comparison trims whitespace but does not strip quote characters.
3. **Re-enter the value in both places** rather than trying to compare them by
   eye. Never paste either one into chat, a commit, an Issue, or a screenshot.

The `run_log` row for a rejection carries
`n8n variable resolved: true|false`, which separates cause 1 from cause 3
without exposing the secret or even its length.

A fourth cause, ruled out only by reading a real body: **Custom Data arrives
nested under `customData`, not at the payload root.** Reading the secret from
the root produced a permanent 401 and cost six diagnostic deliveries during
P06 — see [setup](setup.md), "Two corrections the vendor documentation got
wrong".

## 2. The fix looks applied but production still misbehaves

Saving a workflow writes the **draft**; the production webhook keeps serving
the previously published version. Reading the workflow back through the API
returns the draft, so the fix looks live when it is not. Compare
`activeVersionId` against the workflow's current `versionId` — full account in
[operations](operations.md) §1.

## 3. A lead reached `failed` but nobody was told

A `failed` ledger row is not proof the handoff happened. `Sheets: needs_human`
is a separate node and can fail on its own; ledger row `id=7` is exactly that
case. Judge the handoff on the `needs_human` row, never on the ledger alone.
Replay procedure in [operations](operations.md) §4.

## Related

- [setup](setup.md) — the variable, the credential, the declared contract
- [operations](operations.md) — publishing, response contract, known limitations
- [`../evidence/security-tests.md`](../evidence/security-tests.md) — TC-18's observed 401 behaviour
</content>
