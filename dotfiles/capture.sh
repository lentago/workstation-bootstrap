#!/usr/bin/env bash
#
# capture.sh — refresh tracked dotfiles in this repo from the live $HOME.
#
# The inverse of install.sh. For every file already tracked under
# dotfiles/home/, copy the live version from $HOME back into the repo, so a
# local tweak (e.g. an alacritty edit) becomes a reviewable git diff.
#
# It only refreshes files the repo ALREADY tracks — it does not slurp your
# whole home directory. To start tracking a NEW config, copy it under
# dotfiles/home/ once (mirroring its $HOME-relative path), then capture.sh
# keeps it in sync from then on:
#   mkdir -p dotfiles/home/.config/foo && cp ~/.config/foo/bar.conf "$_"/
#
# Usage:
#   dotfiles/capture.sh      # then: git diff, commit, open a PR
#
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="${DOTFILES_DIR}/home"
LIVE_ROOT="${HOME}"

if [ ! -d "${SRC_ROOT}" ]; then
  echo "No tracked files under ${SRC_ROOT} — nothing to capture."
  exit 0
fi

updated=0
unchanged=0
missing=0

while IFS= read -r -d '' tracked; do
  rel="${tracked#"${SRC_ROOT}"/}"
  live="${LIVE_ROOT}/${rel}"

  if [ ! -f "${live}" ]; then
    echo "missing ${rel} (not present on this machine)"
    missing=$((missing + 1))
    continue
  fi

  if cmp -s "${live}" "${tracked}"; then
    unchanged=$((unchanged + 1))
    continue
  fi

  cp "${live}" "${tracked}"
  updated=$((updated + 1))
  echo "capture ${rel}"
done < <(find "${SRC_ROOT}" -type f -print0)

echo "done: ${updated} updated, ${unchanged} unchanged, ${missing} missing"
if [ "${updated}" -gt 0 ]; then
  echo "review with 'git diff', then commit and open a PR."
fi
