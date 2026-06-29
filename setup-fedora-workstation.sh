#!/usr/bin/env bash
# ============================================================================
# setup-fedora-workstation.sh — v1 (adapted from setup-xubuntu-workstation.sh)
# Fedora KDE Plasma on Proxmox VM — DevOps workstation bootstrap
#
# Author:  Chris Pitzi — Lentago Labs (https://github.com/lentago)
# Updated: 2026-04-01
#
# Lineage: Forked from setup-xubuntu-workstation.sh v1, which was forked from
#          setup-crostini-lab.sh v4. The Crostini version targets Chromebook
#          containers (Debian, CLI-only Docker, broken sudo workarounds).
#          The Xubuntu version targets full VMs (Docker Engine, XRDP + XFCE).
#          This version targets Fedora KDE Plasma with:
#            - dnf package manager (RPM-based, not DEB)
#            - Full Docker Engine (may conflict with podman — handled)
#            - XRDP remote desktop (configured for KDE Plasma X11 session)
#            - SELinux-aware (permissive adjustments for xrdp)
#            - Polkit JavaScript rules (not deprecated .pkla format)
#            - KWin compositor disabled for XRDP (software GL workaround)
#            - openssh-server + qemu-guest-agent for Proxmox
#
# Usage:
#   Quick start (download first — recommended):
#     curl -sLO https://raw.githubusercontent.com/lentago/workstation-bootstrap/main/setup-fedora-workstation.sh
#     GH_TOKEN=ghp_yourtoken bash setup-fedora-workstation.sh
#
#   Or pipe directly (note: GH_TOKEN goes AFTER the pipe):
#     curl -sL https://raw.githubusercontent.com/lentago/workstation-bootstrap/main/setup-fedora-workstation.sh | GH_TOKEN=ghp_yourtoken bash
#
# Environment variables (all optional — auto-detected when possible):
#   GH_TOKEN        GitHub personal access token (scopes: repo, read:org)
#                   If set, skips interactive gh auth login entirely.
#   GIT_NAME        Git user.name (auto-detected from gh profile or prompted)
#   GIT_EMAIL       Git user.email (auto-detected from gh profile or prompted)
#   GITHUB_USER     GitHub username for repo cloning (auto-detected from gh auth)
#   REPOS_DIR       Where to clone repos (default: ~/repos)
#
# IMPORTANT: Run with 'bash', not 'sh'. Fedora's sh is bash, but be explicit.
#            The shebang handles this if you chmod +x and use ./
#
# What this does:
#   1.  System basics & quality-of-life CLI tools
#   2.  Git config (interactive)
#   3.  Python 3 + pip + venv
#   4.  Node.js (LTS via nvm)
#   5.  Go (latest stable)
#   6.  AWS CLI v2 + Granted (account switching)
#   7.  Terraform + tfswitch
#   8.  kubectl + eksctl + Helm
#   9.  Docker Engine + docker-compose (full daemon, replaces podman)
#  10.  GitHub CLI (gh) + authenticate + clone repos
#  11.  VS Code (via Microsoft RPM repo)
#  12.  Claude Code
#  13.  Quality-of-life CLI tools
#  14.  Shell config (starship prompt, aliases, PATH wiring)
#  15.  XRDP configuration (remote desktop — KDE Plasma X11 session)
#
# Changes from Xubuntu version:
#   - Package manager: dnf instead of apt-get
#   - Base packages: Fedora names (bind-utils not dnsutils, @development-tools
#     not build-essential, etc.)
#   - Docker: Fedora repo, handles podman/buildah conflict
#   - VS Code: Microsoft RPM repo instead of DEB repo
#   - GitHub CLI: RPM repo instead of DEB repo
#   - Granted: binary download (no official DNF repo)
#   - Python: no python3-full or python3-venv packages needed (Fedora ships
#     a complete Python with venv support out of the box)
#   - SELinux: sets permissive context for xrdp (Fedora enforces by default)
#   - Polkit: JavaScript rules file (Fedora deprecated .pkla format)
#   - XRDP: KDE Plasma X11 session (not XFCE), KWin compositor disabled
#   - Starship: installs to /usr/local/bin (sudo works normally)
#   - bat/fd: clean names on Fedora (no batcat/fdfind aliasing needed)
#   - Removed Debian/Ubuntu-specific workarounds throughout
# ============================================================================

set -euo pipefail

# --- Global error trap -------------------------------------------------------
# If set -e kills the script unexpectedly, tell the user what step failed
# and that re-running is safe (all steps are idempotent).
CURRENT_STEP="initializing"
trap 'echo ""; echo -e "${RED}[FATAL] Script failed during: ${CURRENT_STEP}${NC}"; echo -e "${YELLOW}Re-run is safe — completed steps will be skipped (idempotent).${NC}"' ERR

# --- Config (overridable via environment variables) -------------------------
GITHUB_USER="${GITHUB_USER:-}"
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# --- Workstation config (personal overrides) --------------------------------
# Source user config if it exists. This lets you set GITHUB_ORG,
# GITHUB_DEFAULT_OWNER, and future preferences without editing the script.
WS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/workstation-bootstrap/config"
GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_DEFAULT_OWNER="${GITHUB_DEFAULT_OWNER:-}"

if [[ -f "$WS_CONFIG" ]]; then
  # shellcheck source=/dev/null
  . "$WS_CONFIG"
fi

# Detect whether stdin is a terminal (interactive) or piped (automated)
INTERACTIVE=false
[[ -t 0 ]] && INTERACTIVE=true

# --- Bootstrap PATH early ---------------------------------------------------
# Tools installed by this script land in these directories. We need them on
# PATH *during* the script run, not just after .bashrc is sourced. This lesson
# was learned the hard way in the Crostini version: install-time PATH and
# shell-config-time PATH must agree.
mkdir -p "$HOME/.local/bin" "$HOME/bin"
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

# --- Colors & helpers -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
skip()    { echo -e "${CYAN}[SKIP]${NC} $*"; }

