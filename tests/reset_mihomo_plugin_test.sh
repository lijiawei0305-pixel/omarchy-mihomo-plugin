#!/usr/bin/env bash
set -Eeuo pipefail

# Clean-room reset for the manual Omarchy Mihomo onboarding test.
#
# This is intentionally not a CI test. It stops named Mihomo services and
# processes, removes plugin state, removes known Mihomo packages, installs the
# plugin from this checkout, and installs the supplied Mihomo package. The
# expected final state is: the plugin is installed, Mihomo is installed but
# stopped, no manager/helper is present, and the UI is ready for "Set up
# Mihomo".

PLUGIN_ID="io.github.lijiawei0305-pixel.mihomo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="${OMARCHY_MIHOMO_PLUGIN_REPO:-$DEFAULT_REPO}"

PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
PLUGIN_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-mihomo"
PLUGIN_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-mihomo"
PLUGIN_SERVICE="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/omarchy-mihomo.service"
PROXY_DROPIN="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/99-mihomo-proxy.conf"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  reset_mihomo_plugin_test.sh [--yes] [--package PATH]

The Mihomo Arch package can also be supplied with:
  OMARCHY_MIHOMO_PACKAGE=/path/to/mihomo.pkg.tar.zst

The checkout defaults to the repository root. Override it with:
  OMARCHY_MIHOMO_PLUGIN_REPO=/path/to/omarchy-mihomo-plugin

This script is destructive. It is for a manual Arch/Omarchy onboarding test,
not for CI. Without --yes it asks for confirmation before changing the host.
USAGE
}

