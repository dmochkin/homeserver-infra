# Server Setup (Linux host)

Set up a new home server, or rebuild a lost one, from bare hardware to running apps. Steps 1–6 are manual; step 7 onwards is done by Ansible from the admin machine.

Commands for the Ansible steps are the intended interface; they are finalized as the playbooks are written.

## What you need

| Item | Notes |
| --- | --- |
| Server | x86-64 mini PC with UEFI firmware, 16 GB RAM, SSD (currently an Asus Chromebox 3, CN65, with MrChromebox UEFI firmware) |
| Network | Ethernet to the home router |
| USB stick | 8 GB or more, for the installer |
| For the install only | A USB keyboard and an HDMI monitor or TV |
| Admin machine | Mac, Windows (WSL 2) or Linux set up with the local setup guide |
| Accounts | Cloudflare (domain, Tunnel, R2), GitHub, Tailscale, Better Stack |
| Secrets key | The age private key, from Bitwarden |

## 1. Prepare the hardware

1. Connect Ethernet, the keyboard and the monitor, then power on.
2. On the boot screen, confirm the firmware is MrChromebox UEFI (the current server shows version 2606.1).
3. To boot from USB: plug in the installer stick, press `Esc` at the boot screen, choose **Boot Manager**, then the USB stick.

Power-on after an outage is checked by an unplug test in step 3, not a BIOS setting.

## 2. Install Ubuntu Server 26.04 LTS

1. Download the Ubuntu Server 26.04 LTS ISO from <https://ubuntu.com/download/server>.
2. Write it to the USB stick with balenaEtcher (any OS) or Rufus (Windows).
3. Boot the server from the USB stick and choose:
    - **Ubuntu Server (minimized)** is not needed; the standard install is fine.
    - Network: wired, DHCP.
    - Storage: use the entire disk.
    - Server name: `homeserver` (or your choice).
    - Your admin user name and a strong password (stored in Bitwarden).
    - **Install OpenSSH server**: yes. **Import SSH identity from GitHub**: yes, with your GitHub user name.
    - No extra snaps.
4. Remove the USB stick and reboot.

## 3. First login (from the home network only)

From the admin machine:

```bash
ssh <admin-user>@<server-ip-on-home-network>
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y smartmontools lm-sensors stress-ng
lsblk                                   # find the disk name, e.g. sda
sudo smartctl -a /dev/sda               # "overall-health" must say PASSED
stress-ng --cpu 8 --timeout 10m &       # full load for 10 minutes
watch -n 5 sensors                      # CPU should stay well under 90 °C
```

What the `sudo` commands do and why they need administrator rights:

| Command | What it does | Why `sudo` |
| --- | --- | --- |
| `sudo apt update && sudo apt full-upgrade -y` | Refreshes the package list and installs all available updates | Changes system-wide software |
| `sudo apt install -y smartmontools lm-sensors stress-ng` | Installs the disk health, temperature and load-test tools | Installs software system-wide |
| `sudo smartctl -a /dev/sda` | Reads the disk's SMART health report | Reading a raw disk device is limited to root |

Then the unplug test:

1. `sudo poweroff` (shuts the machine down; `sudo` is needed because only an administrator may power off the system), wait until it's off, unplug the power, wait 30 seconds, plug it back in.
2. It should start by itself. If it doesn't, note it as a known risk: after an outage someone has to press the power button.

Optional: reserve the server's IP in the home router's DHCP settings so it doesn't change.

## 4. Join Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

- The install script adds the Tailscale package repository and installs Tailscale. It calls `sudo` itself and asks for your password, because it changes system package sources and installs a system service.
- `sudo tailscale up` connects the machine to your tailnet. `sudo` is needed because it configures the system-wide Tailscale service and network interface.

Open the link it prints, approve the machine in Tailscale, and note its Tailscale name.

On the admin machine, make sure Tailscale is running, then add this entry to `~/.ssh/config`. Ansible reads the server's address and admin user from it, so neither is kept in the repo.

