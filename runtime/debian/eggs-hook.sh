#!/usr/bin/env bash
# eggs-hook.sh — penguins-eggs lifecycle integration for penguins-over-the-air
#
# Integrates penguins-eggs ISO generation with the OTA update lifecycle.
# Called as a post-install hook when rebuild_iso_on_update = true in system.toml.
#
# penguins-eggs produces installable/live ISOs from the running Debian system.
# After an OTA update, this hook optionally rebuilds the ISO so the updated
# system can be redistributed or used for fresh installs.
#
# Commands:
#   pre-update    Save current eggs state before OTA
#   post-update   Optionally rebuild ISO after OTA
#   status        Show penguins-eggs installation state
#   produce       Trigger ISO production (wraps eggs produce)
#
# Environment:
#   POTA_EGGS_BIN              Path to eggs binary (default: /usr/bin/eggs)
#   POTA_EGGS_CHANNEL          eggs channel: eggs|eggs-dev (default: eggs)
#   POTA_REBUILD_ISO_ON_UPDATE true|false (default: false)
#   POTA_ISO_OUTPUT_DIR        ISO output directory (default: /home/eggs)

set -euo pipefail

CMD="${1:-}"
shift || true

EGGS_BIN="${POTA_EGGS_BIN:-/usr/bin/eggs}"
EGGS_CHANNEL="${POTA_EGGS_CHANNEL:-eggs}"
REBUILD_ISO="${POTA_REBUILD_ISO_ON_UPDATE:-false}"
ISO_OUTPUT_DIR="${POTA_ISO_OUTPUT_DIR:-/home/eggs}"
STATE_FILE="/var/lib/pota/eggs-state.json"

info() { echo "[pota-eggs] $*"; }
warn() { echo "[pota-eggs] WARN: $*" >&2; }
die()  { echo "[pota-eggs] ERROR: $*" >&2; exit 1; }

require_eggs() {
  [[ -x "$EGGS_BIN" ]] || die "penguins-eggs not found at $EGGS_BIN — install: apt-get install eggs"
}

cmd_pre_update() {
  info "Saving penguins-eggs state before OTA"

  local eggs_version=""
  if [[ -x "$EGGS_BIN" ]]; then
    eggs_version=$("$EGGS_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  fi

  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" <<EOF
{
  "eggs_version": "${eggs_version}",
  "saved_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "iso_output_dir": "${ISO_OUTPUT_DIR}"
}
EOF
  info "State saved: $STATE_FILE"
}

cmd_post_update() {
  info "Post-OTA penguins-eggs hook"

  if [[ "$REBUILD_ISO" != "true" ]]; then
    info "rebuild_iso_on_update=false — skipping ISO rebuild"
    return 0
  fi

  require_eggs

  info "Rebuilding penguins-eggs ISO after OTA update"
  cmd_produce
}

cmd_produce() {
  require_eggs

  info "Producing penguins-eggs ISO"
  mkdir -p "$ISO_OUTPUT_DIR"

  # eggs produce: create a live/installable ISO from the running system
  "$EGGS_BIN" produce \
    --nointeractive \
    --verbose \
    2>&1 | tee /var/log/pota/eggs-produce.log

  info "ISO produced in: $ISO_OUTPUT_DIR"
  ls -lh "$ISO_OUTPUT_DIR"/*.iso 2>/dev/null || warn "No ISO files found in $ISO_OUTPUT_DIR"
}

cmd_status() {
  echo "=== penguins-eggs status ==="

  if [[ -x "$EGGS_BIN" ]]; then
    echo "eggs binary:  $EGGS_BIN"
    echo "eggs version: $("$EGGS_BIN" --version 2>/dev/null | head -1 || echo unknown)"
    echo "eggs channel: $EGGS_CHANNEL"
  else
    echo "eggs binary:  NOT INSTALLED ($EGGS_BIN)"
  fi

  echo "ISO output:   $ISO_OUTPUT_DIR"
  echo "Rebuild ISO:  $REBUILD_ISO"

  if [[ -d "$ISO_OUTPUT_DIR" ]]; then
    echo ""
    echo "Existing ISOs:"
    ls -lh "$ISO_OUTPUT_DIR"/*.iso 2>/dev/null || echo "  (none)"
  fi

  if [[ -f "$STATE_FILE" ]]; then
    echo ""
    echo "Saved state:"
    cat "$STATE_FILE"
  fi
}

case "$CMD" in
  pre-update)  cmd_pre_update ;;
  post-update) cmd_post_update ;;
  produce)     cmd_produce ;;
  status)      cmd_status ;;
  "")  die "Usage: eggs-hook.sh {pre-update|post-update|produce|status}" ;;
  *)   die "Unknown command: $CMD" ;;
esac
