# Local Setup (macOS, Windows, Linux)

Set up a development machine so any app can be run and tested locally before anything is pushed. The only requirements are Git and Docker; Java, Maven, Postgres and the test tools all run in containers.

## 1. Install the tools

### macOS

1. Install Homebrew from <https://brew.sh>.
2. Install Git: `brew install git`
3. Install Docker Desktop from <https://www.docker.com/products/docker-desktop/> (free for personal use). Start it once and accept the prompts.
4. Optional: install VS Code from <https://code.visualstudio.com>.

### Windows 11

Code and tools live inside Ubuntu on WSL 2; VS Code runs on Windows and connects to it.

1. In PowerShell as administrator:

    ```powershell
    wsl --install -d Ubuntu-26.04
    ```

    Restart when asked, then open **Ubuntu** from the Start menu and create a Linux user.
2. Cap the memory WSL can use. Create `%UserProfile%\.wslconfig`:

    ```ini
    [wsl2]
    memory=8GB
    ```

    Then run `wsl --shutdown` in PowerShell and reopen Ubuntu.
3. Check that systemd is on: `cat /etc/wsl.conf` should contain `[boot]` and `systemd=true`. If not, add those two lines and run `wsl --shutdown` again.
4. Inside Ubuntu, follow the **Linux** steps below.
5. Install VS Code on Windows and its **WSL** extension.
6. Always keep repos inside Ubuntu (for example `~/Developer`), never on `C:\`. Builds on `C:\` are very slow.

Docker Desktop for Windows also works; if you use it, turn on its WSL 2 integration for Ubuntu and still keep repos inside Ubuntu.

### Linux (Ubuntu or Debian)

1. Install Git: `sudo apt update && sudo apt install -y git`

    `sudo` is needed because `apt` refreshes the system package list and installs software system-wide.
2. Install Docker Engine by following <https://docs.docker.com/engine/install/ubuntu/>.
3. Let your user run Docker without `sudo`:

    ```bash
    sudo usermod -aG docker $USER
    ```

    This adds your user to the `docker` group. `sudo` is needed because changing group membership edits system account files. Members of the `docker` group have root-equivalent access to the machine through Docker.

    Log out and back in.
4. Check: `docker run --rm hello-world`

## 2. Configure Git and GitHub

Run these once on each machine (inside Ubuntu on Windows):

```bash
git config --global user.name "<your name>"
git config --global user.email "<id>+<username>@users.noreply.github.com"
git config --global init.defaultBranch main
git config --global core.autocrlf input
```

Use your GitHub no-reply address so no personal email lands in commits.

Create an SSH key and add the public key to GitHub (**Settings → SSH and GPG keys**):

```bash
ssh-keygen -t ed25519 -C "<machine name>"
cat ~/.ssh/id_ed25519.pub
```

Check: `ssh -T git@github.com`

## 3. Run an app

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone git@github.com:<owner>/<app>.git
cd <app>
cp .env.example .env          # fill in values only if you use real test accounts
git config core.hooksPath .githooks
docker compose up --build
```

| Address | What it is |
| --- | --- |
| `http://localhost:8080` | The app |
| `http://localhost:8025` | Mailpit: every email the app sends lands here |

Stop with `Ctrl+C`; remove containers and data with `docker compose down -v`.

### Stand-ins for outside services

By default nothing leaves your machine:

- Email goes to Mailpit, not Gmail.
- Calendars come from sample files in the repo.
- AI calls return canned text.
- Sample data is generated; no personal data.

To check against real services, put the **test** Google account and **test** Anthropic key values in `.env`. Never use personal accounts locally.

## 4. Test

| Command | When it runs | What it runs |
| --- | --- | --- |
| `./scripts/test-fast.sh` | Automatically before every push (pre-push hook) | Fast tests and gitleaks |
| `./scripts/test-full.sh` | Before opening a PR, and on every PR in CI | Full suite, including integration tests against a real Postgres |

Both scripts run in Docker, so they work the same on every machine. A failed pre-push check blocks the push.

Every new or changed class or method gets tests, including tests of the code that calls it.

## 5. Optional: prod-like check with k3d

Runs the app in a local Kubernetes cluster with the same Helm chart prod uses. Never required; useful before a release.

### Install the extra tools

| | macOS | Linux and WSL |
| --- | --- | --- |
| k3d | `brew install k3d` | see <https://k3d.io> |
| kubectl | `brew install kubectl` | see <https://kubernetes.io/docs/tasks/tools/> |
| Helm | `brew install helm` | see <https://helm.sh/docs/intro/install/> |

### Run the check

```bash
# 1. Create a local cluster
k3d cluster create local --port "8081:80@loadbalancer"

# 2. Build the app image and load it into the cluster
docker build -t <app>:local .
k3d image import <app>:local -c local

# 3. Deploy with the shared chart and the app's local settings
helm upgrade --install <app> ../homeserver-infra/charts/app \
  -f deploy/values.yaml -f deploy/values-local.yaml \
  --set image.tag=local -n <app> --create-namespace

# 4. Check it
kubectl -n <app> get pods
# then open http://<app>.localhost:8081

# 5. Clean up
k3d cluster delete local
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `permission denied` on Docker (Linux, WSL) | Log out and back in after `usermod -aG docker`, or run `newgrp docker` |
| `docker: not found` from Git hooks or an app, though Docker is installed | Restart the terminal or app (VS Code, a Git app, Claude). Apps opened before Docker was installed don't see its folder on `PATH`. |
| Very slow builds on Windows | Move the repo from `C:\` into Ubuntu's home folder |
| Scripts fail with `\r` errors | Run `git config --global core.autocrlf input`, then re-clone |
| Port already in use | Stop the other app, or change the port in `.env` |
| WSL uses too much memory | Lower `memory=` in `.wslconfig`, then `wsl --shutdown` |
