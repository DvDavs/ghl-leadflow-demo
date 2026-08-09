# GoHighLevel setup — MCP OAuth access

Reproducible checklist for connecting Claude Code to the official HighLevel MCP
server and scoping it to a single disposable trial sub-account. Contains no
secrets, tokens, or account/location identifiers.

## Method chosen: OAuth, not a Private Integration Token

The developer portal documents OAuth as available and recommended for the v2
MCP endpoint, exposing a broader scope set than a PIT. See
[`integration-options.md`](integration-options.md) §1. A PIT was **not**
created for this setup.

## Endpoint

```
https://services.leadconnectorhq.com/mcp/anthropic/v2
```

Configured in the repo's `.mcp.json` as a project-scoped HTTP MCP server named
`leadconnector`. `.mcp.json` holds only `{ "type": "http", "url": "..." }` —
never a token, header, or location id.

## Steps

1. Add the server (project scope, URL only):

   ```
   claude mcp add --transport http leadconnector https://services.leadconnectorhq.com/mcp/anthropic/v2 -s project
   ```

2. Approve the project-scoped MCP server. A freshly added or changed
   `.mcp.json` server is not trusted automatically — run `claude` inside the
   repository directory and accept the trust prompt for `leadconnector`
   before it will connect.

3. Authenticate:

   ```
   claude mcp login leadconnector
   ```

   This opens the HighLevel authorization screen in a browser. **Select only
   the disposable trial sub-account** — do not grant agency-wide access or
   select any other sub-account. Approve the narrowest scope group the
   screen offers for: Contacts, Opportunities (view), Custom Fields (view),
   and Locations (view). Decline Forms edit, Conversations, Messages,
   Payments, and Calendars unless a later phase specifically requires them.

4. Verify:

   ```
   claude mcp list
   ```

   `leadconnector` should show `✔ Connected`.

## Isolation check (run this before anything else)

Call the `list_locations` operation immediately after connecting. It must
return **exactly one** location — the trial sub-account. If it returns more
than one, or an agency-level result, revoke and re-authorize before issuing
any other call:

```
claude mcp logout leadconnector
claude mcp login leadconnector
```

## Capability discovery

Use the meta-toolset rather than assuming coverage — the effective catalog is
grant-dependent:

- `search_operations` — discover operations by keyword/area.
- `describe_operation` — inspect an operation's parameter schema before
  calling it.
- `execute_operation` — the only way to actually call a discovered operation.

Never treat "operation discovered" as "operation works." Confirm each
capability by executing it once, or by schema inspection when a live call
would require building scope-excluded resources (see
[`integration-options.md`](integration-options.md) §5 for the classification
of what was actually confirmed).

## Revocation

To fully remove access:

```
claude mcp logout leadconnector
claude mcp remove leadconnector -s project
```

Revoking in the HighLevel marketplace/app-authorization settings on the
sub-account side also invalidates the grant immediately, independent of the
local CLI state.

## What must never appear in this repository

- Access or refresh tokens.
- The trial location's location id or account id.
- Authorization headers of any kind.
- Real contact, business, or personal data — fixtures are fictional only
  (`@example.com` emails, `+1 202-555-01xx` phones, names containing a
  `P04 Capability Probe`-style marker for anything created during capability
  verification).

## Registry gaps confirmed live (P05)

Checked by exhaustive `search_operations` queries, not assumption — none of
these have a write (or, for the first one, any) operation in the connected
registry:

- **No `update-location` write operation.** The location's `firstName`,
  `lastName`, `email`, `phone`, `address`, `city`, `state`, `postalCode`,
  `country`, and `business.*` fields can be read (`get-location`) but not
  written via MCP. Full Business Profile sanitization is UI-only.
- **No `create-pipeline` operation.** Pipelines (and their stages) can only
  be listed (`get-pipelines`), never created or edited, via MCP.
- **No form-builder write operation.** Forms can only be listed
  (`get-forms`); building one is UI-only.
- **No workflow-builder write operation**, confirming the constraint already
  recorded on Issue #7. Workflows can only be listed (`get-workflow`).

Custom fields, tags, contacts, and opportunities all have working create /
read / delete operations and were built via MCP.

## Gotcha: the form builder can silently fork custom fields (P05)

Building a form field in the GHL UI by typing a new field name — instead of
picking an existing custom field from the dropdown — creates a **new**
custom field object, even when the label looks identical to one that
already exists. P05 hit this directly: the form's "Service Interest" and
"Message" fields were built as new fields (`contact.select_service_interest`,
`contact.message`) instead of being bound to the P0 fields already created
via MCP (`contact.service_interest`, `contact.lead_message`). The live
symptom was a Contact whose `customFields` array held the P0 field values
under the *wrong* field IDs. Always verify post-build with `get-custom-fields`
and compare `fieldKey`s against what was actually created, not just the
field labels shown in the UI.

## Gotcha: opportunity Name templates need real merge tags (P05)

The `Create Opportunity` workflow action's `Name` field must be populated
using GHL's merge-tag picker, not by typing the placeholder text the picker
displays (e.g. `[First Name] [Last Name]`) as literal characters. Doing the
latter creates an Opportunity whose `name` is literally the unresolved
bracket text — confirmed live via `get-opportunity` on the first P05 attempt,
fixed by re-inserting the tokens from the picker.

## Outbound webhook to n8n (P06)

The second GHL workflow — `LeadFlow Demo — Opportunity to n8n` — is built and
published. Its rebuildable checklist lives in
[`n8n-setup.md`](n8n-setup.md) §6, together with the declared Custom Data
contract, because the payload contract and the n8n side that consumes it have
to be read as one thing. Two constraints from that section belong here too:

- **Workflows remain UI-only.** Confirmed again in P06 — `get-workflow` reads,
  nothing writes.
- **Merge values must come from the picker**, never typed. The same defect that
  bit the `Create Opportunity` Name field in P05 would silently produce a
  payload whose `opportunityId` is literal bracket text.

## Related

- [`integration-options.md`](integration-options.md) §1 — MCP capability
  research this setup implements.
- [`architecture.md`](architecture.md) §6 — identity and idempotency design
  this connection exists to verify.
- [`../PROJECT_STATE.md`](../PROJECT_STATE.md) — current sprint state.
