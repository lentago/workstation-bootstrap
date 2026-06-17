#!/usr/bin/env bash
#
# install.sh — deploy tracked dotfiles from this repo into $HOME.
#
# Every file under dotfiles/home/ maps to the same relative path under $HOME
# (e.g. dotfiles/home/.config/alacritty/alacritty.toml -> ~/.config/alacritty/
# alacritty.toml). This script copies each one into place.
#
# Idempotent: files already identical are skipped. An existing live file that
# differs is backed up under ~/.dotfiles-backup/ before being overwritten, so
# a deploy never silently clobbers local edits you haven't captured yet.
#
# Run after a fresh provision (or any time you want the repo's configs live):
#   dotfiles/install.sh
#
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="${DOTFILES_DIR}/home"
DEST_ROOT="${HOME}"
BACKUP_DIR="${DEST_ROOT}/.dotfiles-backup"

if [ ! -d "${SRC_ROOT}" ]; then
  echo "No tracked files under ${SRC_ROOT} — nothing to install."
  exit 0
fi

installed=0
skipped=0
backed_up=0

while IFS= read -r -d '' src; do
  rel="${src#"${SRC_ROOT}"/}"
  dest="${DEST_ROOT}/${rel}"

  if [ -f "${dest}" ] && cmp -s "${src}" "${dest}"; then
    skipped=$((skipped + 1))
    continue
  fi

  if [ -e "${dest}" ]; then
    bdest="${BACKUP_DIR}/${rel}"
    mkdir -p "$(dirname "${bdest}")"
    cp -p "${dest}" "${bdest}"
    backed_up=$((backed_up + 1))
    echo "backup  ${rel} -> ${bdest#"${DEST_ROOT}"/}"
  fi

  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
  installed=$((installed + 1))
  echo "install ${rel}"
done < <(find "${SRC_ROOT}" -type f -print0)

echo "done: ${installed} installed, ${skipped} unchanged, ${backed_up} backed up"
