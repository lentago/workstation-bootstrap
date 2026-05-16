# Workstation Bootstrap

Single-command scripts that turn a fresh Linux environment into a fully configured cloud infrastructure development workstation. Three variants, same tools, same prompt, same workflow.

```
workstation-bootstrap/
├── setup-crostini-lab.sh          # Chromebook Crostini (Debian container)
├── setup-xubuntu-workstation.sh   # Xubuntu 24.04 LTS VM (Proxmox)
├── setup-fedora-workstation.sh    # Fedora KDE Plasma VM (Proxmox)
├── setup-ubuntu-laptop.sh         # Ubuntu Desktop LTS on bare-metal laptop
├── README.md
└── LICENSE
```

## Quick start

Pick the script that matches your environment and run it:

**Chromebook (Crostini):**
```bash
# Download first (recommended):
curl -sLO https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-crostini-lab.sh
GH_TOKEN=ghp_yourtoken bash setup-crostini-lab.sh

# Or pipe directly (note: GH_TOKEN goes AFTER the pipe):
curl -sL https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-crostini-lab.sh | GH_TOKEN=ghp_yourtoken bash
```

**Xubuntu 24.04 VM:**
```bash
curl -sLO https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-xubuntu-workstation.sh
GH_TOKEN=ghp_yourtoken bash setup-xubuntu-workstation.sh
```

**Fedora KDE Plasma VM:**
```bash
curl -sLO https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-fedora-workstation.sh
GH_TOKEN=ghp_yourtoken bash setup-fedora-workstation.sh
```

**Ubuntu Desktop laptop (bare metal):**
```bash
curl -sLO https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-ubuntu-laptop.sh
GH_TOKEN=ghp_yourtoken bash setup-ubuntu-laptop.sh
```

Omit `GH_TOKEN=...` for interactive runs — the script will prompt you to authenticate via `gh auth login`.

> **Why download first?** The `curl | bash` pattern sets `GH_TOKEN` for the `bash` process (not `curl`), but stdin is consumed by the pipe so interactive prompts won't work. Downloading first avoids both issues.

## What they install

Every script installs the same toolchain:

| Category | Tools |
|---|---|
| **Languages** | Python 3 + pip + venv, Node.js LTS (via nvm), Go, Bash |
| **Cloud & IaC** | AWS CLI v2, Granted (account switching), Terraform + tfswitch, kubectl, eksctl, Helm |
| **Containers** | Docker (see variant differences below) |
| **Dev tools** | VS Code (with extensions + settings), Claude Code, GitHub CLI, git (configured) |
| **CLI tools** | jq, yq, bat, ripgrep, fd-find, fzf, tree, tmux, shellcheck, direnv, pipx, tldr |
| **Networking** | dig/nslookup, net-tools, traceroute, nmap, whois |
| **Shell** | Starship prompt (custom config), aliases, functions, direnv |
| **Your code** | Auto-clones all your GitHub repos into `~/repos/` |

## How they differ

The scripts share ~80% of their code. The differences are driven by what each environment can and can't do.

