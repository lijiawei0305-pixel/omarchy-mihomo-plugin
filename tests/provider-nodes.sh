#!/usr/bin/env bash
set -euo pipefail

# Fake controller only: never contact the user's core or change proxy settings.
ROOT="${PROVIDER_TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

root = Path(sys.argv[1])
requests = []
provider_status = 200
providers = {"providers": {"subscription": {"proxies": [
    {"name": "专线-香港1", "type": "AnyTLS", "history": [{"delay": 42}]}
]}}}

class Controller(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        requests.append(self.path)
        payload = {
            "/version": {"version": "test"},
            "/configs": {"mode": "rule"},
            "/proxies": {"proxies": {"Select": {
                "type": "Selector", "all": ["专线-香港1"], "now": "专线-香港1"
            }}},
            "/providers/proxies": providers,
        }.get(self.path)
        status = provider_status if self.path == "/providers/proxies" else 200
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())

server = ThreadingHTTPServer(("127.0.0.1", 0), Controller)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        config = tmp / "config" / "omarchy-mihomo"
        config.mkdir(parents=True)
        (config / "config").write_text(f"endpoint = 127.0.0.1:{server.server_port}\n")
        fake = tmp / "fake"
        fake.mkdir()
        for command in ("gsettings", "pgrep"):
            (fake / command).write_text("#!/bin/sh\nexit 1\n")
            (fake / command).chmod(0o700)
        env = dict(os.environ, XDG_CONFIG_HOME=str(tmp / "config"),
                   PATH=str(fake) + os.pathsep + os.environ["PATH"])

        def bundle(command):
            requests.clear()
            result = subprocess.run([str(root / "bin/mihomo-ctl"), command],
                                    env=env, text=True, capture_output=True,
                                    check=True, timeout=15)
            return json.loads(result.stdout)

        data = bundle("core")
        assert data.get("providersProxies") == providers, "provider nodes missing from core bundle"
        assert set(requests) == {"/version", "/configs", "/proxies", "/providers/proxies"}

        data = bundle("status")
        assert "providersProxies" not in data
        assert set(requests) == {"/version", "/configs"}, requests

        for provider_status in (404, 503):
            data = bundle("core")
            assert data["providersProxies"] is None, data
            assert data["version"]["version"] == "test"
            assert "Select" in data["proxies"]["proxies"]
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print("provider bundle tests: PASS")
PY

node - "$ROOT" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2] + '/Service.qml', 'utf8');
// Execute the shipped service methods rather than a separate merge algorithm.
const methods = ['encode', 'setIfChanged', 'sameStringList', 'isGroupName',
  'proxyFor', 'nodesOf', 'delayOf', 'applyCore', 'runNextTest', 'selectNode'];
const ctx = {
  proxies: {}, proxyProviderNames: {}, groupNames: [], delays: {},
  lastProxiesStamp: '', ready: true, testQueue: [], runner: '/test/mihomo-ctl',
  testProc: {running: false}, testTimeout: 5000, testUrl: 'https://example.com/test',
  skipNodeType: {Selector: true, URLTest: true, Direct: true, Reject: true},
  t: (...args) => args.join(' '),
  markDisconnected: message => { throw Error(message); },
  maybeRefreshSysproxyPort: () => {},
  enqueue: args => { ctx.lastAction = args; },
};
ctx.root = ctx;
vm.createContext(ctx);
for (const name of methods) {
  const method = source.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'));
  assert.ok(method, `missing service method ${name}`);
  vm.runInContext(method[0], ctx);
}

