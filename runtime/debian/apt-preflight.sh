#!/usr/bin/env bash
# apt-preflight.sh — Debian APT pre-update checks for penguins-over-the-air
#
# Runs before an OTA update to ensure the Debian package state is clean
# and won't conflict with the incoming OS image. Also refreshes LVFS
# metadata so fwupd has current firmware information.
#
# Commands:
#   check      Verify APT state is clean (no broken packages, no held packages)
#   refresh    Run apt-get update + fwupdmgr refresh
#   preflight  Run both check and refresh (default pre-update hook)
#
# Used as a pre-install hook: /etc/pota/hooks.d/pre-install-10-apt-preflight.sh

set -euo pipefail

CMD="${1:-preflight}"

info() { echo "[pota-apt] $*"; }
warn() { echo "[pota-apt] WARN: $*" >&2; }
die()  { echo "[pota-apt] ERROR: $*" >&2; exit 1; }

cmd_check() {
  info "Checking APT state"

  # Broken packages
  local broken
  broken=$(dpkg --audit 2>/dev/null | wc -l)
  if [[ "$broken" -gt 0 ]]; then
    warn "Broken packages detected — run: dpkg --configure -a && apt-get -f install"
    dpkg --audit >&2
    exit 1
  fi

  # Held packages that might conflict with OTA
  local held
  held=$(apt-mark showhold 2>/dev/null)
  if [[ -n "$held" ]]; then
    warn "Held packages (may conflict with OTA):"
    echo "$held" >&2
  fi

  # Check available disk space (need at least 500MB for staging)
  local avail_kb
  avail_kb=$(df /var/lib/pota 2>/dev/null | awk 'NR==2{print $4}' || df / | awk 'NR==2{print $4}')
  if [[ "$avail_kb" -lt 512000 ]]; then
    die "Insufficient disk space: ${avail_kb}KB available, 512000KB required"
  fi

  info "APT state OK"
}

cmd_refresh() {
  info "Refreshing package metadata"

  # APT update (non-fatal — we don't want a network blip to block OTA)
  if apt-get update -qq 2>/dev/null; then
    info "APT metadata refreshed"
  else
    warn "apt-get update failed — continuing anyway"
  fi

  # fwupd LVFS refresh
  if command -v fwupdmgr &>/dev/null; then
    if fwupdmgr refresh --force 2>/dev/null; then
      info "LVFS metadata refreshed"
    else
      warn "fwupdmgr refresh failed — continuing anyway"
    fi
  fi
}

cmd_preflight() {
  cmd_check
  cmd_refresh
}

case "$CMD" in
  check)     cmd_check ;;
  refresh)   cmd_refresh ;;
  preflight) cmd_preflight ;;
  *) die "Usage: apt-preflight.sh {check|refresh|preflight}" ;;
esac
