#!/usr/bin/env bash
# ============================================================================
# setup-crostini-lab.sh — v4.1 (field-tested on real Chromebook hardware)
# Chromebook Crostini (Debian) bootstrap for ops/dev homelab work
#
# Author:  Chris Pitzi — PitziLabs (https://github.com/PitziLabs)
# Updated: 2026-03-26
#
# Usage:
#   Quick start (download first — recommended):
#     curl -sLO https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-crostini-lab.sh
#     GH_TOKEN=ghp_yourtoken bash setup-crostini-lab.sh
#
#   Or pipe directly (note: GH_TOKEN goes AFTER the pipe):
#     curl -sL https://raw.githubusercontent.com/PitziLabs/workstation-bootstrap/main/setup-crostini-lab.sh | GH_TOKEN=ghp_yourtoken bash
#
# Environment variables (all optional — auto-detected when possible):
#   GH_TOKEN        GitHub personal access token (scopes: repo, read:org)
#                   If set, skips interactive gh auth login entirely.
#   GIT_NAME        Git user.name (auto-detected from gh profile or prompted)
#   GIT_EMAIL       Git user.email (auto-detected from gh profile or prompted)
#   GITHUB_USER     GitHub username for repo cloning (auto-detected from gh auth)
#   REPOS_DIR       Where to clone repos (default: ~/repos)
#
# IMPORTANT: Run with 'bash', not 'sh'. Debian's sh is dash, not bash.
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
#   9.  Docker CLI + docker-compose (CLI only, no daemon)
#  10.  GitHub CLI (gh) + authenticate + clone repos
#  11.  VS Code (via Microsoft APT repo)
#  12.  Claude Code
#  13.  Quality-of-life CLI tools
#  14.  Shell config (starship prompt, aliases, PATH wiring)
#
# Field-tested bugs fixed in this version:
#   - nvm: directory must exist before installer; source AFTER install
#   - nvm: PROFILE=/dev/null to prevent duplicate .bashrc entries
#   - Granted: binary download from GitHub releases (fwdcloudsec/granted)
#   - tfswitch: installs to ~/bin; PATH must include it before check
#   - Starship: install to ~/.local/bin (Crostini sudo is broken for
#     third-party install scripts); ensure directory exists first
#   - Clone loop: ((count++)) from 0 kills set -e; use || true guard
#   - PATH: ~/.local/bin and ~/bin must be on PATH at script start,
#     not just in .bashrc (chicken-and-egg with tool detection)
# ============================================================================

set -euo pipefail

# --- Global error trap -------------------------------------------------------
# If set -e kills the script unexpectedly, tell the user what step failed
# and that re-running is safe (all steps are idempotent).
CURRENT_STEP="initializing"
trap 'echo ""; echo -e "${RED}[FATAL] Script failed during: ${CURRENT_STEP}${NC}"; echo -e "${YELLOW}Re-run is safe — completed steps will be skipped (idempotent).${NC}"' ERR

# --- Config (overridable via environment variables) -------------------------
# These are populated in three stages:
#   1. Environment variables (if set by the user)
#   2. Existing git config (if already configured on this machine)
#   3. Auto-detection from GitHub profile (after gh auth in step 10)
# Any value still empty after all three stages triggers a prompt (interactive)
# or a warning (non-interactive).
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

# GH_TOKEN is read from environment if set; used by gh CLI directly.

# Detect whether stdin is a terminal (interactive) or piped (automated)
INTERACTIVE=false
[[ -t 0 ]] && INTERACTIVE=true

# --- Bootstrap PATH early ---------------------------------------------------
# Tools installed by this script land in these directories. We need them on
# PATH *during* the script run, not just in .bashrc (which hasn't been
# written yet on first run). This is the single biggest lesson from field
# testing: install-time PATH and shell-config-time PATH must agree.
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

# Verify a command exists after install, or bail with a helpful message
require() {
  local cmd="$1"
  local friendly="${2:-$1}"
  if ! command_exists "$cmd"; then
    fail "$friendly failed to install. Check the output above for errors."
  fi
}

TOTAL_STEPS=15

# --- Preflight --------------------------------------------------------------
section "Preflight Checks"

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "This script is for Linux (Crostini/Debian). You're on $(uname -s)."
fi