section() {
  CURRENT_STEP="$*"
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  $*${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

command_exists() { command -v "$1" &>/dev/null; }

require() {
  local cmd="$1"
  local friendly="${2:-$1}"
  if ! command_exists "$cmd"; then
    fail "$friendly failed to install. Check the output above for errors."
  fi
}

TOTAL_STEPS=16

# --- Preflight --------------------------------------------------------------
section "Preflight Checks"

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "This script is for Linux. You're on $(uname -s)."
fi

if [[ -z "${BASH_VERSION:-}" ]]; then
  fail "This script requires bash. Run it with: bash $0"
fi

# Verify we're actually on Fedora
if [[ ! -f /etc/fedora-release ]]; then
  warn "This script is designed for Fedora. Detected: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
  warn "Continuing anyway — some package names may differ."
fi

# Detect if we're running on a Proxmox VM (informational, not gating)
if [[ -f /sys/class/dmi/id/product_name ]] && grep -qi "qemu\|proxmox\|kvm" /sys/class/dmi/id/product_name 2>/dev/null; then
  info "Detected: Proxmox/KVM virtual machine"
elif command_exists systemd-detect-virt && [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]]; then
  info "Detected: Virtual machine ($(systemd-detect-virt))"
fi

info "Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
info "User: $(whoami) | Home: $HOME"
info "GitHub user: ${GITHUB_USER:-<will auto-detect>} | Org: ${GITHUB_ORG:-<none>} | Repos dir: $REPOS_DIR"
info "Shell: bash $BASH_VERSION"
if [[ -n "${GH_TOKEN:-}" ]]; then
  info "Mode: non-interactive (GH_TOKEN set)"
elif [[ "$INTERACTIVE" == "true" ]]; then
  info "Mode: interactive (terminal detected)"
else
  info "Mode: non-interactive (piped, no GH_TOKEN)"
fi

# Check SELinux status (informational)
if command_exists getenforce; then
  SELINUX_STATUS=$(getenforce 2>/dev/null || echo "unknown")
  info "SELinux: $SELINUX_STATUS"
fi

# Harvest sudo credentials up front so the password prompt doesn't ambush
# us mid-install when the credential cache expires.
sudo -v
# Keep sudo alive in the background — prevents timeout during long installs.
(while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done) &

# --- Create workstation config template if it doesn't exist ---
WS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/workstation-bootstrap"
if [[ ! -f "$WS_CONFIG_DIR/config" ]]; then
  mkdir -p "$WS_CONFIG_DIR"
  if [[ -n "${GITHUB_ORG:-}" ]]; then
    _ws_org_line="GITHUB_ORG=\"${GITHUB_ORG}\""
  else
    _ws_org_line='#GITHUB_ORG=""'
  fi
  if [[ -n "${GITHUB_DEFAULT_OWNER:-}" ]]; then
    _ws_owner_line="GITHUB_DEFAULT_OWNER=\"${GITHUB_DEFAULT_OWNER}\""
  else
    _ws_owner_line='#GITHUB_DEFAULT_OWNER=""'
  fi
  cat > "$WS_CONFIG_DIR/config" << WS_CONF
# ============================================================================
# Workstation bootstrap config — sourced by setup-*-workstation.sh scripts
# Location: ~/.config/workstation-bootstrap/config
#
# This file personalizes your workstation without modifying the bootstrap
# scripts themselves. The scripts stay portable; your preferences live here.
# Re-running any bootstrap script will NOT overwrite this file.
# ============================================================================

# --- GitHub org to clone alongside personal repos --------------------------
# Set this to also clone all repos from a GitHub organization during
# bootstrap. Leave empty to only clone your personal repos.
# The bootstrap script clones BOTH personal and org repos when set.
${_ws_org_line}

# --- Default owner for new repos ------------------------------------------
# Used by the 'ghnew' alias to default gh repo create to this owner.
# Leave empty to default to your personal account.
${_ws_owner_line}
WS_CONF
  info "Created workstation config at $WS_CONFIG_DIR/config"
  info "Edit this file to set your GitHub org and other preferences."
fi

# --- 1. System update & base packages --------------------------------------
section "1/$TOTAL_STEPS — System Update & Base Packages"

sudo dnf upgrade -y --refresh -q

# Development tools group replaces Debian's build-essential.
# dnf5 (Fedora 41+) dropped the 'groupinstall' subcommand.
# The @group syntax works on both dnf4 and dnf5.
sudo dnf install -y -q @development-tools

BASE_PKGS=(
  curl
  wget
  git
  unzip
  zip
  gnupg2
  ca-certificates
  man-db
  less
  openssh-clients
  openssh-server           # SSH server for remote access
  qemu-guest-agent         # Proxmox VM integration
  bind-utils               # dig, nslookup, host (Debian: dnsutils)
  net-tools
  traceroute
  nmap
  whois
  htop
  ncdu
  nano
  nfs-utils                  # NFS client for mounting network shares
  findutils                # xargs, find
  procps-ng                # ps, top, etc.
  util-linux               # lsblk, etc.
  dnf5-plugins              # config-manager, copr, etc. (dnf5 replaces dnf-plugins-core)
)

info "Installing base packages..."
sudo dnf install -y -q "${BASE_PKGS[@]}"

# Enable SSH and guest agent
sudo systemctl enable --now sshd
sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true

success "Base packages installed."

# --- 2. Git config ----------------------------------------------------------
section "2/$TOTAL_STEPS — Git Configuration"

git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.autoSetupRemote true
git config --global core.editor "nano"
git config --global alias.st "status -sb"
git config --global alias.lg "log --oneline --graph --decorate -20"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.unstage "reset HEAD --"
git config --global alias.amend "commit --amend --no-edit"
git config --global alias.wip "!git add -A && git commit -m 'WIP'"
success "Git defaults configured (identity set after GitHub auth in step 10)."

# --- 3. Python 3 + pip + venv -----------------------------------------------
section "3/$TOTAL_STEPS — Python 3 + pip + venv"

# Fedora ships a complete Python 3 with venv support. No python3-full or
# python3-venv packages needed — those are Debian-isms.
sudo dnf install -y -q python3 python3-pip python3-devel
require python3 "Python 3"
success "Python $(python3 --version 2>&1 | awk '{print $2}') ready."

# --- 4. Node.js via nvm -----------------------------------------------------
section "4/$TOTAL_STEPS — Node.js (LTS via nvm)"

export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  info "Installing nvm..."
  # Ensure .bashrc exists so nvm's installer doesn't complain about missing profile
  touch "$HOME/.bashrc"
  # PROFILE=/dev/null prevents the installer from appending source lines
  # to .bashrc. We manage .bashrc ourselves in step 14.
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | \
    PROFILE=/dev/null bash
fi

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
else
  fail "nvm installed but nvm.sh not found at $NVM_DIR/nvm.sh. Check network/git."
fi

if ! command_exists node; then
  info "Installing Node.js LTS..."
  nvm install --lts
  nvm alias default 'lts/*'
else
  info "Node already installed, ensuring LTS is default..."
  nvm install --lts --default 2>/dev/null || true
fi

require node "Node.js"
success "Node $(node -v) + npm $(npm -v) ready."

# --- 5. Go ------------------------------------------------------------------
section "5/$TOTAL_STEPS — Go (latest stable)"

GO_VERSION="1.23.6"  # Bump this when new stable drops
GO_INSTALLED="$(go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+\.[0-9]+' || echo 'none')"

if [[ "$GO_INSTALLED" != "$GO_VERSION" ]]; then
  info "Installing Go ${GO_VERSION}..."
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz
fi

require go "Go"
success "Go $(go version | awk '{print $3}') ready."

# --- 6. AWS CLI v2 + Granted ------------------------------------------------
section "6/$TOTAL_STEPS — AWS CLI v2 + Granted (account switching)"

if ! command_exists aws || [[ "$(aws --version 2>&1)" != *"aws-cli/2"* ]]; then
  info "Installing AWS CLI v2..."
  cd /tmp
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip -qo awscliv2.zip
  sudo ./aws/install --update
  rm -rf aws awscliv2.zip
  cd ~
fi
require aws "AWS CLI"
success "AWS CLI $(aws --version 2>&1 | awk '{print $1}') ready."

# Granted: repo moved from common-fate/granted to fwdcloudsec/granted after
# Common Fate wound down. The releases.commonfate.io CDN is dead. Download
# directly from GitHub releases. Granted is MIT-licensed and will keep working,
# but expect no new releases.
# Docs: https://docs.commonfate.io/granted/getting-started
if ! command_exists granted; then
  info "Installing Granted..."
  GRANTED_VERSION=$(curl -fsSL https://api.github.com/repos/fwdcloudsec/granted/releases/latest | \
    python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2>/dev/null) || true

  if [[ -n "${GRANTED_VERSION:-}" ]]; then
    GRANTED_URL="https://github.com/fwdcloudsec/granted/releases/download/v${GRANTED_VERSION}/granted_${GRANTED_VERSION}_linux_x86_64.tar.gz"
    curl -fsSL "$GRANTED_URL" -o /tmp/granted.tar.gz
    tar -xzf /tmp/granted.tar.gz -C /tmp granted assume
    sudo install -m 0755 /tmp/granted /usr/local/bin/granted
    sudo install -m 0755 /tmp/assume /usr/local/bin/assume
    rm -f /tmp/granted.tar.gz /tmp/granted /tmp/assume
  else
    warn "Could not determine Granted version. Skipping."
  fi
fi

if command_exists granted; then
  success "Granted installed — use 'assume <profile>' to switch AWS accounts."
else
  warn "Granted not available — install manually: https://docs.commonfate.io/granted/getting-started"
fi

# --- 7. Terraform + tfswitch ------------------------------------------------
section "7/$TOTAL_STEPS — Terraform + tfswitch"

if ! command_exists tfswitch; then
  info "Installing tfswitch..."
  curl -fsSL https://raw.githubusercontent.com/warrensbox/terraform-switcher/release/install.sh | sudo bash
fi

if command_exists tfswitch; then
  success "tfswitch ready — run 'tfswitch' in any TF project to auto-select the right version."

  # tfswitch installs terraform to ~/bin/ by default. ~/bin is already on
  # PATH from our early bootstrap block.
  if ! command_exists terraform; then
    info "Installing latest Terraform via tfswitch..."
    tfswitch --latest
  fi
else
  warn "tfswitch install failed. Installing Terraform via HashiCorp RPM repo instead..."
  sudo dnf config-manager addrepo \
    --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo 2>/dev/null || \
  sudo dnf config-manager --add-repo \
    https://rpm.releases.hashicorp.com/fedora/hashicorp.repo 2>/dev/null || true
  sudo dnf install -y -q terraform
fi

if command_exists terraform; then
  success "Terraform $(terraform version -json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1) ready."
else
  warn "Terraform not installed — run 'tfswitch' after setup to install."
fi

# --- 8. kubectl + eksctl + Helm ---------------------------------------------
section "8/$TOTAL_STEPS — kubectl + eksctl + Helm"

if ! command_exists kubectl; then
  info "Installing kubectl..."
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /tmp/kubectl
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
fi
require kubectl "kubectl"
success "kubectl $(kubectl version --client -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || echo 'installed') ready."

if ! command_exists eksctl; then
  info "Installing eksctl..."
  PLATFORM="$(uname -s)_amd64"
  curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${PLATFORM}.tar.gz" | \
    tar xz -C /tmp
  sudo install -m 0755 /tmp/eksctl /usr/local/bin/eksctl
  rm -f /tmp/eksctl
fi
require eksctl "eksctl"
success "eksctl $(eksctl version 2>/dev/null || echo 'installed') ready."

if ! command_exists helm; then
  info "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
require helm "Helm"
success "Helm $(helm version --short 2>/dev/null || echo 'installed') ready."

# --- 9. Docker Engine -------------------------------------------------------
# Full Docker Engine with daemon. Fedora ships podman by default; Docker CE
# may conflict with it. We handle the removal gracefully.
section "9/$TOTAL_STEPS — Docker Engine + Compose"

if ! command_exists docker || docker --version 2>&1 | grep -qi podman; then
  info "Installing Docker Engine (replacing podman if present)..."

  # Remove conflicting packages — podman and buildah use the same OCI
  # runtime paths. This is safe even if they're not installed.
  sudo dnf remove -y -q docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-selinux \
    docker-engine-selinux \
    docker-engine \
    podman \
    buildah 2>/dev/null || true

  # Add the official Docker CE repo for Fedora
  sudo dnf config-manager addrepo \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
  sudo dnf config-manager --add-repo \
    https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || true

  sudo dnf install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Add current user to docker group (no sudo needed for docker commands)
if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER"
  info "Added $USER to docker group (takes effect on next login)"
fi

# Ensure Docker daemon is running
sudo systemctl enable --now docker

require docker "Docker"
success "Docker Engine + Compose plugin ready. Run 'docker run hello-world' to verify."

# --- 10. GitHub CLI (gh) + Clone Repos --------------------------------------
section "10/$TOTAL_STEPS — GitHub CLI + Clone Repos"

if ! command_exists gh; then
  info "Installing GitHub CLI via RPM repo..."
  sudo dnf config-manager addrepo \
    --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || \
  sudo dnf config-manager --add-repo \
    https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
  sudo dnf install -y -q gh
fi
require gh "GitHub CLI"
success "gh $(gh --version 2>/dev/null | head -1) ready."

if ! gh auth status &>/dev/null; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    info "Authenticating GitHub CLI via GH_TOKEN..."
    _SAVED_TOKEN="$GH_TOKEN"
    unset GH_TOKEN
    if echo "$_SAVED_TOKEN" | gh auth login --with-token 2>&1; then
      # Re-export so gh commands work for the rest of this step.
      # We'll clear it after repo cloning is done.
      export GH_TOKEN="$_SAVED_TOKEN"
    else
      warn "GH_TOKEN authentication failed (bad token? expired? wrong scopes?)."
      info "Continuing without GitHub auth — remaining tools will still install."
      info "After setup, fix with: gh auth login"
      info "Or re-run with a valid token: GH_TOKEN=ghp_xxx bash $(basename "$0")"
    fi
    unset _SAVED_TOKEN
  else
    warn "GitHub CLI is not authenticated."
    info "Run 'gh auth login' after setup to enable repo cloning."
    info "Or re-run with: GH_TOKEN=ghp_xxx bash $(basename "$0")"
  fi
fi

if gh auth status &>/dev/null; then
  success "GitHub CLI authenticated."
  gh auth setup-git

  if [[ -z "$GITHUB_USER" ]]; then
    GITHUB_USER=$(gh api user -q '.login' 2>/dev/null || true)
    [[ -n "$GITHUB_USER" ]] && info "Auto-detected GitHub user: $GITHUB_USER"
  fi

  if [[ -z "$(git config --global user.name 2>/dev/null || true)" ]]; then
    GH_NAME=$(gh api user -q '.name // empty' 2>/dev/null || true)
    if [[ -n "${GH_NAME:-}" ]]; then
      git config --global user.name "$GH_NAME"
      GIT_NAME="$GH_NAME"
      info "Auto-set git user.name from GitHub profile: $GH_NAME"
    fi
  fi

  if [[ -z "$(git config --global user.email 2>/dev/null || true)" ]]; then
    GH_EMAIL=$(gh api user/emails -q '.[] | select(.primary) | .email' 2>/dev/null || true)
    [[ -z "${GH_EMAIL:-}" ]] && GH_EMAIL=$(gh api user -q '.email // empty' 2>/dev/null || true)
    if [[ -n "${GH_EMAIL:-}" ]]; then
      git config --global user.email "$GH_EMAIL"
      GIT_EMAIL="$GH_EMAIL"
      info "Auto-set git user.email from GitHub profile: $GH_EMAIL"
    else
      warn "Could not detect email from GitHub. Set manually: git config --global user.email you@example.com"
    fi
  fi
else
  warn "GitHub auth skipped — repo cloning will only work for public repos."
fi

# --- Clone repos (while auth is fresh) ---
info "Cloning repos while GitHub auth is active..."

mkdir -p "$REPOS_DIR"

if ! grep -q "github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
  mkdir -p "$HOME/.ssh"
  ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
fi

if gh auth status &>/dev/null; then
  info "Fetching repo list for $GITHUB_USER..."

  REPO_LIST=$(gh repo list "$GITHUB_USER" --limit 200 --json name,isPrivate \
    --jq '.[] | "\(.name)\t\(.isPrivate)"' 2>/dev/null) || true

  if [[ -z "${REPO_LIST:-}" ]]; then
    warn "No repos found for $GITHUB_USER (or API rate limited)."
  else
    CLONE_COUNT=0
    SKIP_COUNT=0
    FAIL_COUNT=0

    while IFS=$'\t' read -r REPO_NAME IS_PRIVATE; do
      DEST="$REPOS_DIR/$REPO_NAME"

      if [[ -d "$DEST" ]]; then
        skip "$REPO_NAME (already cloned)"
        ((SKIP_COUNT++)) || true
      else
        PRIVATE_TAG=""
        [[ "$IS_PRIVATE" == "true" ]] && PRIVATE_TAG=" 🔒"

        HTTPS_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
        if git clone --quiet "$HTTPS_URL" "$DEST" 2>/dev/null; then
          success "$REPO_NAME${PRIVATE_TAG}"
          ((CLONE_COUNT++)) || true
        else
          warn "Failed to clone $REPO_NAME"
          ((FAIL_COUNT++)) || true
        fi
      fi
    done <<< "$REPO_LIST"

    echo ""
    info "Repos ($GITHUB_USER): $CLONE_COUNT cloned, $SKIP_COUNT already present, $FAIL_COUNT failed"

    # --- Clone org repos (if GITHUB_ORG is set) ---
    if [[ -n "${GITHUB_ORG:-}" ]] && [[ "$GITHUB_ORG" != "$GITHUB_USER" ]]; then
      echo ""
      info "Fetching repo list for org: $GITHUB_ORG..."

      ORG_REPO_LIST=$(gh repo list "$GITHUB_ORG" --limit 200 --json name,isPrivate \
        --jq '.[] | "\(.name)\t\(.isPrivate)"' 2>/dev/null) || true

      if [[ -z "${ORG_REPO_LIST:-}" ]]; then
        warn "No repos found for $GITHUB_ORG (or no access / API rate limited)."
      else
        ORG_CLONE_COUNT=0
        ORG_SKIP_COUNT=0
        ORG_FAIL_COUNT=0

        while IFS=$'\t' read -r REPO_NAME IS_PRIVATE; do
          DEST="$REPOS_DIR/$REPO_NAME"

          if [[ -d "$DEST" ]]; then
            skip "$REPO_NAME (already cloned)"
            ((ORG_SKIP_COUNT++)) || true
          else
            PRIVATE_TAG=""
            [[ "$IS_PRIVATE" == "true" ]] && PRIVATE_TAG=" 🔒"

            HTTPS_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"
            if git clone --quiet "$HTTPS_URL" "$DEST" 2>/dev/null; then
              success "$REPO_NAME${PRIVATE_TAG} (${GITHUB_ORG})"
              ((ORG_CLONE_COUNT++)) || true
            else
              warn "Failed to clone $GITHUB_ORG/$REPO_NAME"
              ((ORG_FAIL_COUNT++)) || true
            fi
          fi
        done <<< "$ORG_REPO_LIST"

        echo ""
        info "Org repos ($GITHUB_ORG): $ORG_CLONE_COUNT cloned, $ORG_SKIP_COUNT already present, $ORG_FAIL_COUNT failed"
      fi
    fi
  fi
  _REPOS_CLONED=1
else
  warn "GitHub CLI not authenticated — skipping repo cloning."
  info "Authenticate later with 'gh auth login', then run:"
  info "  cd ~/repos && gh repo list $GITHUB_USER --limit 200 --json name -q '.[].name' | xargs -I{} gh repo clone $GITHUB_USER/{}"
fi

# Cloning is done — clear GH_TOKEN so it doesn't interfere with npm,
# VS Code, or other tools that respect GitHub tokens in the environment.
unset GH_TOKEN 2>/dev/null || true

# --- 11. VS Code -------------------------------------------------------------
section "11/$TOTAL_STEPS — VS Code"

if ! command_exists code; then
  info "Installing VS Code via Microsoft RPM repo..."
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  cat << 'VSCODE_REPO' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_REPO
  sudo dnf install -y -q code
fi
require code "VS Code"
success "VS Code $(code --version 2>/dev/null | head -1 || echo 'installed') ready."

VSCODE_EXTENSIONS=(
  # --- Infrastructure & DevOps ---
  hashicorp.terraform
  hashicorp.hcl
  ms-azuretools.vscode-docker
  amazonwebservices.aws-toolkit-vscode

  # --- Languages ---
  ms-python.python
  golang.go

  # --- AI ---
  anthropic.claude-code

  # --- Quality & Collaboration ---
  redhat.vscode-yaml
  eamodio.gitlens
  timonwong.shellcheck

  # --- Remote ---
  ms-vscode-remote.remote-ssh
)

info "Installing VS Code extensions..."
INSTALLED_EXT=$(code --list-extensions 2>/dev/null || true)
for ext in "${VSCODE_EXTENSIONS[@]}"; do
  ext_id="${ext%%#*}"
  ext_id="${ext_id// /}"
  if echo "$INSTALLED_EXT" | grep -qi "$ext_id"; then
    skip "$ext_id (already installed)"
  else
    code --install-extension "$ext_id" --force 2>/dev/null && \
      success "$ext_id" || warn "Failed to install $ext_id"
  fi
done

VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"

if [[ ! -f "$VSCODE_SETTINGS" ]]; then
  info "Writing VS Code settings..."
  mkdir -p "$VSCODE_SETTINGS_DIR"
  cat > "$VSCODE_SETTINGS" << 'VSCODE_JSON'
{
  // --- Editor behavior ---
  "editor.fontSize": 15,
  "editor.fontFamily": "'Hack', 'Noto Sans Mono', 'monospace', monospace",
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.formatOnSave": true,
  "editor.trimAutoWhitespace": true,
  "editor.renderWhitespace": "trailing",
  "editor.suggestSelection": "first",
  "editor.linkedEditing": true,
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",

  // --- Files ---
  "files.autoSave": "onFocusChange",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,

  // --- Theme ---
  "workbench.colorTheme": "Default Dark Modern",

  // --- Terminal ---
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.fontSize": 14,

  // --- Git ---
  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true,

  // --- Terraform ---
  "terraform.experimentalFeatures.validateOnSave": true,
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.tabSize": 2
  },
  "[terraform-vars]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.tabSize": 2
  },

  // --- YAML ---
  "[yaml]": {
    "editor.tabSize": 2,
    "editor.autoIndent": "keep"
  },

  // --- JSON ---
  "[json]": {
    "editor.tabSize": 2,
    "editor.defaultFormatter": "vscode.json-language-features"
  },
  "[jsonc]": {
    "editor.tabSize": 2,
    "editor.defaultFormatter": "vscode.json-language-features"
  },

  // --- Markdown ---
  "[markdown]": {
    "editor.wordWrap": "on"
  },

  // --- Docker ---
  "[dockerfile]": {
    "editor.tabSize": 4
  },

  // --- Misc ---
  "telemetry.telemetryLevel": "off",
  "update.mode": "default",
  "extensions.autoUpdate": true
}
VSCODE_JSON
  success "VS Code settings written."
