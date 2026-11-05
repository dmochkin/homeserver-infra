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

1. **Tunnel:** in the Cloudflare dashboard, create a Cloudflare Tunnel and copy its token.
2. **DNS:** for each app subdomain, add a route from `<app>.<domain>` to `http://traefik.kube-system.svc.cluster.local:80`.
3. **R2:** create a bucket for backups and an API token limited to that bucket.
4. Add the tunnel token and R2 credentials to the encrypted secrets in this repo (see "Secrets" below). On first setup, create the age key first.

## 6. Prepare GitHub runners

For each app repo: **Settings → Actions → Runners → New self-hosted runner**, copy the registration token, and add it to the encrypted secrets. Tokens expire after an hour, so do this right before step 7.

## 7. Run Ansible from the admin machine

```bash
# once: install Ansible and SOPS
brew install ansible sops age          # macOS
# Linux/WSL: sudo apt install -y ansible age; install sops from its GitHub releases

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
| firewall | Deny all incoming; allow SSH only on the Tailscale interface |
| docker | Docker Engine for image builds |
| k3s | Single-node k3s with secrets encryption at rest; kubeconfig reachable over Tailscale only |
| platform | Namespaces, cloudflared tunnel, Postgres 17, backup and restore-test jobs |
| runners | One GitHub Actions runner service per app repo, the shared build lock, image pruning (keep 3) |
| secrets | Decrypts SOPS secrets and applies them as Kubernetes Secrets |
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

## Routine operations

| Task | How |
| --- | --- |
| Update the server config | Change the playbook, open a PR, merge, rerun step 7 |
| Add a new app | Add its settings to the shared chart values, a runner role entry and DNS route; rerun step 7 |
| Check disk health | `sudo smartctl -a /dev/sda` (reading a raw disk device needs administrator rights) |
| Reboot | `sudo reboot` (only an administrator may restart the system); apps come back on their own |
