#!/usr/bin/env bash
set -euo pipefail

# Controller polling and installer checks. Uses a temporary config and a local
# HTTP server; it does not talk to a running Mihomo or change desktop proxy.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'kill "${HTTP_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkdir -p "$TMP/config/omarchy-mihomo" "$TMP/bin" "$TMP/empty"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_DATA_HOME="$TMP/data"

cat >"$TMP/bin/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat >"$TMP/bin/gsettings" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == get ]]; then
  printf "'none'\n"
fi
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat >"$TMP/bin/dconf" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod 700 "$TMP/bin/pgrep" "$TMP/bin/gsettings" "$TMP/bin/systemctl" "$TMP/bin/dconf"
export PATH="$TMP/bin:/usr/bin:/bin"

cat >"$TMP/server.py" <<'PY'
import os
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

mode_file = pathlib.Path(os.environ["MODE_FILE"])

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        mode = mode_file.read_text(encoding="utf-8").strip() if mode_file.exists() else ""
        path = self.path.split("?", 1)[0]
        if path == "/version":
            body, code = b'{"meta":true,"version":"fake"}', 200
        elif path == "/configs":
            if mode == "configs-fail":
                body, code = b'{"message":"no"}', 500
            else:
                body, code = b'{"mixed-port":7890,"mode":"rule"}', 200
        elif path == "/proxies":
            body, code = b'{"proxies":{}}', 200
        else:
            body, code = b"", 404
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(os.environ["PORT_FILE"]).write_text(str(server.server_address[1]), encoding="utf-8")
server.serve_forever()
PY

CLOSED_PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
printf 'endpoint = 127.0.0.1:%s\n' "$CLOSED_PORT" >"$XDG_CONFIG_HOME/omarchy-mihomo/config"
if "$ROOT/bin/mihomo-ctl" status >"$TMP/down.out" 2>"$TMP/down.err"; then
  echo "expected a down controller to fail status" >&2
  exit 1
fi
python3 - "$TMP/down.out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert "error" in data, data
assert "version" not in data, data
assert "configs" not in data, data
PY

printf 'ok\n' >"$TMP/mode"
MODE_FILE="$TMP/mode" PORT_FILE="$TMP/port" python3 "$TMP/server.py" &
HTTP_PID=$!
for _ in $(seq 1 50); do [[ -s "$TMP/port" ]] && break; sleep 0.05; done
PORT="$(cat "$TMP/port")"
printf 'endpoint = 127.0.0.1:%s\n' "$PORT" >"$XDG_CONFIG_HOME/omarchy-mihomo/config"

printf 'configs-fail\n' >"$TMP/mode"
partial="$("$ROOT/bin/mihomo-ctl" status)"
python3 - "$partial" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["version"]["version"] == "fake", data
assert data["configs"] is None, data
assert "error" not in data, data
PY

printf 'ok\n' >"$TMP/mode"
full="$("$ROOT/bin/mihomo-ctl" core)"
python3 - "$full" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["version"]["version"] == "fake", data
assert data["configs"]["mixed-port"] == 7890, data
assert "proxies" in data["proxies"], data
PY

mkdir -p "$TMP/curlbin"
cat >"$TMP/curlbin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl should not have been called" >&2
exit 99
SH
chmod 700 "$TMP/curlbin/curl"
if PATH="$TMP/curlbin:$PATH" OMARCHY_MIHOMO_MANAGER_REPO='https://evil.example/repo' \
  "$ROOT/bin/install-manager" >"$TMP/install.out" 2>"$TMP/install.err"; then
  echo "expected an invalid manager repository to be rejected" >&2
  exit 1
fi
if grep -Fq "curl should not have been called" "$TMP/install.err"; then
  echo "installer contacted the network for an invalid repository" >&2
  exit 1
fi
grep -Fq "invalid manager repository" "$TMP/install.err"
if PATH="$TMP/curlbin:$PATH" OMARCHY_MIHOMO_MANAGER_VERSION='../v1' \
  "$ROOT/bin/install-manager" >"$TMP/version.out" 2>"$TMP/version.err"; then
  echo "expected an invalid manager version to be rejected" >&2
  exit 1
fi
grep -Fq "invalid manager version" "$TMP/version.err"

printf 'security regression tests: PASS\n'