else
  skip "VS Code settings already exist (not overwriting)."
fi

# --- 12. Claude Code --------------------------------------------------------
# Native binary installer (Anthropic's canonical install path as of Oct 2025).
# The npm package now also ships a native binary rather than a Node entry —
# but the standalone installer at ~/.local/bin/claude avoids the per-nvm-
# version global package isolation that creates dangling references when
# nvm switches versions or when claude self-updates.
# Auto-update is enabled by default; set DISABLE_AUTOUPDATER=1 in the env
# at install time to disable.
section "12/$TOTAL_STEPS — Claude Code"

if ! command_exists claude || ! claude --version &>/dev/null; then
  info "Installing Claude Code (native binary)..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

if command_exists claude; then
  success "Claude Code installed at $(which claude). Run 'claude' to authenticate."
else
  warn "Claude Code install failed. Try manually: curl -fsSL https://claude.ai/install.sh | bash"
fi

# --- 13. Quality-of-life CLI tools ------------------------------------------
section "13/$TOTAL_STEPS — Quality-of-Life CLI Tools"

# Fedora packages — cleaner names than Debian (bat not batcat, fd-find not fdfind)
QOL_PKGS=(jq tree tmux ShellCheck direnv pipx bat ripgrep fd-find)
sudo dnf install -y -q "${QOL_PKGS[@]}"

