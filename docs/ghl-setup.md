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

## Related

- [`integration-options.md`](integration-options.md) §1 — MCP capability
  research this setup implements.
- [`architecture.md`](architecture.md) §6 — identity and idempotency design
  this connection exists to verify.
- [`../PROJECT_STATE.md`](../PROJECT_STATE.md) — current sprint state.