```
Host homeserver
  HostName <tailscale-name>
  User <admin-user>
  IdentityFile ~/.ssh/id_ed25519
```

From now on, connect only over Tailscale:

```bash
ssh homeserver
```

After step 7 the firewall allows SSH only over Tailscale, so an entry that points at the server's home-network address stops working.

## 5. Prepare Cloudflare

1. **Tunnel:** in the Cloudflare dashboard, go to **Networking → Tunnels** and select **Create a tunnel** (name it, for example, `homeserver`). Don't run the install command it offers; cloudflared runs in the cluster. To get the token of an existing tunnel, open it, select **Add a replica** on the **Overview** tab, and copy the `eyJ…` string from the command. **Refresh token** on the same tab replaces a leaked token.
2. **Routes:** on the tunnel's **Routes** tab, for each app select **Add route → Published application**: subdomain `<app>`, your domain, service URL `http://traefik.kube-system.svc.cluster.local:80`. The first route is `status`, for the hello-world status page.
3. **R2:** create a bucket for backups and an API token limited to that bucket.
4. Add the values to `secrets/prod.enc.yaml` (see "Secrets" below). On first setup, create the age key first.

    | Field | Value |
    | --- | --- |
    | `cloudflare_tunnel_token` | The tunnel token (`eyJ…`) |
    | `domain` | The domain, without `https://` or `www.` |

    R2 credentials are added in the backups step.

## 6. Prepare GitHub runners

Runners are registered by Ansible in step 7: for each repo listed in `runner_repos` (in `ansible/group_vars/all.yml`), it asks GitHub for a fresh registration token with `gh` on the admin machine. No token is stored.

1. On the admin machine, sign in to GitHub CLI once with an account that administers the app repos: `gh auth login`.
2. In each app repo, under **Settings → Actions → General**, set fork pull request workflows to require approval for all outside collaborators. Pull request tests run on GitHub-hosted runners; only tag deploys run on the server.

## 7. Run Ansible from the admin machine

```bash
# once: install Ansible, SOPS, Helm and kubectl
brew install ansible sops age helm kubectl          # macOS
# Linux/WSL: sudo apt install -y ansible age; install sops, helm and kubectl from their official releases
helm plugin install https://github.com/databus23/helm-diff --version v3.15.15   # lets Ansible detect Helm release changes reliably

cd ~/Developer/homeserver-infra/ansible
ansible-galaxy collection install -r requirements.yml
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt   # the age key from Bitwarden
ansible-playbook site.yml --ask-become-pass
```

- On Linux and WSL, `sudo apt install` installs Ansible and age system-wide, which needs administrator rights. On macOS, Homebrew installs without `sudo`.
- `--ask-become-pass` asks for the admin user's password on the server. Ansible connects as the admin user with its SSH key, then uses `sudo` on the server for every task, because each one changes system configuration: packages, SSH settings, systemd units and the firewall.
- The playbook first checks that it is connected over Tailscale and stops if it is not, so the firewall cannot cut off the session it runs in.

The playbook does, in order:

| Role | What it sets up |
| --- | --- |
| base | SSH keys only, no root or password login; time zone; daily automatic security updates; a reboot on Sundays at 4am only when an update requires one; fail2ban on SSH |
| firewall | Deny all incoming from the home network and the internet; allow SSH on the Tailscale interface. Tailscale accepts tailnet traffic before ufw, so this does not limit access from your own devices. |
| docker | Docker from Ubuntu's packages (updated with the system), with log and build cache limits |
| k3s | Single-node k3s (pinned version) with secrets encryption at rest; Kubernetes API reachable only over Tailscale; no built-in load balancer and Traefik reachable only inside the cluster, so no ports open on the host; writes `~/.kube/config` on the admin machine, pointed at the server's Tailscale name |
| platform | cloudflared, installed with Cloudflare's Helm chart from the admin machine (Postgres 17, backup and restore-test jobs are added in later steps). The status page at `status.<domain>` is the hello-world app repo, deployed by tag. |
| runners | Helm on the server; the shared chart in `/opt/homeserver/charts/app`; the `homeserver-deploy` script (build lock, build, import, `helm upgrade`, keep 3 images); a `github-runner` user in the `docker` group, allowed to run only the image helper as root; one GitHub Actions runner service per repo in `runner_repos` |
| secrets | Decrypts each `secrets/apps/<app>.enc.yaml` on the admin machine and applies it as the Kubernetes Secret `<app>-env` (restarting the app when it changes); copies the age private key to `/etc/homeserver/age/keys.txt` (root only) |
| monitoring | Heartbeat URLs for jobs, backups and deploys |