# tldr — simplified, community-maintained man pages
if ! command_exists tldr; then
  info "Installing tldr..."
  pip install --break-system-packages --quiet tldr 2>/dev/null || \
    pipx install tldr 2>/dev/null || true
fi

# fzf — Fedora's repo version is often recent enough, but the git install
# gives us keybindings and completion scripts that the RPM doesn't wire up.
if ! command_exists fzf; then
  info "Installing fzf..."
  [[ -d "$HOME/.fzf" ]] && rm -rf "$HOME/.fzf"
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-zsh --no-fish < /dev/null
fi

# yq (YAML processor — the Go-based one by Mike Farah)
if ! command_exists yq; then
  info "Installing yq..."
  YQ_VERSION=$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | \
    python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])') || true
  if [[ -n "${YQ_VERSION:-}" ]]; then
    sudo wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
      -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
  else
    warn "Could not fetch yq version. Skipping."
  fi
fi

# Starship: install to /usr/local/bin. Unlike Crostini, sudo works normally
# on a full Fedora install.
if ! command_exists starship; then
  info "Installing Starship prompt..."
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y 2>&1 | \
    grep -E "^(>|✓|Starship)" || true
fi

# Report what we got
INSTALLED_QOL=""
for tool in jq yq tree tmux shellcheck direnv fzf rg pipx tldr starship bat fd; do
  command_exists "$tool" && INSTALLED_QOL="$INSTALLED_QOL $tool"
