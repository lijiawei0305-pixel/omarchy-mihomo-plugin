#!/usr/bin/env bash
set -euo pipefail

# Exercise the System Proxy contract without changing the host desktop proxy.
# The fake controller response is served by curl, while a local TCP listener
# is created only for the final success case.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'kill "${LISTENER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

FAKE="$TMP/fake"
mkdir -p "$FAKE" "$TMP/config"
export XDG_CONFIG_HOME="$TMP/config"

cat >"$FAKE/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_CONFIG_MODE:-mixed}" == "port-only" ]]; then
  printf '{"port":7890}\n200\n'
else
  printf '{"mixed-port":%s}\n200\n' "${FAKE_MIXED_PORT:-7890}"
fi
SH

cat >"$FAKE/gsettings" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == get ]]; then
  printf "'none'\n"
fi
SH

cat >"$FAKE/dconf" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"$FAKE/systemctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod 700 "$FAKE/curl" "$FAKE/gsettings" "$FAKE/dconf" "$FAKE/systemctl"
export PATH="$FAKE:/usr/bin:/bin"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"

fail_cmd() {
  if "$ROOT/bin/mihomo-ctl" sysproxy on 127.0.0.1 "$1" >"$TMP/out" 2>"$TMP/err"; then
    echo "expected failure for port $1" >&2
    exit 1
  fi
}

# A regular HTTP port is not accepted as a mixed-port substitute.
export FAKE_CONFIG_MODE=port-only
fail_cmd "$PORT"
grep -Fq "requires Mihomo mixed-port $PORT" "$TMP/out"

# The controller must report the requested mixed-port, and a real listener
# must exist before the desktop proxy is changed.
export FAKE_CONFIG_MODE=mixed
export FAKE_MIXED_PORT="$PORT"
MISMATCH_PORT=$((PORT == 65535 ? PORT - 1 : PORT + 1))
fail_cmd "$MISMATCH_PORT"
grep -Fq "requires Mihomo mixed-port $MISMATCH_PORT" "$TMP/out"
fail_cmd "$PORT"
grep -Fq "not listening on mixed-port $PORT" "$TMP/out"

PORT="$PORT" python3 - <<'PY' &
import socket
import os

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", int(os.environ["PORT"])))
server.listen()
while True:
    connection, _ = server.accept()
    connection.close()
PY
LISTENER_PID=$!
for _ in $(seq 1 20); do
  if /usr/bin/bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" >/dev/null 2>&1; then break; fi
  sleep 0.05
done

if "$ROOT/bin/mihomo-ctl" sysproxy on evil.example "$PORT" >"$TMP/out" 2>"$TMP/err"; then
  echo "expected non-local system proxy host to be rejected" >&2
  exit 1
fi
grep -Fq "system proxy host must be local" "$TMP/out"

result="$($ROOT/bin/mihomo-ctl sysproxy on 127.0.0.1 "$PORT")"
grep -Fq '"ok":true' <<<"$result"

printf 'system proxy tests: PASS\n'
