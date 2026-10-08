#!/usr/bin/env bash
set -euo pipefail

# Exercise the plugin-owned bootstrap path without starting a real core or
# touching the user's systemd manager. The fake systemctl marks the service as
# started and the fake controller becomes reachable at that point.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE="$TMP/fake"
mkdir -p "$FAKE"
export XDG_CONFIG_HOME="$TMP/config"
export MIHOMO_CTL="$FAKE/mihomo-ctl"
export MIHOMO_SETUP_ATTEMPTS=1
export FAKE_READY="$TMP/ready"

cat >"$FAKE/mihomo-ctl" <<'SH'
#!/usr/bin/bash
set -euo pipefail
[[ -e "$FAKE_READY" ]] || exit 1
[[ "${1:-} ${2:-}" == "get /version" ]] || exit 2
printf '{"version":"fake"}\n'
SH
chmod 700 "$FAKE/mihomo-ctl"

# Keep a non-executable mihomo earlier in PATH for the missing-core check.
: >"$FAKE/mihomo"

cat >"$FAKE/pgrep" <<'SH'
#!/usr/bin/bash
exit 1
SH
chmod 700 "$FAKE/pgrep"

ln -s /usr/bin/dirname "$FAKE/dirname"
ln -s /usr/bin/head "$FAKE/head"

cat >"$FAKE/systemctl" <<'SH'
#!/usr/bin/bash
set -euo pipefail
case "$*" in
  *"show-environment"*) exit 0 ;;
  *" cat "*) exit 1 ;;
  *"enable --now"*) : >"$FAKE_READY"; exit 0 ;;
  *"daemon-reload"*) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod 700 "$FAKE/systemctl"
export PATH="$FAKE:/usr/bin:/bin"

missing="$(PATH="$FAKE" /usr/bin/bash "$ROOT/bin/mihomo-setup" status)"
python3 - "$missing" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
assert data["state"] == "needs-core", data
assert data["binary"] is False, data
PY

# An executable placeholder is enough: the fake service does not execute it.
chmod 700 "$FAKE/mihomo"
setup="$($ROOT/bin/mihomo-setup setup)"
python3 - "$setup" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
assert data["state"] == "ready", data
assert data["managed"] is True, data
PY

core_home="$XDG_CONFIG_HOME/omarchy-mihomo/core"
bootstrap="$core_home/config.yaml"
service="$XDG_CONFIG_HOME/systemd/user/omarchy-mihomo.service"
[[ -f "$bootstrap" && -f "$service" ]]
[[ "$(stat -c '%a' "$bootstrap")" == "600" ]]
grep -Fq 'external-controller: 127.0.0.1:9090' "$bootstrap"
grep -Fq 'X-Omarchy-Mihomo-Managed: true' "$service"
grep -Fq 'ExecStart=' "$service"
if grep -Eq '^(tun|geox-url):' "$bootstrap"; then
  echo 'bootstrap unexpectedly depends on TUN or Geo resources' >&2
  exit 1
fi

preflight="$($ROOT/bin/mihomo-setup preflight --stack gvisor)"
python3 - "$preflight" <<'PY'
import json
import sys
data = json.loads(sys.argv[1])
ids = {check["id"] for check in data["checks"]}
assert {"tunCapability", "firewallTunCompatibility"} <= ids, data
PY

printf 'bootstrap tests: PASS\n'
