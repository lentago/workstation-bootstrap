#!/usr/bin/env bash
# install.sh — set up Claude Code local-session cost export on this workstation.
# Idempotent: safe to re-run (re-syncs assets, won't duplicate the hook).
#
# Installs:
#   ~/.claude/cost-export/{cost-export.mjs,pricing.json,cost-hook.sh}  (assets + state)
#   ~/.config/systemd/user/claude-cost-export.{service,timer}          (5-min sweep+ship)
#   a SessionEnd hook in ~/.claude/settings.json                       (prompt finalize)
#
# Run standalone:  claude-cost-export/install.sh
# Called by the workstation-bootstrap setup-*.sh scripts after repos are cloned.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
INSTALL_DIR="$HOME/.claude/cost-export"
UNIT_DIR="$HOME/.config/systemd/user"
SETTINGS="$HOME/.claude/settings.json"

c_ok()   { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[0;34m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
c_fail() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

# --- 1. Prerequisites ------------------------------------------------------
NODE_BIN="$(command -v node || true)"
[ -z "$NODE_BIN" ] && c_fail "node not found on PATH — install Node (the bootstrap installs it via nvm) before running this."
command -v jq >/dev/null 2>&1 || c_fail "jq not found — install jq first (it's in the bootstrap's QoL tools)."
command -v curl >/dev/null 2>&1 || c_fail "curl not found."
c_info "node: $NODE_BIN  ($($NODE_BIN --version))"

# --- 2. Copy assets --------------------------------------------------------
mkdir -p "$INSTALL_DIR/done"
install -m 0755 "$SRC_DIR/cost-export.mjs" "$INSTALL_DIR/cost-export.mjs"
install -m 0755 "$SRC_DIR/cost-hook.sh"    "$INSTALL_DIR/cost-hook.sh"
# pricing.json: install fresh on first run; on re-run keep the local copy if the
# operator has hand-edited it (compare against the shipped one and warn on drift).
if [ ! -f "$INSTALL_DIR/pricing.json" ]; then
  install -m 0644 "$SRC_DIR/pricing.json" "$INSTALL_DIR/pricing.json"
  c_ok "installed pricing.json"
elif ! cmp -s "$SRC_DIR/pricing.json" "$INSTALL_DIR/pricing.json"; then
  c_warn "pricing.json differs from the repo copy — leaving your local version. Diff: diff $INSTALL_DIR/pricing.json $SRC_DIR/pricing.json"
fi
c_ok "assets installed to $INSTALL_DIR"

# --- 3. systemd --user units (substitute node + install paths) -------------
# Render + load the units now, but DON'T start the timer yet — the guard must be
# seeded first (step 5), or the timer's catch-up run would ship the whole backlog.
mkdir -p "$UNIT_DIR"
sed -e "s#__NODE_BIN__#$NODE_BIN#g" -e "s#__INSTALL_DIR__#$INSTALL_DIR#g" \
  "$SRC_DIR/claude-cost-export.service" > "$UNIT_DIR/claude-cost-export.service"
install -m 0644 "$SRC_DIR/claude-cost-export.timer" "$UNIT_DIR/claude-cost-export.timer"
systemctl --user daemon-reload
c_ok "units installed (timer not started yet)"

# --- 4. SessionEnd hook in settings.json (idempotent merge) ----------------
HOOK_CMD="$INSTALL_DIR/cost-hook.sh"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 || c_fail "$SETTINGS is not valid JSON — refusing to touch it."
exists="$(jq -r --arg c "$HOOK_CMD" \
  '[(.hooks.SessionEnd // [])[].hooks[]?.command] | index($c) != null' "$SETTINGS" 2>/dev/null || echo false)"
if [ "$exists" != "true" ]; then
  cp -p "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"   # backup before edit
  tmp="$(mktemp)"
  jq --arg c "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.SessionEnd //= [] |
    .hooks.SessionEnd += [ { "hooks": [ { "type": "command", "command": $c } ] } ]
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  c_ok "added SessionEnd hook to $SETTINGS (backup saved)"
else
  c_ok "SessionEnd hook already present"
fi

# --- 5. SEED the guard BEFORE starting the timer ---------------------------
# Claim all currently-finished sessions as already-emitted so only sessions that
# complete AFTER install ship — no backfill spike, no bulk-ship race. Must run
# before the timer is enabled. Deliberate history backfill is an explicit opt-in
# (see the hint below).
if [ ! -f "$INSTALL_DIR/emitted.json" ]; then
  c_info "seeding emit-guard (claiming existing sessions without shipping)..."
  /usr/bin/flock -n "$INSTALL_DIR/.lock" "$NODE_BIN" "$INSTALL_DIR/cost-export.mjs" seed || c_warn "seed returned non-zero"
else
  c_info "emitted.json exists — skipping seed (already initialized)."
fi

# --- 6. NOW start the timer (guard is populated) ---------------------------
systemctl --user enable --now claude-cost-export.timer
c_ok "timer enabled: $(systemctl --user is-active claude-cost-export.timer) ($(systemctl --user is-enabled claude-cost-export.timer))"
# Linger lets the timer run even when not logged into a session (best-effort).
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
  if loginctl enable-linger "$USER" 2>/dev/null; then
    c_ok "enabled linger for $USER"
  else
    c_warn "could not enable linger (needs root). For run-while-logged-out: sudo loginctl enable-linger $USER"
  fi
fi

cat <<EOF

$(c_ok "Claude Code cost export installed.")
  State:    $INSTALL_DIR
  Timer:    every 5 min (systemctl --user list-timers claude-cost-export.timer)
  Spool:    $INSTALL_DIR/spool.ndjson   (unsent; drains when on-LAN)
  Run now:  flock -n $INSTALL_DIR/.lock $NODE_BIN $INSTALL_DIR/cost-export.mjs        # sweep + ship
  Backfill: COST_LOOKBACK_DAYS=90 flock -n $INSTALL_DIR/.lock $NODE_BIN $INSTALL_DIR/cost-export.mjs sweep
  Dashboard: "Claude Runner Fleet" → Local sessions row  (source="local")
EOF