if [[ -z "${BASH_VERSION:-}" ]]; then
  fail "This script requires bash. Run it with: bash $0"
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

# Harvest sudo credentials up front so the password prompt doesn't ambush
# us mid-install when the credential cache expires.
sudo -v
# Keep sudo alive in the background — prevents timeout during long installs.
(while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done) &
_SUDO_KEEPALIVE_PID=$!
trap 'kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null; exit' EXIT

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

sudo apt-get update -qq
sudo apt-get upgrade -y -qq

BASE_PKGS=(
  build-essential
  curl
  wget
  git
  unzip
  zip
  gnupg
  lsb-release
  ca-certificates
  software-properties-common
  apt-transport-https
  man-db
  less
  openssh-client
  dnsutils
  net-tools
  traceroute
  nmap
  whois
  htop
  ncdu
  nano
  nfs-common                 # NFS client for mounting network shares
)

info "Installing base packages..."
sudo apt-get install -y -qq "${BASE_PKGS[@]}"
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

sudo apt-get install -y -qq python3 python3-pip python3-venv python3-full
require python3 "Python 3"
success "Python $(python3 --version 2>&1 | awk '{print $2}') ready."

# --- 4. Node.js via nvm -----------------------------------------------------
section "4/$TOTAL_STEPS — Node.js (LTS via nvm)"

export NVM_DIR="$HOME/.nvm"

# [BUG FIX v3] Directory MUST exist before the nvm installer runs.
# The installer checks $NVM_DIR and errors if set but missing.
mkdir -p "$NVM_DIR"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  info "Installing nvm..."
  # Ensure .bashrc exists so nvm's installer doesn't complain about missing profile
  touch "$HOME/.bashrc"
  # [BUG FIX v3] PROFILE=/dev/null prevents the installer from appending
  # source lines to .bashrc. We manage our own .bashrc block in step 13.
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | \
    PROFILE=/dev/null bash
fi

# [BUG FIX v3] Source nvm AFTER the install, not before.
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
# Common Fate wound down. The releases.commonfate.io CDN and APT repo are dead.
# Download directly from GitHub releases. Granted is MIT-licensed and will keep
# working, but expect no new releases.
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

  # [BUG FIX v4] tfswitch installs terraform to ~/bin/ by default (not
  # /usr/local/bin). ~/bin is already on PATH from our early bootstrap block.
  if ! command_exists terraform; then
    info "Installing latest Terraform via tfswitch..."
    tfswitch --latest
  fi
else
  warn "tfswitch install failed. Installing Terraform via HashiCorp APT repo instead..."
  wget -qO- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq terraform
fi

if command_exists terraform; then
  success "Terraform $(terraform version -json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1) ready."
else
  warn "Terraform not installed — run 'tfswitch' after setup to install."
fi

# ┌──────────────────────────────────────────────────────────────────────┐
# │ TERRAGRUNT — uncomment when you need multi-env DRY Terraform.      │
# │ You'll know when the time comes: it's when you find yourself       │
# │ copy-pasting backend configs between staging/ and production/      │
# │ and hating yourself for it.                                        │
# └──────────────────────────────────────────────────────────────────────┘
# if ! command_exists terragrunt; then
#   info "Installing Terragrunt..."
#   TG_VERSION=$(curl -fsSL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | \
#     python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
#   sudo wget -q "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VERSION}/terragrunt_linux_amd64" \
#     -O /usr/local/bin/terragrunt
#   sudo chmod +x /usr/local/bin/terragrunt
#   success "Terragrunt ${TG_VERSION} ready."
# fi

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

# --- 9. Docker CLI (no daemon) + docker-compose ------------------------------
section "9/$TOTAL_STEPS — Docker CLI + Compose (CLI only, no daemon)"

if ! command_exists docker; then
  info "Installing Docker CLI (client only)..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce-cli docker-compose-plugin
fi
require docker "Docker CLI"
success "Docker CLI + Compose plugin ready (no daemon — point DOCKER_HOST at a remote)."

# --- 10. GitHub CLI (gh) + Clone Repos --------------------------------------
section "10/$TOTAL_STEPS — GitHub CLI + Clone Repos"

