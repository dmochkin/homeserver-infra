# homeserver-infra

Configuration for the home server that runs every app: server setup with Ansible, the shared Helm chart for app deploys, platform services, and encrypted secrets.

## Docs

| Guide | Covers |
| --- | --- |
| [System design](docs/system-design.md) | Architecture, request and deploy flows, backups, secrets, monitoring |
| [Local setup](docs/local-setup.md) | Preparing a Mac, Windows or Linux machine to develop and test apps locally |
| [Server setup](docs/server-setup.md) | Installing and configuring the server, or rebuilding it from scratch |

## Layout

| Path | Contents |
| --- | --- |
| `ansible/` | Playbook and roles that configure the server; run from `ansible/` (see [Server setup](docs/server-setup.md), step 7) |
| `charts/app/` | Shared Helm chart used to deploy every app (added in a later setup step) |
| `platform/` | Cluster-wide services: Postgres, Cloudflare Tunnel, backups (added in a later setup step) |
| `secrets/` | SOPS-encrypted secrets (`prod.enc.yaml`), `*.enc.yaml` only, subfolders allowed |
| `docs/` | The guides above |
| `.githooks/` | Git hooks: secret scan before commit and push |
| `AGENTS.md`, `CLAUDE.md` | Rules and instructions for AI coding agents |
| `.claude/` | Claude Code settings, including the list of private files Claude may not read |

## First-time setup on a development machine

Requirements: Git, and Docker installed and running (see [Local setup](docs/local-setup.md)).

```bash
git clone git@github.com:<owner>/homeserver-infra.git
cd homeserver-infra
git config core.hooksPath .githooks
```

The hooks run gitleaks in Docker before each commit and push, and block them if a secret is found. If Docker is not running, the hooks block the commit or push and say so.

## Working with secrets

Secrets are encrypted with SOPS and age. The age private key is kept in Bitwarden, on the server and in one offline copy, and is never committed. To create the key or set it up on a new machine, see [Secrets in the server setup guide](docs/server-setup.md#secrets).

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt   # required on macOS
sops secrets/prod.enc.yaml                             # opens decrypted in your editor, re-encrypts on save
```

Only files ending in `.enc.yaml` can be committed under `secrets/`; Git ignores everything else there.

## Changes

All changes go through a branch and a pull request reviewed before merge to `main`.
