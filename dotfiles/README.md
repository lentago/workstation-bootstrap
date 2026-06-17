# dotfiles — captured local configs

Version-controlled copies of hand-tuned local config files, so they survive a
machine rebuild and so a local tweak becomes a reviewable diff instead of a
one-off edit that's lost on the next reinstall.

This complements — it doesn't replace — the configs the `setup-*.sh` scripts
generate inline (e.g. `~/.config/starship.toml`). Those are *generated* and
belong in the scripts. This directory is for configs that are too large or too
hand-iterated to live as a heredoc (the alacritty config is the seed: ~7.5KB
across three theme variants).

## Layout

Everything under `home/` mirrors its path relative to `$HOME`:

```
dotfiles/home/.config/alacritty/alacritty.toml   ->   ~/.config/alacritty/alacritty.toml
```

The set of files under `home/` *is* the set of tracked configs. There's no
manifest to keep in sync — the directory tree is the manifest.

## Workflow

Two idempotent helpers, inverses of each other:

| Script | Direction | When |
|---|---|---|
| `install.sh` | repo → `$HOME` | After a fresh provision, or to make the repo's configs live |
| `capture.sh` | `$HOME` → repo | After tweaking a config locally, to snapshot it back into git |

```bash
# Deploy tracked configs onto a freshly set-up machine.
# Backs up any differing existing file to ~/.dotfiles-backup/ first.
dotfiles/install.sh

# Pull your latest local edits back into the repo, then PR them.
dotfiles/capture.sh
git -C ~/repos/workstation-bootstrap diff
```

Both skip files that are already identical, so re-running is safe and quiet.

## Adding a new config to track

Copy it under `home/`, mirroring its `$HOME`-relative path, then commit:

```bash
mkdir -p dotfiles/home/.config/foo
cp ~/.config/foo/bar.conf dotfiles/home/.config/foo/bar.conf
```

From then on `capture.sh` keeps it fresh and `install.sh` deploys it.

## Why copy, not symlink

`install.sh` copies rather than symlinking so live files stay real files.
That preserves in-place swapping — e.g. alacritty's
`cp alacritty-aurora.toml alacritty.toml` to change the active theme would
clobber a symlink. The cost is that local edits don't flow back automatically;
that's what `capture.sh` is for.

## Not yet wired into `setup-*.sh`

The provisioning scripts don't call `install.sh` yet — for now it's a manual
post-provision step. Wiring it in (across all four scripts, per the repo's
keep-in-sync rule) is a sensible follow-up.

## What's tracked today

- **`.config/alacritty/`** — `alacritty.toml` (active) plus the `ember` and
  `aurora` theme variants. All three pin `working_directory` so new windows
  open in `$HOME` instead of inheriting the spawning window's cwd.