if ! command_exists gh; then
  info "Installing GitHub CLI..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh
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
  info "Installing VS Code via Microsoft APT repo..."
  # Import Microsoft's GPG key and add their APT repository.
  # This is the official method from https://code.visualstudio.com/docs/setup/linux
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
    https://packages.microsoft.com/repos/code stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt-get update -qq
  # Pre-seed debconf to avoid interactive prompt about adding Microsoft repo.
  # The package's postinst script asks this via debconf even with -y.
  # See: https://code.visualstudio.com/docs/setup/linux
  echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
  sudo apt-get install -y -qq code
fi
require code "VS Code"
success "VS Code $(code --version 2>/dev/null | head -1 || echo 'installed') ready."

# VS Code extensions — install if not already present
VSCODE_EXTENSIONS=(
  # --- Infrastructure & DevOps ---
  hashicorp.terraform            # Terraform + HCL language support
  hashicorp.hcl                  # HCL syntax highlighting
  ms-azuretools.vscode-docker    # Docker file support + compose
  amazonwebservices.aws-toolkit-vscode  # AWS explorer, CloudWatch, resources

  # --- Languages ---
  ms-python.python               # Python IntelliSense, linting, debugging
  golang.go                      # Go language support

  # --- AI ---
  anthropic.claude-code          # Claude Code in VS Code

  # --- Quality & Collaboration ---
  redhat.vscode-yaml             # YAML language support + schemas
  eamodio.gitlens                # Git blame, history, annotations
  timonwong.shellcheck           # ShellCheck linting for bash/sh scripts

  # --- Remote ---
  ms-vscode-remote.remote-ssh    # Edit files on remote hosts via SSH
)

info "Installing VS Code extensions..."
INSTALLED_EXT=$(code --list-extensions 2>/dev/null || true)
for ext in "${VSCODE_EXTENSIONS[@]}"; do
  # Strip inline comment
  ext_id="${ext%%#*}"
  ext_id="${ext_id// /}"
  if echo "$INSTALLED_EXT" | grep -qi "$ext_id"; then
    skip "$ext_id (already installed)"
  else
    code --install-extension "$ext_id" --force 2>/dev/null && \
      success "$ext_id" || warn "Failed to install $ext_id"
  fi
done

# VS Code user settings
VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"