const name = '专线2.5x-香港1';
const core = {
  GLOBAL: {type: 'Selector', all: ['Select', 'Auto'], now: 'Select'},
  Select: {type: 'Selector', all: [name, 'shared'], now: name},
  Auto: {type: 'URLTest', all: [name], now: name},
  Hidden: {type: 'Selector', all: ['shared'], now: 'shared'},
  DIRECT: {type: 'Direct'},
  shared: {name: 'shared', type: 'Shadowsocks', history: [{delay: 10}]},
};
const providerName = '订阅 / test';
const providers = {
  [providerName]: {proxies: [
    {name, type: 'AnyTLS', history: [{delay: 42}]},
    {name: 'shared', type: 'AnyTLS', history: [{delay: 99}]},
    {name: 'Select', type: 'AnyTLS'},
    {name: 'DIRECT', type: 'AnyTLS'},
    {name: '__proto__', type: 'AnyTLS'},
    {name: 'constructor', type: 'AnyTLS'},
    null, {}, {name: 123},
  ]},
  duplicate: {proxies: [{name, type: 'AnyTLS', history: [{delay: 88}]}]},
  empty: {proxies: []}, malformed: {proxies: {}}, missing: null,
};
const data = {proxies: {proxies: core}, providersProxies: {providers}};
function apply(value) { ctx.applyCore(JSON.stringify(value)); }

apply(data);
assert.equal(ctx.proxyFor(name).type, 'AnyTLS');
assert.equal(ctx.delayOf(name), 42);
assert.equal(ctx.delayOf('shared'), 10); // Static node takes precedence.
assert.equal(ctx.proxyFor('Select').type, 'Selector');
assert.equal(ctx.proxyFor('DIRECT').type, 'Direct');
assert.equal(ctx.proxyFor('__proto__').type, 'AnyTLS');
assert.equal(ctx.proxyFor('constructor').type, 'AnyTLS');
assert.equal(ctx.nodeCount, 4); // Each provider name is counted once.
assert.equal(JSON.stringify(ctx.groupNames), JSON.stringify(['Select', 'Auto', 'Hidden']));
assert.ok(ctx.nodesOf('Select').every(node => ctx.proxyFor(node)));
assert.equal(ctx.proxyProviderNames[name], providerName);
assert.equal(ctx.proxyProviderNames.shared, undefined);

const groupList = ctx.groupNames;
const proxyMap = ctx.proxies;
apply(data);
assert.equal(ctx.proxies, proxyMap); // An unchanged poll preserves map identity.
assert.equal(ctx.groupNames, groupList);
providers[providerName].proxies[0].history.push({delay: 77});
apply(data);
assert.equal(ctx.delayOf(name), 77); // Same groups, newer node history.
assert.equal(ctx.groupNames, groupList); // No group-list rebuild.

const delayed = JSON.parse(JSON.stringify(data));
delayed.providersProxies = null;
apply(delayed);
assert.equal(ctx.proxyFor(name), null);
assert.equal(ctx.nodeCount, 1);
apply(data); // Provider recovery must work without a group change.
assert.equal(ctx.delayOf(name), 77);
assert.equal(ctx.nodeCount, 4);

function probe(node, group) {
  ctx.testProc.running = false;
  ctx.testQueue = [{name: node, group}];
  ctx.runNextTest();
  return ctx.testProc.command[3];
}
assert.ok(probe(name, false).startsWith('/providers/proxies/'
  + encodeURIComponent(providerName) + '/' + encodeURIComponent(name) + '/healthcheck?'));
assert.ok(probe('shared', false).startsWith('/proxies/shared/delay?'));
assert.ok(probe('Select', true).startsWith('/group/Select/delay?'));
ctx.selectNode('Select', name);
assert.equal(ctx.lastAction[0], 'put');
assert.equal(ctx.lastAction[1], '/proxies/Select');
assert.equal(JSON.parse(ctx.lastAction[2]).name, name);

apply({proxies: {proxies: core}}); // Older cores and static-only configurations.
assert.equal(ctx.delayOf('shared'), 10);
assert.equal(ctx.proxyFor(name), null);
assert.equal(ctx.proxyProviderNames[name], undefined);
assert.equal(ctx.nodeCount, 1);
console.log('provider service tests: PASS');
JS