done

success "CLI tools:${INSTALLED_QOL}"

# --- 14. Shell configuration ------------------------------------------------
section "14/$TOTAL_STEPS — Shell Configuration"

BASHRC="$HOME/.bashrc"
MARKER="# >>> setup-fedora-workstation >>>"

# Remove old block if re-running (check for markers from all three scripts)
for marker_check in "# >>> setup-crostini-lab >>>" "# >>> setup-xubuntu-workstation >>>" "$MARKER"; do
  if grep -q "$marker_check" "$BASHRC" 2>/dev/null; then
    info "Removing previous config block from .bashrc..."
    end_check="${marker_check/>>>/<<<}"
    sed -i "/${marker_check//\//\\/}/,/${end_check//\//\\/}/d" "$BASHRC"
  fi
done

info "Appending config to .bashrc..."
cat >> "$BASHRC" << 'BASHRC_BLOCK'
# >>> setup-fedora-workstation >>>

# --- PATH ---
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

# --- Workstation config ---
WS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/workstation-bootstrap/config"
[[ -f "$WS_CONFIG" ]] && . "$WS_CONFIG"

# --- nvm ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# --- fzf ---
[ -f "$HOME/.fzf.bash" ] && . "$HOME/.fzf.bash"

# --- direnv ---
command -v direnv &>/dev/null && eval "$(direnv hook bash)"