if [[ ! -f "$VSCODE_SETTINGS" ]]; then
  info "Writing VS Code settings..."
  mkdir -p "$VSCODE_SETTINGS_DIR"
  cat > "$VSCODE_SETTINGS" << 'VSCODE_JSON'
{
  // --- Editor behavior ---
  "editor.fontSize": 15,
  "editor.fontFamily": "'Droid Sans Mono', 'monospace', monospace",
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

# APT-available tools
QOL_PKGS=(jq tree tmux shellcheck direnv pipx)
sudo apt-get install -y -qq "${QOL_PKGS[@]}"

# bat (called 'batcat' on Debian due to a name conflict)
if ! command_exists bat && ! command_exists batcat; then
  sudo apt-get install -y -qq bat 2>/dev/null || true
fi

# ripgrep
if ! command_exists rg; then
  sudo apt-get install -y -qq ripgrep 2>/dev/null || true
fi

# fd-find (called 'fdfind' on Debian due to a name conflict, like bat)
if ! command_exists fd && ! command_exists fdfind; then
  sudo apt-get install -y -qq fd-find 2>/dev/null || true
fi

# tldr — simplified, community-maintained man pages
if ! command_exists tldr; then
  info "Installing tldr..."
  pip install --break-system-packages --quiet tldr 2>/dev/null || \
    pipx install tldr 2>/dev/null || true
fi

# fzf — clone and install (apt version is often ancient)
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

# [BUG FIX v4] Starship: install to ~/.local/bin to avoid Crostini's broken
# sudo for third-party install scripts. The directory was created at the top
# of this script in the PATH bootstrap section.
if ! command_exists starship; then
  info "Installing Starship prompt..."
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" 2>&1 | \
    grep -E "^(>|✓|Starship)" || true
fi

# Report what we got
INSTALLED_QOL=""
for tool in jq yq tree tmux shellcheck direnv fzf rg pipx tldr starship; do
  command_exists "$tool" && INSTALLED_QOL="$INSTALLED_QOL $tool"
done
command_exists batcat && INSTALLED_QOL="$INSTALLED_QOL bat(cat)"
command_exists bat && INSTALLED_QOL="$INSTALLED_QOL bat"
command_exists fdfind && INSTALLED_QOL="$INSTALLED_QOL fd(find)"
command_exists fd && INSTALLED_QOL="$INSTALLED_QOL fd"

success "CLI tools:${INSTALLED_QOL}"

# --- 14. Shell configuration ------------------------------------------------
section "14/$TOTAL_STEPS — Shell Configuration"

BASHRC="$HOME/.bashrc"
MARKER="# >>> setup-crostini-lab >>>"
END_MARKER="# <<< setup-crostini-lab <<<"

# Remove old block if re-running
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
  info "Removing previous config block from .bashrc..."
  sed -i "/$MARKER/,/$END_MARKER/d" "$BASHRC"
fi

info "Appending config to .bashrc..."
cat >> "$BASHRC" << 'BASHRC_BLOCK'
# >>> setup-crostini-lab >>>

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
# Usage: assume <profile-name>
# Docs:  https://docs.commonfate.io/granted/getting-started
alias assume="source assume"

# --- Aliases: navigation ---
alias ll='ls -alFh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias repos='cd ~/repos'

# --- Aliases: bat ---
command -v batcat &>/dev/null && alias bat='batcat'

# --- Aliases: fd ---
command -v fdfind &>/dev/null && alias fd='fdfind'

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

# --- Docker (point at remote) ---
# export DOCKER_HOST=ssh://user@your-docker-host

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

# <<< setup-crostini-lab <<<
BASHRC_BLOCK

success ".bashrc configured."

# Starship config — Chris's custom prompt
# Design: full absolute path, git always visible in repos, everything else
# appears only when active. Clean and quiet until you need the context.
mkdir -p "$HOME/.config"
cat > "$HOME/.config/starship.toml" << 'STARSHIP_CONF'
# ============================================================================
# Starship prompt — setup-crostini-lab
# Full absolute path always visible. Context modules (aws, k8s, terraform,
# etc.) only appear when active. Context on line 1, path + cursor on line 2.
# ============================================================================

scan_timeout = 100
add_newline = false

# The format string controls what shows up and in what order.
# Context modules render on line 1 (only when active), then a newline,
# then hostname:path + cursor on line 2. The parens around the context
# modules collapse the entire group (and its trailing newline) when no
# variable inside it has a value, so an idle prompt is a single line.
format = """
($git_branch\
$git_status\
$python\
$nodejs\
$golang\
$terraform\
$aws\
$kubernetes\
$cmd_duration
)${custom.os}$hostname$directory\
$character"""

# --- Prompt character -------------------------------------------------------
[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

# --- Directory: full absolute path, no truncation ---------------------------
[directory]
truncation_length = 0          # 0 = never truncate
truncate_to_repo = false       # show full path even inside git repos
format = "[$path]($style) "
style = "bold cyan"

# Home directory is still shown as ~ (starship default). To see the raw
# /home/username path instead, uncomment the next line:
# fish_style_pwd_dir_length = 0

# --- Git: branch name + dirty/staged/ahead/behind indicators ---------------
[git_branch]
symbol = " "
format = "[$symbol$branch(:$remote_branch)]($style) "
style = "bold purple"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"
# Individual indicators (these are the defaults, shown here for clarity):
# conflicted = "="
# ahead = "⇡"
# behind = "⇣"
# diverged = "⇕"
# untracked = "?"
# stashed = "$"
# modified = "!"
# staged = "+"
# renamed = "»"
# deleted = "✘"

# --- Python: only shows when venv is active or .py/.python-version found ---
[python]
format = '[${symbol}${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'
symbol = "🐍 "
style = "yellow"

# --- Node: only shows when package.json or .nvmrc found --------------------
[nodejs]
format = "[$symbol($version )]($style)"
symbol = "⬡ "
style = "bold green"

# --- Go: only shows when go.mod or .go files found -------------------------
[golang]
format = "[$symbol($version )]($style)"
symbol = "🐹 "
style = "bold cyan"

# --- Terraform: only shows when .tf files found ----------------------------
[terraform]
format = "[$symbol$workspace]($style) "
symbol = "💠 "
style = "bold 105"    # purple-ish

# --- AWS: only shows when AWS_PROFILE or AWS_REGION is set -----------------
[aws]
format = '[$symbol($profile )(\($region\) )]($style)'
symbol = "☁️  "
style = "bold 208"    # orange

# --- Kubernetes: only shows when KUBECONFIG is set or ~/.kube/config exists -
[kubernetes]
disabled = false       # starship disables k8s by default; we want it
format = '[$symbol$context( \($namespace\))]($style) '
symbol = "⎈ "
style = "bold blue"

# --- OS: distro + version from /etc/os-release ------------------------------
[custom.os]
command = '. /etc/os-release 2>/dev/null && echo "${ID} ${VERSION_ID}"'
when = "true"
format = "[$output]($style) "
style = "bold dimmed green"

# --- Command duration: only shows for commands > 3 seconds -----------------
[cmd_duration]
min_time = 3_000       # milliseconds
format = "took [$duration](bold yellow) "
show_milliseconds = false

# --- Modules we explicitly DON'T want cluttering the prompt ----------------
[package]
disabled = true        # don't show npm/cargo/etc package versions

[username]
disabled = true        # we know who we are

[hostname]
disabled = false
ssh_only = false            # Always show — know which box you're on
format = "[$hostname](bold dimmed green):"
STARSHIP_CONF
success "Starship config written."

# --- 15. Install scripts into ~/.local/bin ----------------------------------
section "15/$TOTAL_STEPS — Installing Scripts into ~/.local/bin"
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
# (Crostini's systemd --user may be unavailable — the installer degrades safely.)
if [[ -x "$WB_REPO/claude-cost-export/install.sh" ]]; then
  section "Claude Code cost export"
  "$WB_REPO/claude-cost-export/install.sh" || warn "cost-export install failed (non-fatal — re-run later)"
fi

# ============================================================================
section "🎉 Setup Complete!"
echo ""
echo -e "${GREEN}Everything is installed. Open a new terminal or run:${NC}"
echo ""
echo -e "  ${BOLD}source ~/.bashrc${NC}"
echo ""
echo -e "${YELLOW}Post-install checklist:${NC}"
echo "  • Run 'aws configure' (or 'aws configure sso') to set up AWS creds"
echo "  • Run 'assume <profile>' to switch AWS accounts via Granted"
echo "  • Set DOCKER_HOST in ~/.bashrc if using a remote Docker daemon"
echo "  • Run 'claude' to authenticate Claude Code"
echo "  • Run 'projects' to see your cloned repos at a glance"
echo "  • Run 'pull-all' to checkout default + git pull every repo in ~/repos/"
echo "  • Run 'clean-all' to delete non-default local branches + pull every repo"
echo ""
echo -e "${BLUE}Installed tools summary:${NC}"
echo "  Languages:    Python 3, Node.js (nvm), Go, Bash"
echo "  Cloud/Ops:    AWS CLI v2, Granted, Terraform, tfswitch, kubectl, eksctl, Helm"
echo "  Containers:   Docker CLI + Compose (no daemon)"
echo "  Dev tools:    git, gh, VS Code, Claude Code, jq, yq, ripgrep, fzf, bat, tmux"
echo "  Shell:        Starship prompt, direnv, shellcheck"
echo "  Scripts:      Custom CLI tools symlinked to ~/.local/bin/"
echo "  Config:       ~/.config/workstation-bootstrap/config (org: ${GITHUB_ORG:-<none>})"
if [[ -n "${GITHUB_ORG:-}" ]]; then
  echo "  Your code:    ~/repos/ (${GITHUB_USER:-<configure gh>} + ${GITHUB_ORG} repos)"
else
  echo "  Your code:    ~/repos/ (all ${GITHUB_USER:-<configure gh>} repos)"
fi
echo ""
# Build a personalized sign-off using whatever name info we have
SIGNOFF_NAME="${GIT_NAME:-${GITHUB_USER:-hacker}}"
# Use just the first name if we have a full name
SIGNOFF_FIRST=$(echo "$SIGNOFF_NAME" | awk '{print $1}')
echo -e "${BOLD}Happy hacking, ${SIGNOFF_FIRST}. 🚀${NC}"