| Area | Crostini | Xubuntu VM | Fedora KDE VM | Ubuntu laptop |
|---|---|---|---|---|
| **Package manager** | `apt-get` (Debian) | `apt-get` (Ubuntu) | `dnf` (Fedora RPM) | `apt-get` (Ubuntu) |
| **Docker** | CLI-only (no daemon) | Full engine + daemon | Full engine + daemon (replaces podman) | Full engine + daemon |
| **Remote desktop** | N/A (local terminal) | XRDP + XFCE | XRDP + KDE Plasma X11 | N/A (local GNOME) |
| **SSH server** | No | Yes | Yes | Yes |
| **SELinux** | No | No | Enforcing (xrdp policy configured) | No |
| **Firewall** | None | None (ufw not default) | firewalld (port 3389 opened) | None (ufw not default) |
| **Polkit rules** | N/A | `.pkla` format | JavaScript `.rules` format | N/A |
| **Compositor fix** | N/A | xfwm4 XML | KWin `kwinrc` | N/A |
| **Wayland** | N/A | N/A (X11 default) | Forced to X11 for XRDP | Default (GNOME local) |
| **VM integration** | N/A | qemu-guest-agent | qemu-guest-agent | N/A (bare metal) |
| **Power management** | N/A | N/A | N/A | TLP (replaces power-profiles-daemon) |
| **Firmware updates** | N/A | N/A | N/A | fwupd (LVFS) |
| **Battery thresholds** | N/A | N/A | N/A | ThinkPad: 75-80% (configurable) |
| **Starship install** | `~/.local/bin` (broken sudo workaround) | `/usr/local/bin` | `/usr/local/bin` | `/usr/local/bin` |
| **bat/fd names** | `batcat`/`fdfind` (Debian conflict) | `batcat`/`fdfind` (Ubuntu conflict) | `bat`/`fd` (clean) | `batcat`/`fdfind` (Ubuntu conflict) |
| **Granted install** | APT repo | APT repo | Binary download (no DNF repo) | APT repo |
| **Steps** | 14 | 15 | 15 | 15 |

### When to use which

- **Crostini** — You're on a Chromebook and want a local dev environment. Lightweight, disposable, no Docker daemon (point `DOCKER_HOST` at a remote). Start here.
- **Xubuntu** — You have a Proxmox host (or any hypervisor) and want a persistent workhorse VM with full Docker. XFCE is lighter on resources. Good default.
- **Fedora KDE** — You want KDE Plasma's desktop, Fedora's fresh packages, and SELinux enforcing by default. Slightly heavier, more opinionated, better desktop experience for power users.
- **Ubuntu laptop** — You're sitting in front of a real laptop (developed against a refurbished ThinkPad T14, but works for any Ubuntu Desktop machine). Same toolchain as Xubuntu, no XRDP/QEMU agent, plus TLP for battery thresholds and fwupd for firmware updates. Use this for bare metal; use Xubuntu/Fedora for VMs.

## Why this exists

I'm a systems architect who works from a Chromebook. My Linux environments are disposable — ChromeOS updates corrupt Crostini, VMs get rebuilt, hypervisors get reinstalled. Instead of spending half a day manually configuring tools, I run one command and go get coffee.

**The philosophy: the script is the source of truth, not the machine.** Your dev environment is cattle, not a pet. Same principle you'd apply to any infrastructure you manage.

The day after finishing the Crostini script, my VM refused to start. Corrupted metadata. Unrecoverable. Deleted everything, re-enabled Linux, ran `curl | bash`, and was back in fifteen minutes. The script paid for itself in under 24 hours.

## Customization

### Environment variables

All scripts accept the same environment variables:

| Variable | Default | Description |
|---|---|---|
| `GH_TOKEN` | *(none)* | GitHub PAT (scopes: `repo`, `read:org`) — enables non-interactive auth and repo cloning |
| `GIT_NAME` | *(auto-detected)* | Git commit author name — from gh profile, git config, or prompt |
| `GIT_EMAIL` | *(auto-detected)* | Git commit author email — from gh profile, git config, or prompt |
| `GITHUB_USER` | *(auto-detected)* | GitHub username for repo cloning — from gh auth session |
| `GITHUB_ORG` | *(none)* | GitHub organization — clones org repos alongside personal repos when set |
| `GITHUB_DEFAULT_OWNER` | *(none)* | Default owner for `gh repo create` — powers the `ghnew` and `ghclone` aliases |
| `REPOS_DIR` | `~/repos` | Where to clone repos |

All identity values are auto-detected from your GitHub profile after authentication. You only need environment variables if you want to override defaults or run fully unattended.

The `read:org` scope on `GH_TOKEN` is required to list and clone repos from a GitHub organization. Without it, personal repo cloning still works but org cloning will silently return no results.

### Persistent config file

On first run, each script creates a config template at `~/.config/workstation-bootstrap/config`. This file is sourced on every subsequent run and in every new shell (via `.bashrc`), so your preferences persist without passing environment variables each time.