# --- Starship prompt ---
command -v starship &>/dev/null && eval "$(starship init bash)"

# --- Granted (AWS account switching) ---
alias assume="source assume"

# --- Aliases: navigation ---
alias ll='ls -alFh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias repos='cd ~/repos'

# --- Aliases: docker ---
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlog='docker logs -f'

# --- Aliases: kubernetes ---
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'

# --- Aliases: terraform ---
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfs='tfswitch'

# --- Aliases: git ---
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gp='git push'
alias gl='git lg'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gwip='git wip'

# --- Aliases: GitHub org ---
if [[ -n "${GITHUB_DEFAULT_OWNER:-}" ]]; then
  alias ghnew='gh repo create --owner "$GITHUB_DEFAULT_OWNER"'
  alias ghclone='gh repo clone "$GITHUB_DEFAULT_OWNER"/'
fi

# --- Aliases: safety nets ---
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# --- Aliases: Fedora-specific ---
alias dnfu='sudo dnf upgrade --refresh'
alias dnfi='sudo dnf install'
alias dnfs='dnf search'

# --- AWS defaults (uncomment as needed) ---
# export AWS_PROFILE=default
# export AWS_DEFAULT_REGION=us-east-1

# --- Functions ---

# mkdir + cd in one shot
mkcd() { mkdir -p "$1" && cd "$1"; }

# Quick Python venv setup
venv() {
  local name="${1:-.venv}"
  if [[ ! -d "$name" ]]; then
    python3 -m venv "$name"
    echo "Created venv: $name"
  fi
  # shellcheck disable=SC1091
  source "$name/bin/activate"
  echo "Activated: $name"
}

