# Environment Inventory

Public, sanitized inventory of the workstation used to build this demo. It
records what capability exists and how it was verified, so that later claims in
this repository about what the environment can do are checkable rather than
assumed.

- **Audit date:** 2026-08-08
- **Scope:** environment inventory only. No demo feature, payload, test, or
  external resource was created.
- **Method:** parallel read-only inspection, consolidated, re-verified, and then
  adversarially reviewed. Version strings come from executing each tool.

> **Sanitization.** No secret value was read, copied, or recorded at any point.
> No `.env` file, key file, credential file, or cloud configuration file was
> opened. Tokens, key names, account identifiers, location IDs, webhook URLs,
> commit identity, host paths, and host-level version fingerprints are
> deliberately excluded. Dependency-relevant tool versions are kept, because
> they are what makes the rest of this repository reproducible.
> **Local security findings are maintained outside version control.**

---

## System

- **OS:** Windows 11, x64
- **Shell:** Windows PowerShell 5.1. Git Bash is also available.
- **Node version management:** a version manager is in use, with **22.19.0**
  active. This matters because n8n requires Node ≥20.19 and <25 — the active
  version satisfies it.

---

## Development toolchain

| Tool | Installed | Version | Verified | Classification |
|---|---|---|---|---|
| Git | yes | 2.45.1 | yes — `git status` succeeds in the repo | required now |
| gh (GitHub CLI) | yes | 2.89.0 | yes — authenticated API call returned HTTP 200 | required now |
| Claude Code | yes | 2.1.226 | yes — version and MCP listing both respond | required now |
| Node.js | yes | 22.19.0 | yes — executed a trivial script | required later |
| npm | yes | 10.9.3 | yes — `npm ping` round-tripped to the public registry | required later |
| pnpm | yes | 11.9.0 | yes — resolves its content store | optional |
| Docker | yes, engine **stopped** | 28.4.0 | partial — CLI responds, engine not running | required later |
| Docker Compose | yes | v2.39.2 | partial — plugin responds without the daemon | required later |
| Playwright | **no** | n/a | n/a — absent from PATH, npm globals, and the project | **required later** |

**Classification key:** *required now* = needed to complete the bootstrap;
*required later* = expected during the sprint but not yet needed; *optional* =
no current justification to install.

Notes worth carrying forward:

- **Docker's engine is stopped, not broken.** It is installed and set to manual
  start. This matters only if n8n ends up self-hosted.
- **Playwright is not installed**, and is classified *required later* — meaning
  expected during the sprint, but not needed to reach the current milestone. It
  is scheduled by the "Add E2E tests and evidence" work item, which covers
  automating the lead-capture path and producing repeatable evidence.
  To be precise about the boundary: [`architecture.md`](architecture.md) rules
  out automated tests *against live GHL* in this sprint, so Playwright's scope
  here is the capture path and evidence collection, not CRM assertions. Manual
  evidence — record identifiers, correlation ids, exports — remains acceptable
  for scenarios it does not cover.

---

## GitHub

- **Authenticated:** yes, to github.com, verified by a live API call.
- **Git transport:** SSH, verified working. No key was generated during the
  audit and no key material was read.
- **Local repository at audit time:** valid work tree, zero commits, zero
  tracked files, no remote configured.
- **Remote repository at audit time:** already existed, public and empty. It was
  not created by the audit and was inspected read-only.

Because the remote is **public**, everything committed here is sanitized by
default. That constraint drove the `.gitignore` and the split between this
document and its untracked local counterpart.

---

## Services

| Service | Detected | Configured | Tested | Status |
|---|---|---|---|---|
| GoHighLevel access | no | no | no | not detected |
| n8n | no | no | no | not detected |
| Google (Sheets/API) | no | no | no | not detected |
| GitHub | yes | yes | yes | connected |
| ngrok (webhook tunnel) | yes | unknown | no | installed, not running |
| Docker engine | yes | n/a | no | installed, stopped |

**These three words are not synonyms**, and the distinction is load-bearing:

- **not detected** — not found in the locations inspected.
- **not configured** — present, but no credentials or settings exist for it.
- **not tested** — present and possibly configured, but no command exercised it.

Nothing in this table was started, installed, or authenticated. No credentials
were requested at any point.

**Coverage limit.** Discovery covered PATH, npm globals, standard configuration
directories, listening TCP ports, and running processes. It did **not** cover
Docker containers or images, because the engine is stopped — a stopped n8n
container could exist and remain invisible. A `not detected` row means "not
found where we looked", never "does not exist on this machine".

---

## MCP registry

| Name | Installed | Configured | Connected | Status |
|---|---|---|---|---|
| GoHighLevel MCP | no | no | no | **not detected** |
| Excalidraw MCP | no | no | no | **not detected** |
| Playwright MCP | no | no | no | **not detected** |
| Documentation and memory MCPs | yes | yes | **yes** | connected — not part of the CRM flow |

**Evidence standard.** Only a live health check that reported a successful
connection was accepted as proof of connection. Appearing in a configuration
file counts as *configured*, never as *connected*.

**Coverage limit.** MCP discovery was timeboxed to known configuration
locations. A project-scoped configuration nested elsewhere would have been
missed. "Not detected" is scoped to what was inspected.

Two consequences for this sprint: **no GoHighLevel MCP is configured here**, so
the integration layer cannot be assumed (see
[`integration-options.md`](integration-options.md)); and **Excalidraw MCP is
absent**, which is why the diagrams in this repository are Mermaid.

---

## Changes made during the audit

- **Tools installed:** none. Every *required now* capability was already present.
- **Files created:** this document and its parent directory.
- **Configuration changed:** none.
- **Remote resources created:** none.
- **Services started:** none.

---

## Blockers

**No hard blockers.** No capability required for the immediate sprint is
missing.

Two items are pending decisions rather than blockers:

1. **n8n hosting model** — self-hosted via Docker, local npm, or n8n Cloud. This
   determines whether the Docker engine and a webhook tunnel become *required
   now*. See [`integration-options.md`](integration-options.md).
2. **GoHighLevel integration layer** — MCP, REST API, or webhooks. None is
   configured, and credentials were intentionally not requested.

**Human action required for authentication:** none. GitHub CLI and SSH are both
already authenticated and functionally verified.