```bash
# ~/.config/workstation-bootstrap/config
GITHUB_ORG="YourOrg"
GITHUB_DEFAULT_OWNER="YourOrg"
```

The scripts will never overwrite an existing config file. Environment variables still take precedence — if you pass `GITHUB_ORG=something` at the command line, it overrides whatever is in the config file for that run.

### Org-aware aliases

When `GITHUB_DEFAULT_OWNER` is set (via config file or environment), two aliases become available:

- **`ghnew`** — `gh repo create --owner $GITHUB_DEFAULT_OWNER` (create repos under your org by default)
- **`ghclone`** — `gh repo clone $GITHUB_DEFAULT_OWNER/` (clone org repos without typing the owner prefix)

## The Starship prompt

All three scripts install the same custom [Starship](https://starship.rs) prompt designed for infrastructure work:

```
 main [!] 💠 default ☁️  aws-lab (us-east-1) took 9s
ubuntu 24.04 xubuntu:~/repos/foundry-platform-demo/environments/dev ❯
```

- **Line 1 (context):** Git branch + dirty status, Terraform workspace, AWS profile + region, k8s context, Docker context, command duration — only appears when relevant
- **Line 2 (working line):** OS distro + version, hostname, full absolute path, cursor

The OS label is pulled from `/etc/os-release` via a custom Starship module: `debian 12` (Crostini), `ubuntu 24.04` (Xubuntu), `fedora 41` (Fedora KDE). When working across three environments, the label tells you at a glance which package manager and system conventions apply.

When there's no active context, it collapses to a single line:

```
debian 12 penguin:~ ❯
```

The VM variants (Xubuntu, Fedora) add a Docker context module and show the hostname (useful when SSH'd in from the Chromebook).

## Shell functions included

All three scripts install the same functions:

- **`projects`** — Lists all repos in `~/repos/` with current branch and dirty status
- **`pull-all`** — Runs `git pull --rebase` on every repo in `~/repos/`
- **`venv [name]`** — Creates and activates a Python venv in one step
- **`mkcd <dir>`** — `mkdir -p` + `cd` combined

## VS Code configuration

Same across all variants:

**Extensions:** HashiCorp Terraform + HCL, Docker, AWS Toolkit, Python, Go, Claude Code, YAML (Red Hat), GitLens, ShellCheck, Remote SSH

**Settings highlights:**
- Autosave on focus change (switch to terminal → file saves)
- Format on save with Terraform formatter wired to HashiCorp extension
- Trim trailing whitespace + insert final newline
- Telemetry disabled
- 15px font, 2-space tabs, bracket pair colorization

## Design decisions (and the bugs that informed them)

These scripts were developed through iterative field testing on real hardware. Every design choice has a story.

### Shared across all scripts

**PATH bootstrapping** — The single biggest lesson from the Crostini version. Tools installed during the script need to be findable *during the script*, not just after `.bashrc` is sourced. All three scripts bootstrap PATH at the very top before any installs happen.

**nvm triple-fix** — The nvm installer has three gotchas on a fresh VM: (1) `$NVM_DIR` must exist before the installer runs, (2) source nvm *after* install not before, (3) `PROFILE=/dev/null` prevents duplicate `.bashrc` entries.

**The `set -e` arithmetic trap** — In bash, `((count++))` returns exit code 1 when `count` is 0, which kills `set -e`. All scripts use `((count++)) || true`.

**Clone via HTTPS, not SSH** — Fresh VMs don't have SSH keys. `gh auth setup-git` configures HTTPS auth through the GitHub CLI. One less thing to manage.

**OS module** — A custom Starship module reads `/etc/os-release` to show the distro name and version (e.g. `debian 12`, `fedora 41`) in the prompt. Plain text — no emoji, no Nerd Font dependency. When working across three environments, the label tells you which package manager and system conventions apply.

**VS Code debconf pre-seed** — The `code` .deb package asks via debconf whether to add Microsoft's APT repository. Even with `apt-get -y`, this debconf question blocks in non-interactive mode. Fix: `debconf-set-selections` pre-seeds the answer before install.

### Crostini-specific

**Crostini's broken sudo** — Third-party install scripts that invoke `sudo` internally hit a password prompt on Crostini. Workaround: install to `~/.local/bin` instead of `/usr/local/bin`.

### Xubuntu-specific

**XRDP: TLS key permissions** — xrdp runs as user `xrdp`, which can't read the snakeoil SSL key without being in the `ssl-cert` group.

**XRDP: D-Bus session collision** — If a local XFCE session is running, the RDP session inherits its D-Bus address and fails. Fix: unset `DBUS_SESSION_BUS_ADDRESS` in startwm.sh.

**XRDP: XFCE compositor + software GL** — xfwm4 enables OpenGL compositing by default, falls back to llvmpipe on a VM, and crashes at high resolutions. Fix: disable compositing via xfconf XML.

### Fedora-specific

**The podman conflict** — Fedora ships podman as the default `docker` command. The script removes podman/buildah before installing Docker CE. Deliberate trade-off: the AWS/ECS/ECR toolchain assumes Docker.

**SELinux and XRDP** — The #1 reason XRDP "works on Ubuntu but not Fedora." The script sets SELinux booleans, registers port types, and generates local policy modules from audit denials. Belt and suspenders because SELinux denial symptoms (silent drops, black screens, misleading error messages) don't point at SELinux as the cause.

**KDE Plasma: Wayland trap** — Fedora KDE defaults to Wayland via SDDM. XRDP can't render Wayland. The startwm.sh forces `startplasma-x11` with `XDG_SESSION_TYPE=x11`.

**KWin compositor** — Same software-GL-at-high-resolution problem as XFCE, different config mechanism (`kwinrc` instead of xfconf XML).

**Polkit rules format** — Fedora deprecated `.pkla` in favor of JavaScript `.rules` files.

**firewalld** — Fedora runs it by default. Without opening port 3389, XRDP installs perfectly and nothing connects.

**Granted: no DNF repo** — Common Fate maintains an APT repo but not a DNF repo. The Fedora script downloads the binary directly from GitHub releases.

**`dnf config-manager` syntax change** — Fedora 41+ changed the subcommand format. The script tries both old and new syntax.

## Idempotent

All three scripts are safe to re-run at any time. Each checks for existing installations before doing anything, and the `.bashrc` configuration block is replaced cleanly on each run (bounded by marker comments). The Xubuntu and Fedora scripts also clean up markers from the other variants if you're migrating between environments.

The workstation config file at `~/.config/workstation-bootstrap/config` is never overwritten on re-run — only created if it doesn't exist yet.

## Requirements

**Crostini:**
- Chromebook with Crostini support (most devices from 2019+)
- Linux development environment enabled (Settings → Developers → Turn on)
- ~10 minutes and an internet connection

**Xubuntu VM:**
- Proxmox VE host (or any hypervisor)
- Xubuntu 24.04 LTS installed as a VM
- At least 2 vCPUs, 8 GiB RAM, 50 GiB disk recommended

**Fedora KDE VM:**
- Proxmox VE host (or any hypervisor)
- Fedora KDE Plasma installed as a VM (KDE Spin ISO or Fedora Everything + KDE group)
- At least 2 vCPUs, 8 GiB RAM, 50 GiB disk recommended

**Ubuntu Desktop laptop:**
- Any laptop running Ubuntu Desktop 24.04 LTS or newer
- ThinkPad recommended for charge-threshold support (script auto-detects and skips on unsupported hardware)
- ~10 minutes and an internet connection

## Credits

Built iteratively with [Claude](https://claude.ai) (Anthropic) through multi-day pair-programming sessions that included real-time field testing on actual Chromebook and Proxmox hardware. Seven bug fixes in the Crostini version, three layers of XRDP debugging in the Xubuntu version, and SELinux/KDE/Wayland adaptation for the Fedora version — each discovered on real hardware, each baked into the scripts so nobody else has to debug them.

## License

MIT License — see [LICENSE](LICENSE).
