#!/usr/bin/env bash
# fwupd-debian.sh — Debian-specific fwupd integration for penguins-over-the-air
#
# Extends the base fwupd-coordinator.sh with Debian-specific behaviour:
#   - Respects /etc/apt/apt.conf.d/50unattended-upgrades fwupd settings
#   - Handles Debian's fwupd plugin configuration in /etc/fwupd/
#   - Integrates with Debian's needrestart for post-firmware service restarts
#   - Supports Debian Secure Boot MOK enrollment for new firmware keys
#
# Commands:
#   check-debian    Check fwupd state with Debian-specific context
#   apply-debian    Apply firmware updates respecting Debian policy
#   mok-enroll      Enroll a new MOK key for Secure Boot firmware
#   status          Show Debian fwupd configuration state
#
# Delegates to the base fwupd-coordinator.sh for core operations.

set -euo pipefail

CMD="${1:-}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_COORDINATOR="${LOTA_RUNTIME_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/runtime}/firmware/fwupd-coordinator.sh"

info() { echo "[pota-fwupd-debian] $*"; }
warn() { echo "[pota-fwupd-debian] WARN: $*" >&2; }
die()  { echo "[pota-fwupd-debian] ERROR: $*" >&2; exit 1; }

# Check if unattended-upgrades has fwupd disabled
unattended_upgrades_allows_fwupd() {
  local ua_conf="/etc/apt/apt.conf.d/50unattended-upgrades"
  [[ ! -f "$ua_conf" ]] && return 0  # no config = allow

  # If fwupd is explicitly blocked in unattended-upgrades, respect it
  if grep -q 'Unattended-Upgrade::Package-Blacklist.*fwupd' "$ua_conf" 2>/dev/null; then
    return 1
  fi
  return 0
}

# Read fwupd plugin allowlist from system.toml
get_plugin_allowlist() {
  python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
config_path = '/etc/pota/system.toml'
try:
    with open(config_path, 'rb') as f:
        config = tomllib.load(f)
    plugins = config.get('firmware', {}).get('debian', {}).get('plugin_allowlist', [])
    print(' '.join(plugins))
except Exception:
    pass
" 2>/dev/null || true
}

cmd_check_debian() {
  info "Checking fwupd state (Debian)"

  # Check unattended-upgrades policy
  if ! unattended_upgrades_allows_fwupd; then
    warn "fwupd is blocked by unattended-upgrades config — skipping firmware check"
    exit 0
  fi

  # Check fwupd service state
  if ! systemctl is-active --quiet fwupd 2>/dev/null; then
    info "Starting fwupd service"
    systemctl start fwupd 2>/dev/null || warn "Could not start fwupd"
  fi

  # Delegate to base coordinator
  bash "$BASE_COORDINATOR" check
}

cmd_apply_debian() {
  info "Applying firmware updates (Debian)"

  if ! unattended_upgrades_allows_fwupd; then
    warn "fwupd blocked by unattended-upgrades — skipping"
    exit 0
  fi

  # Apply plugin allowlist if configured
  local allowlist
  allowlist=$(get_plugin_allowlist)
  if [[ -n "$allowlist" ]]; then
    info "Plugin allowlist: $allowlist"
    for plugin in $allowlist; do
      fwupdmgr enable-remote "$plugin" 2>/dev/null || true
    done
  fi

  # Delegate to base coordinator
  bash "$BASE_COORDINATOR" apply

  # Run needrestart if available (Debian-specific post-firmware service restart)
  if command -v needrestart &>/dev/null; then
    info "Running needrestart post-firmware"
    needrestart -r a 2>/dev/null || true
  fi
}

cmd_mok_enroll() {
  local key_path="${1:-}"
  [[ -z "$key_path" ]] && die "Usage: mok-enroll KEY_PATH"
  [[ ! -f "$key_path" ]] && die "Key not found: $key_path"

  info "Enrolling MOK key for Secure Boot: $key_path"

  if ! command -v mokutil &>/dev/null; then
    die "mokutil not found — install: apt-get install mokutil"
  fi

  # Convert PEM to DER if needed
  local der_path="$key_path"
  if file "$key_path" | grep -q "PEM"; then
    der_path="${key_path%.pem}.der"
    openssl x509 -in "$key_path" -outform DER -out "$der_path"
    info "Converted PEM → DER: $der_path"
  fi

  mokutil --import "$der_path"
  info "MOK key enrolled — reboot to complete enrollment in shim"
}

cmd_status() {
  echo "=== penguins-over-the-air fwupd (Debian) ==="

  echo "fwupd service: $(systemctl is-active fwupd 2>/dev/null || echo 'inactive')"
  echo "fwupd version: $(fwupdmgr --version 2>/dev/null | head -1 || echo 'not installed')"

  echo ""
  echo "Unattended-upgrades allows fwupd: $(unattended_upgrades_allows_fwupd && echo yes || echo no)"

  local allowlist
  allowlist=$(get_plugin_allowlist)
  echo "Plugin allowlist: ${allowlist:-all}"

  echo ""
  echo "Secure Boot:"
  if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null || echo "  (mokutil query failed)"
  else
    echo "  mokutil not installed"
  fi

  echo ""
  bash "$BASE_COORDINATOR" status 2>/dev/null || true
}

case "$CMD" in
  check-debian)  cmd_check_debian ;;
  apply-debian)  cmd_apply_debian ;;
  mok-enroll)    cmd_mok_enroll "$@" ;;
  status)        cmd_status ;;
  # Pass-through to base coordinator for standard commands
  check|apply|pre-os-update|post-os-update|boot-check)
    bash "$BASE_COORDINATOR" "$CMD" "$@" ;;
  "")  die "Usage: fwupd-debian.sh {check-debian|apply-debian|mok-enroll|status|check|apply|pre-os-update|post-os-update|boot-check}" ;;
  *)   die "Unknown command: $CMD" ;;
esac