The playbook is safe to run again; a second run should report no changes.

## 8. Restore data (rebuild only)

```bash
cd ~/Developer/homeserver-infra/ansible
ansible-playbook restore.yml -e backup=latest --ask-become-pass
```

Downloads the latest backup from R2, decrypts it and restores each database.

## 9. Verify

- [ ] `kubectl get nodes` (from the admin machine over Tailscale) shows the node `Ready`
- [ ] `https://status.<domain>` loads
- [ ] Better Stack shows every check green
- [ ] Each runner shows **Idle** in its repo's GitHub settings
- [ ] Tagging the hello-world app deploys it in under 10 minutes
- [ ] Stopping the hello-world app triggers an alert email
- [ ] Last night's backup exists in R2 (after the first night)
- [ ] `ssh` from outside Tailscale is refused

## Secrets

Secrets are encrypted with SOPS using one age key pair. The public key is in `.sops.yaml` and is safe to commit. The private key decrypts every secret and every backup; it is kept in Bitwarden, on the server and in one offline copy, and never in the repo.

### Create the key (first setup only)

Do this once, before the first secret is added in step 5. On a rebuild, skip it and use the existing key from Bitwarden.

```bash
brew install sops age                   # macOS; for Linux and WSL see step 7
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

1. `age-keygen` prints the public key, which starts with `age1`. Replace `<age-public-key>` in `.sops.yaml` with it and open a pull request.
2. Save the full contents of `keys.txt` in Bitwarden.
3. Make the offline copy.

### Use the key on an admin machine

Copy the private key from Bitwarden into `~/.config/sops/age/keys.txt`, then:

```bash
chmod 600 ~/.config/sops/age/keys.txt                  # readable only by your user
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt   # macOS looks elsewhere by default
```

### Edit secrets

```bash
sops secrets/prod.enc.yaml      # opens decrypted in your editor, re-encrypts on save
```

- Encrypted files go in `secrets/` (subfolders allowed) and end in `.enc.yaml`. Git ignores every other file in `secrets/`.
- SOPS encrypts values, not field names. Put secrets and personal data only in values.
- Never commit a decrypted file. gitleaks blocks commits and pushes that contain secrets.

### App secrets

Each app's secret settings live in `secrets/apps/<app>.enc.yaml`, named after the app, one environment variable per line:

```yaml
DATABASE_PASSWORD: "…"
GOOGLE_CLIENT_SECRET: "…"
```

1. Create or edit the file: `sops secrets/apps/<app>.enc.yaml`. Quote every value; the playbook stops and names any value that is not a quoted string.
2. In the app repo, set `envSecret: <app>-env` in `deploy/values.yaml`.
3. Rerun step 7. Ansible applies the file as the Kubernetes Secret `<app>-env` in the app's namespace and restarts the app if the secrets changed.

## Routine operations

| Task | How |
| --- | --- |
| Update the server config | Change the playbook, open a PR, merge, rerun step 7 |
| Add a new app | In the app repo, add `deploy/values.yaml` and the deploy and test workflows (copy them from the hello-world repo). Add the repo to `runner_repos`, add its secrets if it has any (see "App secrets"), rerun step 7, add a Cloudflare route for its subdomain, then push a release tag. |
| Check disk health | `sudo smartctl -a /dev/sda` (reading a raw disk device needs administrator rights) |
| Reboot | `sudo reboot` (only an administrator may restart the system); apps come back on their own |
