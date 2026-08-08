# Integration options

What GoHighLevel and n8n actually support, established from **official vendor
documentation only**. Community blog posts, tutorials, and third-party MCP
projects are not accepted as evidence and appear here only where they are
explicitly labelled as unverified.

**All sources consulted 2026-08-08.** Vendor documentation changes; re-verify
before relying on any claim below.

Every claim carries a link. Anything that could not be confirmed officially is
in [§5 Not verified](#5-not-verified) rather than stated as fact — **absence of
evidence is reported as absence of evidence, not as absence of the feature.**

---

## 1. GoHighLevel — official MCP server

**An official MCP server exists and is published by HighLevel itself.**

- Developer portal: <https://marketplace.gohighlevel.com/docs/other/mcp/>
- Support article: <https://help.gohighlevel.com/support/solutions/articles/155000005741-how-to-use-the-highlevel-mcp-server>
- Announcement, dated 30 July 2025: <https://www.gohighlevel.com/post/introducing-the-mcp-server>

### Two endpoints, not equivalent

| Endpoint | What the docs say |
|---|---|
| `https://services.leadconnectorhq.com/mcp/anthropic/v2` | Per-client endpoint, live for Claude. Docs call it the recommended route and describe "hundreds of operations across 40 domains". |
| `https://services.leadconnectorhq.com/mcp/` | The original generic endpoint. Docs describe it as a "more limited, focused set" with "narrower scope than the `/mcp/{client}/v2` catalog". |

Source for both: <https://marketplace.gohighlevel.com/docs/other/mcp/>

### ⚠️ Two official sources disagree, and one is stale

The **developer portal** documents OAuth as available and recommended, alongside
Private Integration Tokens (`Authorization: Bearer pit-your-token`). It notes
that "OAuth exposes a broader scope set than a PIT".

The **support-portal article** still says "OAuth support is planned for a future
release. Use Private Integration Tokens for the current setup", lists exactly 36
tools, and requires a `locationId` header.

**Treat the developer portal as authoritative** — it is the newer of the two and
describes the v2 endpoint. Expect the support article to lag. Flagging this
because following the older article would lead to building against a narrower
capability set than actually exists.

### Capability coverage

The v2 endpoint exposes a **meta-toolset** (`search`, `fetch`,
`search_operations`, `describe_operation`, `execute_operation`,
`list_locations`) rather than one tool per endpoint. The docs instruct callers
to "Ask `search_operations` for exact operations available to your grant" — so
**the effective catalog is grant-dependent and only fully discoverable at
runtime with a real token.**

| Capability | Supported | Evidence | Notes |
|---|---|---|---|
| Contacts | **Yes** | [dev portal](https://marketplace.gohighlevel.com/docs/other/mcp/) | Get, list, search, create, update, delete, upsert, duplicate lookup, tags, notes, tasks, appointments |
| Opportunities and pipelines | **Yes** | same | Pipelines, lost reasons, search, create, update, delete, upsert, status changes |
| Calendars and appointments | **Yes** | same | Calendars, groups, appointments, events, free/blocked slots, schedules, services |
| Conversations and messages | **Yes** | same | Send and read messages, message status |
| Location / sub-account targeting | **Yes** | same | Every request targets a single location; `list_locations` tool exists |
| Custom fields | **Partial — unconfirmed** | same | Absent from the v2 coverage list. The older 36-tool list includes a custom-field read. Contact create/update carries custom-field values in the REST API, but a dedicated management operation could not be confirmed |
| **Workflows** | **No — absent from the coverage list** | same | **The decisive gap.** No workflow tools in the v2 list or the 36-tool list |

### The finding that shapes the sprint

> **Workflow authoring cannot be automated.** The official MCP does not cover
> it, and the REST API documents only retrieval
> (<https://marketplace.gohighlevel.com/docs/ghl/workflows/get-workflow>).
> Creating the workflow and its outbound webhook step is **UI-only**.

Budget interview and build time for clicking this in the GHL UI, and write it
down as a reproducible checklist — otherwise the demo cannot be rebuilt on a
fresh location.

### Connecting it

The docs give this command:

```
claude mcp add --transport http leadconnector https://services.leadconnectorhq.com/mcp/anthropic/v2
```

**Not run.** Installing MCPs is out of scope for this phase and requires
credentials that have not been requested.

---

## 2. GoHighLevel — REST API and webhooks

### REST API

- Base URL: `https://services.leadconnectorhq.com`
- Required headers: `Authorization: Bearer <token>` and `Version: 2021-07-28`
- Source: <https://marketplace.gohighlevel.com/docs/Authorization/PrivateIntegrationsToken/>

**Token models**, described generally — no scope strings are enumerated here:

- **Private Integration Token.** Created in the UI under *Settings → Private
  Integrations*; scopes chosen at creation; the token is shown once. Available
  for both agencies and sub-accounts. Static, unlike OAuth tokens which "expire
  daily and need to be refreshed". HighLevel recommends rotating every 90 days.
- **OAuth 2.0 Marketplace app.** Access tokens last one day; refresh tokens are
  "valid for a year unless they are used"
  (<https://marketplace.gohighlevel.com/docs/oauth/Faqs/index.html>).

**Scopes** are granular per-permission strings selected at creation. The docs
advise "selecting only the required scopes for better data security". A real
gotcha: for OAuth apps, "Scopes can only be changed while your app is in a draft
version" (<https://marketplace.gohighlevel.com/docs/webhook/WebhookIntegrationGuide/>).

### Webhooks — two mechanisms, and the difference costs money

**(a) Workflow action "Webhook (Outbound)"** — the free path.
<https://help.gohighlevel.com/support/solutions/articles/155000003299-workflow-action-webhook-outbound->

Sends contact and trigger data to a URL you supply; POST is the documented
default. Payload includes standard and custom fields.

Documented limitations, quoted: "We cannot send images/files using webhook
action", and "If the trigger is not related to a specific object…data for other
objects like appointments or opportunities will **not** be included".

> **No custom headers, no authentication, and no signature verification are
> documented for this action.** This is why the design authenticates ingress
> with an unguessable path plus a shared secret in the payload rather than
> cryptographically. It is a real constraint, not a shortcut.

**(b) Marketplace-app webhook subscriptions** — the signed path.
<https://marketplace.gohighlevel.com/docs/webhook/WebhookIntegrationGuide/>

Requires an OAuth app. Sends `X-GHL-Signature` (Ed25519, current) and
`X-WH-Signature` (RSA-SHA256, legacy). **The legacy header is documented as
deprecated on 1 September 2026.** Signed webhooks therefore mean building a
Marketplace app — real work, out of scope for a two-day demo.

### Rate limits

| Context | Limit | Source |
|---|---|---|
| Production, per app per location | **100 requests / 10 seconds**, and **200,000 / day** | [OAuth FAQ](https://marketplace.gohighlevel.com/docs/oauth/Faqs/index.html) |
| Sandbox | **25 requests / 10 seconds**, and **10,000 / day**, applied at location level and not multiplying across tokens | [Sandbox PIT](https://marketplace.gohighlevel.com/docs/oauth/SandboxPIT) |

Responses carry `X-RateLimit-*` headers, which is what makes the backoff policy
in [`architecture.md`](architecture.md) implementable rather than guessed.

### Sandbox

Available from the Developer Portal under *Testing → Create App Test Account*.
Docs state it is "provisioned immediately", includes "Trial access to Enterprise
features", and stays active up to six months. Private Integration Tokens are
supported. Explicitly isolated from production and rate-limited.
<https://marketplace.gohighlevel.com/docs/oauth/SandboxAccount>

**This conveniently sidesteps the unresolved question of whether API access
requires a specific paid plan tier** (see §5).

### ⚠️ Premium workflow features are billable

<https://help.gohighlevel.com/support/solutions/articles/155000005678-how-to-enable-and-rebill-premium-features-for-workflows>

Premium **trigger**: Inbound Webhook. Premium **actions**: Google Sheets, Slack,
**Custom Outbound Webhook**, Workflow AI Actions. Sub-accounts get **100 free
executions**, then **$0.01 per execution** debited from the agency wallet.

Two consequences that genuinely favour this architecture:

1. **GHL's own Google Sheets action is a paid action.** Routing
   GHL → n8n → Google Sheets via the *free* plain outbound webhook avoids that
   charge entirely. That is a real architectural argument, not a workaround.
2. **The plain outbound Webhook action is free; the Custom Webhook action —
   which does support methods, auth, and headers — is premium**
   (<https://help.gohighlevel.com/support/solutions/articles/48001238167-guide-to-custom-webhook-workflow-action>).
   The lack of header auth in the free action is therefore a *pricing*
   boundary, not a product gap. Worth knowing before designing around it.

---

## 3. n8n — hosting options

### n8n Cloud

- **14-day trial**, Pro features capped at **1000 executions**. "If you don't
  upgrade by the end of your trial, the trial automatically expires and n8n
  deletes your workspace." 90 days to download workflows afterwards.
  <https://docs.n8n.io/deploy/use-n8n-cloud/start-your-free-trial>
- "No credit card required" for Starter/Pro trials; a card is only required for
  the Business trial. Starter €20/mo annually, Pro €50/mo.
  <https://n8n.io/pricing/>
- There is **no permanent free tier**; the free option is self-hosting the
  Community Edition.

### Self-hosted, Docker

Official image `docker.n8n.io/n8nio/n8n`.
<https://docs.n8n.io/deploy/host-n8n/install-options/install-with-docker>

```shell
docker volume create n8n_data

docker run -it --rm \
 --name n8n \
 -p 5678:5678 \
 -e GENERIC_TIMEZONE="<YOUR_TIMEZONE>" \
 -e TZ="<YOUR_TIMEZONE>" \
 -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
 -e N8N_RUNNERS_ENABLED=true \
 -v n8n_data:/home/node/.n8n \
 docker.n8n.io/n8nio/n8n
```

The docs warn: "Self-hosting n8n requires technical knowledge… mistakes can lead
to data loss, security issues, and downtime." The named volume holds "other
important data like encryption keys" — note `--rm` deletes the *container* on
exit, but the volume survives. Compose guidance:
<https://docs.n8n.io/deploy/host-n8n/install-options/use-a-cloud-provider/use-docker-compose>

### Self-hosted, npm or npx

<https://docs.n8n.io/deploy/host-n8n/install-options/install-with-npm>

```bash
npx n8n              # try without installing
npm install n8n -g   # global install
```

> **"n8n requires a Node.js version between 20.19 and 24.x, inclusive."**

The local machine runs Node 22.19, which satisfies this — see
[`environment.md`](environment.md).

### ⚠️ The tunnel story has changed — this invalidates common older guidance

**The `n8n start --tunnel` flag no longer exists.** Verified against the current
`master` branch of <https://github.com/n8n-io/n8n>
(`packages/cli/src/commands/start.ts` defines only `open`/`-o`). The old
documentation URLs now return 404.

Current official docs describe the tunnel as **cloudflared-based and
monorepo-oriented**: "The tunnel uses cloudflared, which runs as a Docker
container. **Make sure Docker is installed on your machine, even when running
n8n via npm.**" The documented commands are `pnpm`-based and assume a monorepo
checkout — **so they do not apply to a plain `npx n8n` or `docker run`
install.**

n8n's own warnings: "Use this for local development and testing. It isn't safe
to use it in production", and "The underlying implementation may change between
n8n versions."

**The install-method-agnostic, officially documented route** is to front n8n
with any tunnel or reverse proxy and set the URL explicitly:
<https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/configuration-examples/configure-webhook-urls-with-reverse-proxy>

- **`N8N_WEBHOOK_URL`** — set manually "so that n8n can display it in the editor
  UI and register the correct webhook URLs with external services".
- **`N8N_WEBHOOK_URL` replaces the deprecated `WEBHOOK_URL`.** Another stale-
  knowledge trap; n8n logs a deprecation warning for the old name.
- **`N8N_PROXY_HOPS=1`** when behind a reverse proxy.

**ngrok is not named anywhere in official n8n documentation.** Pointing ngrok at
`:5678` and setting `N8N_WEBHOOK_URL` is a reasonable inference from the
documented variable, but it is **an inference, not a documented recipe.**

### ⚠️ Test versus Production webhook URLs

<https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/workflow-development>

During development, "Select **Listen for test event** to register the webhook" —
and "The test webhook stays active for **120 seconds**." Production requires
switching to the Production URL on a **saved and published** workflow.

**A live demo wired to the test URL will die mid-interview.** This is the single
cheapest mistake to avoid on the list.

### Google Sheets

Official built-in node exists, with append, append-or-update, get, update,
clear, create, and delete operations.
<https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.googlesheets>

Authentication (<https://docs.n8n.io/integrations/builtin/credentials/google>):

- **OAuth2** — "Recommended because it's more widely available and easier to set up."
- **Service Account** — supported for some nodes only.
- **n8n Cloud offers managed OAuth2**, requiring no Google Cloud Console work.
- **Self-hosted requires custom OAuth2**: a Google Cloud project, the Sheets API
  enabled, a consent screen, and n8n's redirect URI registered.

That last point is the **largest hidden time sink in the self-hosted path** and
the classic source of an unplanned ninety-minute detour.

---

## 4. Recommendations

### GoHighLevel integration layer

Applying [ADR-001](decisions/ADR-001-integration-hierarchy.md) per operation:

| Operation | Layer | Justification |
|---|---|---|
| Contacts, opportunities, pipelines, calendars, locations | **Official MCP** (`/mcp/anthropic/v2`) | Vendor-owned, OAuth-capable, and the coverage list explicitly names every object the demo needs |
| Anything the runtime grant turns out not to cover | **Official REST API** | Discoverable via `search_operations`; same vendor, documented auth |
| **Workflow authoring and the outbound webhook step** | **UI — unavoidable** | Absent from MCP coverage; REST documents retrieval only |
| Enabling premium features | **UI — agency settings** | No documented API |
| Browser automation | **Not justified** | The only UI-bound task is one-time workflow authoring, which a human does faster and more reliably than a script |

### n8n hosting — conditional, in priority order

**This must not be finalized before asking whether an instance already exists.**

**1. Reuse an existing instance — first choice, if David already runs one.**
Every documented failure mode below is eliminated by an instance that already
has a stable HTTPS URL and working Google credentials. It also removes the
1000-execution cap and the workspace-deletion clause. **Ask before building
anything.**

**2. If none exists: local Docker plus a tunnel — the default candidate.**
Docker is n8n's own recommended self-hosting route, and it beats npx on two
verified counts: no Node version constraint on the host, and the official tunnel
requires Docker anyway "even when running n8n via npm". Two caveats are
load-bearing: the documented tunnel commands assume a monorepo checkout and do
not apply here, so the real route is an external tunnel plus `N8N_WEBHOOK_URL`;
and n8n itself says the tunnel "isn't safe to use in production". A live
interview is not production, so that is acceptable — but start the tunnel
**once**, paste the URL into the GHL workflow, and restart nothing before the
demo.

**3. n8n Cloud only if access and configuration are demonstrably faster — and
the evidence says it often will be.** Two documented advantages materially
shrink demo risk: a native stable HTTPS webhook URL with **no tunnel at all**,
and **managed OAuth2 for Google**, versus self-hosted's Google Cloud Console
setup. The 14-day trial covers a two-day window comfortably. Accept the
constraints: 1000 executions, and the workspace is deleted at trial end.
**If the Google Sheets leg is in scope, Cloud's managed OAuth2 is a strong,
evidence-backed reason to prefer this over option 2.**

**4. Do not deploy a VPS.** It adds DNS, TLS, firewall, and reverse-proxy
configuration — every one a new failure mode — to solve a problem that option 3
solves in minutes with no infrastructure. n8n's own docs warn that self-hosting
mistakes "can lead to data loss, security issues, and downtime".

### What breaks a live demo, ranked

1. **Tunnel URL rotation.** Free tunnels issue a new hostname on each start, and the GHL workflow's webhook URL does not follow. Any restart between rehearsal and demo silently breaks the chain.
2. **Laptop sleep or network change.** Drops the tunnel; GHL fires into a dead URL.
3. **Test-versus-Production URL confusion.** The 120-second window expires.
4. **Google OAuth consent screen.** Self-hosted only; the classic unplanned detour.
5. **Container restart.** Recoverable, but it resets the tunnel, compounding #1.

---

## 5. Not verified

Could not be confirmed from an official source as of 2026-08-08. Listed so that
nothing here is mistaken for established fact.

1. **Dedicated custom-field management operations on the MCP v2 endpoint.** Absent from the coverage list; discoverable only at runtime with a real token.
2. **MCP workflow operations.** Absent from documentation — this is absence from docs, not a documented denial.
3. **GHL API v3 status.** Pages titled "v3" and a version switcher exist, but no official statement declares v3 GA or superseding v2. The [changelog](https://marketplace.gohighlevel.com/docs/Changelog/) contains no v3 GA announcement. Use `Version: 2021-07-28`, which the current auth docs still show.
4. **GHL V1 API end-of-support date.** Appeared only in a search-engine summary; the primary page could not be located.
5. **Whether GHL API access requires a specific paid plan tier.** Unconfirmed. Sidestepped by the sandbox, which officially includes "Trial access to Enterprise features" and supports Private Integration Tokens.
6. **MCP-specific rate limits.** None published. Whether MCP calls consume the REST budget is undocumented.
7. **n8n Cloud time to a first working public webhook URL.** No official figure.
8. **ngrok plus n8n as an officially supported combination.** n8n names no third-party tunnel service. The pairing is an inference from `N8N_WEBHOOK_URL`.
9. **Whether older released n8n versions still accept `n8n start --tunnel`.** Verified absent from `master` and current docs; tagged releases were not audited.
10. **GHL webhook retry and delivery-guarantee policy.** Not documented on any consulted page. The at-least-once assumption in [ADR-002](decisions/ADR-002-idempotency-strategy.md) rests on this and is flagged there as an assumption.

### Unverified community claims — not evidence

Third-party "GoHighLevel MCP" projects exist on GitHub, some advertising
"250–500+ tools", alongside 2026-dated blog posts. **None is an official
HighLevel project**, and several of those posts are third-party marketing
content rather than vendor documentation. They are recorded here only so that
nobody mistakes them for the official server documented in §1. Per
[ADR-001](decisions/ADR-001-integration-hierarchy.md), a third-party MCP is
classified at the layer its transport actually sits on — usually the REST API —
and is never counted as an official MCP.

---

## Related

- [ADR-001](decisions/ADR-001-integration-hierarchy.md) — the hierarchy this research feeds
- [`architecture.md`](architecture.md) — the design these constraints shape
- [`environment.md`](environment.md) — what the local machine can run