auto_confirm=0
package_arg=""
while (($# > 0)); do
  case "$1" in
    --yes)
      auto_confirm=1
      ;;
    --package)
      shift
      [[ $# -gt 0 ]] || die "--package requires a path"
      package_arg="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      [[ -z "$package_arg" ]] || die "unexpected argument: $1"
      package_arg="$1"
      ;;
  esac
  shift
done

MIHOMO_PKG="${OMARCHY_MIHOMO_PACKAGE:-$package_arg}"
[[ -d "$REPO" ]] || die "Repo not found: $REPO"
[[ -n "$MIHOMO_PKG" ]] || die "Mihomo package path is required; use --package or OMARCHY_MIHOMO_PACKAGE"
[[ -f "$MIHOMO_PKG" ]] || die "Mihomo package not found: $MIHOMO_PKG"
command -v omarchy >/dev/null 2>&1 || die "omarchy command not found"
command -v pacman >/dev/null 2>&1 || die "pacman command not found"

log "Preflight"
printf 'Repo:        %s\n' "$REPO"
printf 'Mihomo pkg:  %s\n' "$MIHOMO_PKG"
printf 'Plugin ID:   %s\n' "$PLUGIN_ID"
printf '\nThis will stop named Mihomo services/processes, remove the plugin checkout\n'
printf 'and plugin state, remove known Mihomo packages, and clear system-proxy state.\n'
printf 'It will NOT delete ~/.config/mihomo.\n\n'
if [[ "$auto_confirm" != 1 ]]; then
  read -r -p "Continue? [y/N] " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || exit 0
fi

log "Acquire sudo credentials"
sudo -v

log "Turn off any previous system proxy state"
if [[ -x "$PLUGIN_DIR/bin/mihomo-ctl" ]]; then
  "$PLUGIN_DIR/bin/mihomo-ctl" sysproxy off >/dev/null 2>&1 || true
fi
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.system.proxy mode 'none' >/dev/null 2>&1 || true
fi
if command -v dconf >/dev/null 2>&1; then
  dconf write /system/proxy/mode "'none'" >/dev/null 2>&1 || true
fi
rm -f "$PROXY_DROPIN"
systemctl --user set-environment \
  http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= \
  all_proxy= ALL_PROXY= no_proxy= NO_PROXY= \
  >/dev/null 2>&1 || true
ok "System proxy cleanup requested"

log "Stop Mihomo processes/services"
systemctl --user disable --now omarchy-mihomo.service >/dev/null 2>&1 || true
systemctl --user stop mihomo.service mihomo-alpha.service clash-meta.service verge-mihomo.service >/dev/null 2>&1 || true
sudo systemctl stop mihomo.service mihomo-alpha.service clash-meta.service verge-mihomo.service >/dev/null 2>&1 || true
pkill -x mihomo >/dev/null 2>&1 || true
pkill -x mihomo-alpha >/dev/null 2>&1 || true
pkill -x clash-meta >/dev/null 2>&1 || true
sleep 1
ok "Mihomo services/processes stopped"

log "Remove plugin-managed service and state"
rm -f "$PLUGIN_SERVICE"
systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user reset-failed omarchy-mihomo.service >/dev/null 2>&1 || true
rm -rf "$PLUGIN_STATE"
rm -rf "$PLUGIN_DATA"
ok "Plugin-owned config/data removed"

log "Remove Omarchy plugin"
omarchy plugin remove "$PLUGIN_ID" >/dev/null 2>&1 || true
rm -rf "$PLUGIN_DIR"
ok "Plugin removed"

log "Uninstall existing Mihomo package(s)"
mapfile -t mihomo_pkgs < <(
  pacman -Qq 2>/dev/null \
    | grep -E '^(mihomo|mihomo-bin|mihomo-alpha|clash-meta)$' \
    || true
)
if ((${#mihomo_pkgs[@]} > 0)); then
  printf 'Removing: %s\n' "${mihomo_pkgs[*]}"
  sudo pacman -Rns --noconfirm "${mihomo_pkgs[@]}"
else
  warn "No installed Mihomo package matched the known package names"
fi
pkill -x mihomo >/dev/null 2>&1 || true
pkill -x mihomo-alpha >/dev/null 2>&1 || true
pkill -x clash-meta >/dev/null 2>&1 || true
if command -v mihomo >/dev/null 2>&1; then
  warn "mihomo still exists at $(command -v mihomo); continuing, but this is not a fully clean package state"
else
  ok "Mihomo binary is absent"
fi

log "Prepare local plugin checkout"
git -C "$REPO" status --short
printf 'Branch: %s\n' "$(git -C "$REPO" branch --show-current)"
printf 'HEAD:   %s\n' "$(git -C "$REPO" rev-parse --short HEAD)"
# Remove development-built helper binaries so Setup must test the real
# installer path. These paths are inside the explicitly selected checkout.
rm -f "$REPO/bin/omarchy-mihomo-manager"
rm -f "$REPO/manager/omarchy-mihomo-manager"

log "Install plugin from local checkout"
omarchy plugin add "$REPO" --enable
omarchy bar move "$PLUGIN_ID" --section right
ok "Plugin installed and enabled"

log "Install Mihomo from local package"
sudo pacman -U --noconfirm "$MIHOMO_PKG"
MIHOMO_BIN="$(command -v mihomo || true)"
[[ -n "$MIHOMO_BIN" ]] || die "Mihomo package installed but 'mihomo' is not in PATH"
printf 'Mihomo binary: %s\n' "$MIHOMO_BIN"
mihomo -v || true

log "Reset TUN capability for first-run testing"
if command -v getcap >/dev/null 2>&1; then
  caps="$(getcap "$MIHOMO_BIN" 2>/dev/null || true)"
  if [[ -n "$caps" ]]; then
    sudo setcap -r "$MIHOMO_BIN" || true
  fi
  caps="$(getcap "$MIHOMO_BIN" 2>/dev/null || true)"
  [[ -z "$caps" ]] || die "Could not clear Mihomo capabilities: $caps"
  ok "Mihomo has no file capabilities"
else
  warn "getcap is unavailable; could not verify first-run TUN capability state"
fi

log "Ensure Mihomo is installed but NOT running"
systemctl --user stop omarchy-mihomo.service mihomo.service mihomo-alpha.service clash-meta.service verge-mihomo.service >/dev/null 2>&1 || true
sudo systemctl stop mihomo.service mihomo-alpha.service clash-meta.service verge-mihomo.service >/dev/null 2>&1 || true
pkill -x mihomo >/dev/null 2>&1 || true
pkill -x mihomo-alpha >/dev/null 2>&1 || true
pkill -x clash-meta >/dev/null 2>&1 || true
sleep 1
if pgrep -x mihomo >/dev/null 2>&1; then
  pgrep -af mihomo || true
  die "Mihomo is still running"
fi

# Remove anything that would make Setup skip the true first-run path.
rm -f "$PLUGIN_SERVICE"
systemctl --user daemon-reload >/dev/null 2>&1 || true
rm -rf "$PLUGIN_DATA"
[[ ! -e "$PLUGIN_DATA/bin/omarchy-mihomo-manager" ]] || die "Manager helper unexpectedly exists"

log "Restart Omarchy shell"
omarchy restart shell

log "Final verification"
printf 'Plugin dir:      '
[[ -d "$PLUGIN_DIR" ]] && echo "present" || die "plugin directory missing"
printf 'Mihomo binary:   '
command -v mihomo
printf 'Mihomo process:  '
if pgrep -x mihomo >/dev/null 2>&1; then
  echo "RUNNING (unexpected)"
  exit 1
else
  echo "stopped"
fi
printf 'Controller 9090: '
if curl -fsS --connect-timeout 1 http://127.0.0.1:9090/version >/dev/null 2>&1; then
  echo "reachable (unexpected)"
  exit 1
else
  echo "not reachable"
fi
printf 'Manager helper:  '
if [[ -e "$PLUGIN_DATA/bin/omarchy-mihomo-manager" ]]; then
  echo "present (unexpected)"
  exit 1
else
  echo "absent"
fi
printf 'Plugin service:  '
if systemctl --user cat omarchy-mihomo.service >/dev/null 2>&1; then
  echo "present (unexpected)"
  exit 1
else
  echo "absent"
fi

cat <<'MSG'

============================================================
READY FOR ONBOARDING TEST
============================================================
Expected UI state now:

  Mihomo detected
  -> "Set up Mihomo" button is visible

STOP HERE.

Next manual action:
  1. Open the Mihomo widget.
  2. Click "Set up Mihomo".
  3. Observe whether helper installation succeeds.

Useful parallel log during that click:
  journalctl --user -f | grep -Ei 'quickshell|omarchy|mihomo|curl'

If helper installation fails, do NOT manually install it first.
Capture the UI message + journal output so the automatic path remains reproducible.
============================================================
MSG