# Quick look at what's in your repos dir
projects() {
  echo ""
  echo "📂 ~/repos:"
  for dir in ~/repos/*/; do
    [[ -d "$dir/.git" ]] || continue
    local name branch dirty
    name=$(basename "$dir")
    branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "—")
    dirty=""
    [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]] && dirty=" *"
    printf "  %-30s (%s)%s\n" "$name" "$branch" "$dirty"
  done
  echo ""
}

# pull-all and clean-all live in scripts/ and are symlinked into
# ~/.local/bin by bootstrap/install-scripts.sh.

# <<< setup-fedora-workstation <<<
BASHRC_BLOCK

success ".bashrc configured."

# Starship config
mkdir -p "$HOME/.config"
cat > "$HOME/.config/starship.toml" << 'STARSHIP_CONF'
# ============================================================================
# Starship prompt — setup-fedora-workstation
# Full absolute path always visible. Context modules (aws, k8s, terraform,
# etc.) only appear when active. Context on line 1, path + cursor on line 2.
# ============================================================================

scan_timeout = 100
add_newline = false

format = """
($git_branch\
$git_status\
$python\
$nodejs\
$golang\
$terraform\
$aws\
$kubernetes\
$docker_context\
$cmd_duration
)${custom.os}$hostname$directory\
$character"""

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
truncation_length = 0
truncate_to_repo = false
format = "[$path]($style) "
style = "bold cyan"

[git_branch]
symbol = " "
format = "[$symbol$branch(:$remote_branch)]($style) "
style = "bold purple"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"

[python]
format = '[${symbol}${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'
symbol = "🐍 "
style = "yellow"

[nodejs]
format = "[$symbol($version )]($style)"
symbol = "⬡ "
style = "bold green"

[golang]
format = "[$symbol($version )]($style)"
symbol = "🐹 "
style = "bold cyan"

[terraform]
format = "[$symbol$workspace]($style) "
symbol = "💠 "
style = "bold 105"

[aws]
format = '[$symbol($profile )(\($region\) )]($style)'
symbol = "☁️  "
style = "bold 208"

[kubernetes]
disabled = false
format = '[$symbol$context( \($namespace\))]($style) '
symbol = "⎈ "
style = "bold blue"

[docker_context]
format = "[$symbol$context]($style) "
symbol = "🐳 "
style = "blue"
only_with_files = true

# --- OS: distro + version from /etc/os-release ------------------------------
[custom.os]
command = '. /etc/os-release 2>/dev/null && echo "${ID} ${VERSION_ID}"'
when = "true"
format = "[$output]($style) "
style = "bold dimmed green"

[cmd_duration]
min_time = 3_000
format = "took [$duration](bold yellow) "
show_milliseconds = false

[package]
disabled = true

[username]
disabled = true

[hostname]
disabled = false
ssh_only = false
format = "[$hostname](bold dimmed green):"
STARSHIP_CONF
success "Starship config written."

# --- 15. XRDP Configuration -------------------------------------------------
# XRDP for remote desktop access from the Chromebook via Microsoft Remote
# Desktop. Configured for KDE Plasma X11 session — XRDP does not support
# Wayland, so we force the X11 session regardless of SDDM's default.
section "15/$TOTAL_STEPS — XRDP Remote Desktop (KDE Plasma)"

if ! command_exists xrdp; then
  info "Installing XRDP..."
  sudo dnf install -y -q xrdp xorgxrdp
fi

# Fedora 43+ ships KDE as Wayland-only. The plasma-workspace-x11 package
# provides the X11 session backend that startplasma-x11 needs. Without it,
# Xvnc starts, finds no session to launch, and exits immediately — producing
# the cryptic "VNC server closed connection" error in the xrdp log.
if ! rpm -q plasma-workspace-x11 &>/dev/null; then
  info "Installing plasma-workspace-x11 (required for XRDP X11 sessions)..."
  sudo dnf install -y -q plasma-workspace-x11
fi

# SELinux: allow xrdp to connect and bind.
# Fedora enforces SELinux by default. Without this, xrdp silently fails to
# start or drops connections with "cannot read private key" even when file
# permissions are correct. The actual issue is SELinux denying the access.
if command_exists setsebool; then
  info "Configuring SELinux for XRDP..."
  # Allow xrdp to connect to the X server and bind to its port
  sudo setsebool -P xrdp_connect_all_unreserved_ports on 2>/dev/null || true

  # If the above fails or isn't sufficient, allow xrdp full network access.
  # This is broader than ideal but prevents the "works on Ubuntu, fails on
  # Fedora" surprise that catches everyone.
  if command_exists semanage; then
    sudo semanage port -a -t xrdp_port_t -p tcp 3389 2>/dev/null || true
  fi

  # Generate a local policy module if audit2allow is available and there are
  # existing denials. This is the "catch whatever we missed" safety net.
  if command_exists audit2allow; then
    XRDP_DENIALS=$(sudo ausearch -m avc -ts recent < /dev/null 2>/dev/null | grep xrdp 2>/dev/null || true)
    if [[ -n "$XRDP_DENIALS" ]]; then
      info "Generating SELinux policy for existing xrdp denials..."
      echo "$XRDP_DENIALS" | sudo audit2allow -M xrdp-local 2>/dev/null && \
        sudo semodule -i xrdp-local.pp 2>/dev/null || true
      rm -f xrdp-local.te xrdp-local.pp xrdp-local.mod 2>/dev/null || true
    fi
  fi
fi

# TLS key permissions — same issue as the Xubuntu version.
# xrdp needs to read the TLS private key. On Fedora the snakeoil cert
# paths differ, but xrdp generates its own key pair at /etc/xrdp/.
# Ensure the xrdp user can read them.
if id xrdp &>/dev/null; then
  sudo chown root:xrdp /etc/xrdp/key.pem 2>/dev/null || true
  sudo chmod 640 /etc/xrdp/key.pem 2>/dev/null || true
fi

# Configure startwm.sh to launch KDE Plasma X11 session.
# CRITICAL: XRDP does not support Wayland. Fedora KDE defaults to Wayland
# via SDDM, but XRDP bypasses SDDM entirely and runs startwm.sh directly.
# We must launch the X11 session explicitly with startplasma-x11.
sudo tee /etc/xrdp/startwm.sh > /dev/null << 'STARTWM'
#!/bin/sh
if test -r /etc/profile; then
    . /etc/profile
fi

# Unset inherited D-Bus and runtime dir to prevent session collisions.
# Same fix as the XFCE version — if a local KDE session is running, the
# RDP session would try to attach to its D-Bus and fail.
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

# Force X11 session type. XRDP cannot render Wayland.
export XDG_SESSION_TYPE=x11

# Force software rendering for KWin. On a headless Xvnc display with no GPU,
# kwin_x11 tries OpenGL compositing, fails to initialize a GL context, and
# hangs until systemd's start timeout kills it — producing a black screen
# with plasmashell running but no window manager. These variables force
# XRender compositing and software GL so kwin actually starts.
# Discovered on Fedora 43 KDE (2026-04-01).
export KWIN_COMPOSE=O2
export LIBGL_ALWAYS_SOFTWARE=1
export KWIN_OPENGL_INTERFACE=egl
export QT_XCB_GL_INTEGRATION=none

exec startplasma-x11
STARTWM
sudo chmod +x /etc/xrdp/startwm.sh

# Disable KWin compositor for XRDP sessions.
# Same problem as XFCE's xfwm4 compositor: KWin enables OpenGL compositing
# by default, falls back to llvmpipe (software GL) on a VM with no GPU,
# and either crashes or produces a black screen at high resolutions.
#
# We disable compositing globally via kwinrc. If the user logs in locally
# (at the console with a real GPU), they can re-enable it.
mkdir -p "$HOME/.config"
if [[ -f "$HOME/.config/kwinrc" ]]; then
  # Modify existing kwinrc
  if grep -q "^\[Compositing\]" "$HOME/.config/kwinrc"; then
    sed -i '/^\[Compositing\]/,/^\[/{s/^Enabled=.*/Enabled=false/}' "$HOME/.config/kwinrc"
    # If Enabled key doesn't exist in the section, add it
    if ! sed -n '/^\[Compositing\]/,/^\[/p' "$HOME/.config/kwinrc" | grep -q "^Enabled="; then
      sed -i '/^\[Compositing\]/a Enabled=false' "$HOME/.config/kwinrc"
    fi
  else
    # Section doesn't exist, append it
    echo -e "\n[Compositing]\nEnabled=false" >> "$HOME/.config/kwinrc"
  fi
