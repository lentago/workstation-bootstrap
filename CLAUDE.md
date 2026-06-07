# CLAUDE.md — workstation-bootstrap

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Persona — introduce yourself

When Claude initializes in this directory, open the first response with a
brief self-introduction as **Bootstrap Claude** — provisioning specialist
for the family of `setup-*.sh` workstation/laptop bootstrap scripts. One
sentence is plenty; don't make a meal of it.

## What this repo is

Three standalone bash scripts that bootstrap a fresh Linux environment into a fully configured cloud infrastructure development workstation. Each script is self-contained (~1000+ lines) and installs the same toolchain with platform-specific adaptations.

| Script | Target | Package manager |
|---|---|---|
| `setup-crostini-lab.sh` | Chromebook Crostini (Debian) | apt-get |
| `setup-xubuntu-workstation.sh` | Xubuntu 24.04 LTS VM | apt-get |
| `setup-fedora-workstation.sh` | Fedora KDE Plasma VM | dnf |
| `setup-ubuntu-laptop.sh` | Ubuntu Desktop LTS (bare-metal laptop) | apt-get |

## There is no build/test/lint system

These are standalone bash scripts. There is no build step, no test suite, and no package manager. To validate changes, run `shellcheck <script>` or execute the script on the target platform.

## Architecture

The scripts share ~80% of their logic but are intentionally kept as independent files (not sourced from a shared library). Each follows the same sequential structure:

1. `set -euo pipefail` + global error trap
2. Config via environment variables with auto-detection fallbacks
3. Numbered steps (15-17), each idempotent — checks for existing installs before acting
4. `.bashrc` block bounded by marker comments, replaced cleanly on re-run
5. Starship prompt config written to `~/.config/starship.toml`

Key platform differences to keep in mind when editing:
- **Crostini**: CLI-only Docker (no daemon), installs to `~/.local/bin` (broken sudo), `batcat`/`fdfind` naming
- **Xubuntu**: Full Docker Engine, XRDP+XFCE, `batcat`/`fdfind` naming
- **Fedora**: Full Docker Engine (removes podman first), XRDP+KDE Plasma X11, SELinux policy, firewalld rules, JavaScript polkit rules, `bat`/`fd` clean names, Granted installed via binary (no DNF repo)
- **Ubuntu laptop**: Full Docker Engine, no XRDP, TLP replaces power-profiles-daemon, ThinkPad charge thresholds (75-80%), fwupd timer enabled, `batcat`/`fdfind` naming

## Editing guidelines

- **All four scripts must stay in sync** for shared functionality across the apt-based variants and adapted for Fedora's package manager. If you change how a tool is installed or configured in one script, apply the same change to the others (adapting for the package manager and platform).
- **Every step must be idempotent.** Always check if something is already installed before installing it. Re-running the script must be safe.
- **The `set -e` arithmetic trap**: `((count++))` returns exit code 1 when count is 0. Always use `((count++)) || true`.
- **PATH bootstrapping**: Tools installed mid-script must be findable during the script. PATH is set at the top, not deferred to `.bashrc`.
- **nvm triple-fix**: (1) `$NVM_DIR` must exist before installer, (2) source nvm after install not before, (3) `PROFILE=/dev/null` prevents duplicate `.bashrc` entries.

## CI/CD

- **Claude Code Review** (`.github/workflows/claude-code-review.yml`): Runs on every non-draft PR. Read-only review focused on bash correctness, idempotency, and security. Skips `.md` and `docs/` changes.
- **ShellCheck** (`.github/workflows/shellcheck.yml`): Runs on every non-draft PR
  that touches `.sh` files. Static analysis at `--severity=warning`. Required
  status check for branch protection.
- **Claude Code Responder** (`.github/workflows/claude.yml`): Triggered by `@claude` mentions in issues/PR comments.

## Workflow

PR workflow + auto-merge arming protocol is fleet-wide; see `~/repos/CLAUDE.md`. Repo-specific note: work on the branch created for the issue (don't spawn extra ones), and the required status checks are ShellCheck + Claude Code Review.
