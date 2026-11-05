# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this repo is

Configuration for a single home server running Ubuntu Server 26.04 LTS and k3s. It holds Ansible playbooks, a shared Helm chart for app deploys, platform manifests and SOPS-encrypted secrets. Read `docs/system-design.md` before making changes.

## Rules

1. **No personal data.** No real names, email addresses, home IPs, domains, usernames or hostnames that identify the owner in code, config, docs, commit messages or logs. Use placeholders such as `<domain>`, `<owner>`, `<admin-user>`. Git author settings are set by the owner; leave them unchanged.
2. **No plaintext secrets.** Secrets live only in `secrets/*.enc.yaml`, encrypted with SOPS. Never print, log, echo or commit a decrypted value. Never create files ending in `.dec.yaml`.
3. **No exposed keys or private config.** This covers any private key or credentials file, inside or outside the repo: the age private key (`keys.txt`), kubeconfigs (including `k3s.yaml`), SSH and TLS private keys, `.env` files, API tokens and cloud credentials. Tools may use them, for example `sops` or `kubectl`, but never open, print, copy, log or commit their contents.
4. **No changes to the server, a repo's history or a remote without the owner's explicit approval.** Ask first before commits, pushes, tags, running playbooks, `kubectl apply` or `helm upgrade`. Work on a branch; every change reaches `main` through a reviewed pull request.
5. **Explain every `sudo` command** in docs and in answers: what it does and why it needs administrator rights.
6. **Ansible must be idempotent.** Running a playbook twice in a row must report no changes on the second run.
7. **Keep docs in sync.** Any change to how the server is built, deployed or operated updates the matching guide in `docs/` in the same pull request.
8. **Plain names.** Name features, roles and files in readable words, not codes.
9. **Docs state facts and instructions only.** No opinions or editorial notes.
10. **Batch open questions.** When a requirement is unclear, keep working on what is clear and collect the open questions into one list for the owner.

## Conventions

| Area | Convention |
| --- | --- |
| Line endings | LF everywhere (enforced by `.gitattributes`) |
| YAML | 2-space indent |
| Release tags (app repos) | `1.2.3`, no `v` prefix |
| Scheduled jobs | Kubernetes CronJobs with `timeZone: America/Toronto` and `concurrencyPolicy: Forbid` |
| Namespaces | One per app, with CPU and memory limits |

## Checks before proposing a change

- The pre-commit and pre-push hooks pass (gitleaks).
- For Ansible changes: after the owner approves the run, the playbook runs cleanly and a second run reports no changes.
- For chart changes: `helm lint charts/app` passes and the chart renders with `helm template`.