else
  # Create new kwinrc
  cat > "$HOME/.config/kwinrc" << 'KWINRC'
[Compositing]
Enabled=false
KWINRC
fi

# Suppress polkit authentication popups over RDP.
# Fedora uses JavaScript-based polkit rules, not the deprecated .pkla format
# that Ubuntu/Debian still supports. Same functional goal: prevent the
# "color management device" auth popup that fires on every RDP login.
sudo mkdir -p /etc/polkit-1/rules.d
sudo tee /etc/polkit-1/rules.d/45-allow-colord.rules > /dev/null << 'POLKIT_JS'
// Allow color management for all users — suppresses the authentication
// popup that appears on every XRDP login when colord tries to create
// a color profile for the virtual display.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.color-manager.create-device" ||
         action.id == "org.freedesktop.color-manager.create-profile" ||
         action.id == "org.freedesktop.color-manager.delete-device" ||
         action.id == "org.freedesktop.color-manager.delete-profile" ||
         action.id == "org.freedesktop.color-manager.modify-device" ||
         action.id == "org.freedesktop.color-manager.modify-profile") &&
        subject.isInGroup("users")) {
        return polkit.Result.YES;
    }
});
POLKIT_JS

# Open firewall port for XRDP if firewalld is running
if command_exists firewall-cmd && sudo firewall-cmd --state &>/dev/null; then
  info "Opening firewall port 3389 for XRDP..."
  sudo firewall-cmd --permanent --add-port=3389/tcp
  sudo firewall-cmd --reload
fi

sudo systemctl enable --now xrdp
success "XRDP configured — connect via Microsoft Remote Desktop at $(hostname -I | awk '{print $1}'):3389"
info "Session type: KDE Plasma X11 (Wayland is not supported over XRDP)"
info "Recommended: set RDP client resolution to 1920x1080 (4K causes rendering issues with software GL)"

# --- 16. Install scripts into ~/.local/bin ----------------------------------
section "16/$TOTAL_STEPS — Installing Scripts into ~/.local/bin"
WB_REPO="$REPOS_DIR/workstation-bootstrap"
if [[ -d "$WB_REPO" ]]; then
  # Pull latest so re-runs pick up updated install-scripts.sh (e.g. after a fix)
  git -C "$WB_REPO" pull --ff-only --quiet 2>/dev/null || true
  bash "$WB_REPO/bootstrap/install-scripts.sh"
  success "Scripts installed."
else
  warn "workstation-bootstrap not found at $WB_REPO — skipping script installation"
fi

# --- Claude Code cost export (local-session cost → homelab Grafana) ---------
# Idempotent installer for the systemd --user timer + SessionEnd hook that ship
# finished interactive-session cost to the "Claude Runner Fleet" dashboard.
# node + jq + the cloned repo are all present by now. Non-fatal on any failure.
if [[ -x "$WB_REPO/claude-cost-export/install.sh" ]]; then
  section "Claude Code cost export"
  "$WB_REPO/claude-cost-export/install.sh" || warn "cost-export install failed (non-fatal — re-run later)"
fi

# --- Captured local dotfiles (alacritty, etc.) -----------------------------
# Deploy hand-tuned configs tracked in dotfiles/ onto this machine. Idempotent;
# backs up any differing existing file to ~/.dotfiles-backup/ before overwrite.
# The repo clone above provides install.sh; non-fatal if it's an older clone.
if [[ -x "$WB_REPO/dotfiles/install.sh" ]]; then
  section "Local config files (dotfiles)"
  "$WB_REPO/dotfiles/install.sh" || warn "dotfiles install failed (non-fatal — re-run later)"
fi

# ============================================================================
section "🎉 Setup Complete!"
echo ""
echo -e "${GREEN}Everything is installed. Open a new terminal or run:${NC}"
echo ""
echo -e "  ${BOLD}source ~/.bashrc${NC}"
echo ""
echo -e "${YELLOW}Post-install checklist:${NC}"
echo "  • Log out and back in (or reboot) so docker group takes effect"
echo "  • Run 'docker run hello-world' to verify Docker"
echo "  • Run 'aws configure' (or 'aws configure sso') to set up AWS creds"
echo "  • Run 'assume <profile>' to switch AWS accounts via Granted"
echo "  • Run 'claude' to authenticate Claude Code"
echo "  • Run 'projects' to see your cloned repos at a glance"
echo "  • Run 'pull-all' to checkout default + git pull every repo in ~/repos/"
echo "  • Run 'clean-all' to delete non-default local branches + pull every repo"
echo "  • Take a Proxmox snapshot of this VM (your known-good baseline)"
echo "  • See ~/.local/bin/gh-issue to try the new issue-drafting tool"
echo ""
echo -e "${BLUE}Installed tools summary:${NC}"
echo "  Languages:    Python 3, Node.js (nvm), Go, Bash"
echo "  Cloud/Ops:    AWS CLI v2, Granted, Terraform, tfswitch, kubectl, eksctl, Helm"
echo "  Containers:   Docker Engine + Compose"
echo "  Dev tools:    git, gh, VS Code, Claude Code, jq, yq, ripgrep, fzf, bat, tmux"
echo "  Shell:        Starship prompt, direnv, shellcheck"
echo "  Remote:       XRDP (port 3389), SSH (port 22)"
echo "  Desktop:      KDE Plasma (X11 session for XRDP compatibility)"
echo "  Scripts:      Custom CLI tools symlinked to ~/.local/bin/"
echo "  Config:       ~/.config/workstation-bootstrap/config (org: ${GITHUB_ORG:-<none>})"
if [[ -n "${GITHUB_ORG:-}" ]]; then
  echo "  Your code:    ~/repos/ (${GITHUB_USER:-<configure gh>} + ${GITHUB_ORG} repos)"
else
  echo "  Your code:    ~/repos/ (all ${GITHUB_USER:-<configure gh>} repos)"
fi
echo ""
SIGNOFF_NAME="${GIT_NAME:-${GITHUB_USER:-hacker}}"
SIGNOFF_FIRST=$(echo "$SIGNOFF_NAME" | awk '{print $1}')
echo -e "${BOLD}Happy hacking, ${SIGNOFF_FIRST}. 🚀${NC}"
