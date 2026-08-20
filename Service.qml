import QtQuick
import Quickshell
import Quickshell.Io

// Headless state holder for the mihomo panel.
//
// Everything the panel shows comes from the core's external controller, reached
// through bin/mihomo-ctl (which resolves the endpoint itself). No GUI client is
// involved, so the panel keeps working after clash-verge is uninstalled.
//
// Polling is scoped to what is actually on screen: `active` follows the panel's
// open state, `page` follows the visible tab. A closed panel only hits
// /version + /configs every 30s. The full /proxies payload is fetched while
// Home or Proxies is visible, and after a write.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  // Injected by Omarchy's service host after object creation.
  property var shell: null
  property var manifest: null

  readonly property bool ready: manifest !== null
    && manifest.__sourceDir !== undefined
    && String(manifest.__sourceDir) !== ""
  readonly property string pluginDir: ready
    ? String(manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.lijiawei0305-pixel.mihomo"
  readonly property string runner: pluginDir + "/bin/mihomo-ctl"

  // Set by the panel. Drives poll cadence and the streaming subscriptions.
  property bool active: false
  property string page: "home"

  property bool connected: false
  property string lastError: ""
  property string version: ""
  property string endpointTarget: ""
  property string endpointTransport: ""
  property string endpointSource: ""

  property string mode: "rule"
  property int mixedPort: 0
  property bool allowLan: false
  property bool ipv6: false
  property string logLevel: ""
  property bool tunEnabled: false
  property string tunStack: ""
  property string tunDevice: ""
  property bool tunAutoRoute: false
  property string tunDnsHijack: ""
  property bool unifiedDelay: false
  property string findProcessMode: ""
  property bool sniffing: false
  property bool geodataMode: false
  property bool geoAutoUpdate: false
  property int socksPort: 0
  property int redirPort: 0
  property int tproxyPort: 0
  property int httpPort: 0
  property int nodeCount: 0

  property string configPath: ""
  property int configSize: 0
  property int configMtime: 0
  property bool dnsEnabled: false
  property string dnsListen: ""
  property string dnsMode: ""
  property string dnsFakeIp: ""
  property bool configLoading: false
  property bool configReloading: false

  // Raw /proxies map plus the group ordering taken from GLOBAL.all, which is
  // the only place the core preserves the order groups appear in the config.
  property var proxies: ({})
  property var groupNames: []
  property var delays: ({})
  property var testing: ({})

  property real upSpeed: 0
  property real downSpeed: 0
  property real upTotal: 0
  property real downTotal: 0
  property real memInuse: 0

  property var proxyProviders: []
  property var ruleProviders: []
  property bool providersLoading: false

  property var rules: []
  property int ruleCount: 0
  property bool rulesLoading: false

  property var connections: []
  property var connectionBytes: ({})
  property bool connectionsLoading: false
  property string lastProxiesStamp: ""
  property string lastConnIdent: ""
  property string lastRulesRaw: ""
  property string lastProvidersStamp: ""

  property string notice: ""
  property string language: "en"

  I18n {
    id: i18n
    language: root.language
  }

  readonly property string modeLabel: t(mode === "global" ? "modeGlobal"
    : mode === "direct" ? "modeDirect"
    : "modeRule")

  function t() {
    var _dep = language
    return i18n.t.apply(i18n, arguments)
  }

  function setLanguage(code) {
    if (code !== "en" && code !== "zh") return
    language = code
    if (!ready || langSetProc.running) return
    langSetProc.command = ["/usr/bin/bash", runner, "set-lang", code]
    langSetProc.running = true
  }

  // --- helpers -------------------------------------------------------------

  function encode(name) {
    return encodeURIComponent(String(name || ""))
  }

  function setIfChanged(name, value) {
    if (root[name] !== value) root[name] = value
  }

  function sameStringList(a, b) {
    if (a === b) return true
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false
    }
    return true
  }

  // Only the fields the panel binds to. History and extra change on every
  // probe and would otherwise force a full group-list rebuild every poll.
  function proxyStamp(p) {
    if (!p) return ""
    var all = p.all
    return String(p.now || "") + "\x1f" + String(p.type || "") + "\x1f"
      + (p.hidden === true ? "1" : "0") + "\x1f" + (p.udp ? "1" : "0") + "\x1f"
      + (all && all.length ? all.join("\x1e") : "")
  }

  function proxiesUiStamp(map, groups) {
    var parts = []
    var i
    for (i = 0; i < groups.length; i++)
      parts.push(groups[i] + "=" + proxyStamp(map[groups[i]]))
    if (map && map["GLOBAL"] && groups.indexOf("GLOBAL") < 0)
      parts.push("GLOBAL=" + proxyStamp(map["GLOBAL"]))
    return parts.join("|")
  }

  function connUpload(id) {
    var row = connectionBytes ? connectionBytes[id] : undefined
    return row ? row.upload : 0
  }

  function connDownload(id) {
    var row = connectionBytes ? connectionBytes[id] : undefined
    return row ? row.download : 0
  }

  function proxyFor(name) {
    var p = proxies ? proxies[name] : undefined
    return p === undefined ? null : p
  }

  function isGroup(name) {
    return isGroupName(proxies, name)
  }

  function nodesOf(group) {
    var p = proxyFor(group)
    return p && p.all ? p.all : []
  }

  // mihomo records probe results per test URL. Prefer the plain `history`, then
  // the most recent entry across every `extra` URL, so a node probed through a
  // different test URL than its group still shows a number.
  function delayOf(name) {
    if (delays && delays[name] !== undefined) return delays[name]
    var p = proxyFor(name)
    if (!p) return -1

    var history = p.history
    if (history && history.length > 0) return Number(history[history.length - 1].delay)

    var best = -1
    var bestTime = ""
    var extra = p.extra
    for (var url in extra) {
      var entries = extra[url] ? extra[url].history : null
      if (!entries || entries.length === 0) continue
      var last = entries[entries.length - 1]
      var when = String(last.time || "")
      if (best < 0 || when > bestTime) {
        best = Number(last.delay)
        bestTime = when
      }
    }
    return best
  }

  function isTesting(name) {
    return testing && testing[name] === true
  }

  function markTesting(name, value) {
    var next = {}
    for (var key in testing) next[key] = testing[key]
    if (value) next[name] = true
    else delete next[name]
    testing = next
  }

  function fmtBytes(bytes) {
    var value = Number(bytes || 0)
    if (value >= 1073741824) return (value / 1073741824).toFixed(2) + " GB"
    if (value >= 1048576) return (value / 1048576).toFixed(1) + " MB"
    if (value >= 1024) return (value / 1024).toFixed(1) + " KB"
    return Math.round(value) + " B"
  }

  function fmtSpeed(bytes) {
    return fmtBytes(bytes) + "/s"
  }

  // --- reads ---------------------------------------------------------------

  function refresh(forceProxies) {
    if (!ready || coreProc.running) return
    var needProxies = forceProxies === true
      || (active && (page === "home" || page === "proxies"))
    coreProc.command = ["/usr/bin/bash", runner, needProxies ? "core" : "status"]
    coreProc.running = true
  }

  function refreshProviders() {
    if (!ready || providersProc.running) return
    providersLoading = true
    providersProc.running = true
  }

  function refreshRules() {
    if (!ready || rulesProc.running) return
    rulesLoading = true
    rulesProc.running = true
  }

  function refreshConnections() {
    if (!ready || connectionsProc.running) return
    connectionsProc.running = true
  }

  function refreshPage() {
    if (page === "config") refreshConfig()
    else if (page === "rules") refreshRules()
    else if (page === "connections") refreshConnections()
    else refresh()
  }

  function refreshConfig() {
    refreshConfigInfo()
    refreshProviders()
    refreshRules()
  }

  function refreshConfigInfo() {
    if (!ready || configInfoProc.running) return
    configLoading = true
    configInfoProc.running = true
  }

  function applyCore(raw) {
    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      connected = false
      lastError = t("parseError")
      return
    }

    if (data.error) {
      connected = false
      lastError = String(data.error)
      return
    }

    if (data.version) setIfChanged("version", String(data.version.version || ""))

    var configs = data.configs
    if (configs) {
      setIfChanged("mode", String(configs.mode || "rule"))
      setIfChanged("mixedPort", Number(configs["mixed-port"] || configs.port || 0))
      setIfChanged("allowLan", configs["allow-lan"] === true)
      setIfChanged("ipv6", configs.ipv6 === true)
      setIfChanged("logLevel", String(configs["log-level"] || ""))
      setIfChanged("unifiedDelay", configs["unified-delay"] === true)
      setIfChanged("findProcessMode", String(configs["find-process-mode"] || ""))
      var tun = configs.tun || {}
      setIfChanged("tunEnabled", tun.enable === true)
      setIfChanged("tunStack", String(tun.stack || ""))
      setIfChanged("tunDevice", String(tun.device || ""))
      setIfChanged("tunAutoRoute", tun["auto-route"] === true)
      var hijack = tun["dns-hijack"]
      setIfChanged("tunDnsHijack", hijack && hijack.length ? hijack.join(", ") : "")
      setIfChanged("sniffing", configs.sniffing === true)
      setIfChanged("geodataMode", configs["geodata-mode"] === true)
      setIfChanged("geoAutoUpdate", configs["geo-auto-update"] === true)
      setIfChanged("socksPort", Number(configs["socks-port"] || 0))
      setIfChanged("redirPort", Number(configs["redir-port"] || 0))
      setIfChanged("tproxyPort", Number(configs["tproxy-port"] || 0))
      setIfChanged("httpPort", Number(configs.port || 0))
    }

    if (data.proxies && data.proxies.proxies) {
      var nextProxies = data.proxies.proxies
      var global = nextProxies["GLOBAL"]
      var ordered = []
      var seen = {}
      if (global && global.all) {
        for (var i = 0; i < global.all.length; i++) {
          var name = global.all[i]
          if (isGroupName(nextProxies, name) && !seen[name]) {
            ordered.push(name)
            seen[name] = true
          }
        }
      }
      // Anything the core exposes but GLOBAL does not list (hidden groups,
      // provider-backed groups) still belongs in the list.
      for (var key in nextProxies) {
        if (key === "GLOBAL" || seen[key] || !isGroupName(nextProxies, key)) continue
        ordered.push(key)
        seen[key] = true
      }

      var stamp = proxiesUiStamp(nextProxies, ordered)
      if (stamp !== lastProxiesStamp) {
        lastProxiesStamp = stamp
        proxies = nextProxies
        if (!sameStringList(groupNames, ordered)) groupNames = ordered
      }

      var skipType = {
        Selector: true, URLTest: true, Fallback: true, LoadBalance: true, Relay: true,
        Direct: true, Reject: true, RejectDrop: true, Pass: true, PassRule: true,
        Compatible: true, Dns: true
      }
      var nodes = 0
      for (var proxyName in nextProxies) {
        var kind = String(nextProxies[proxyName].type || "")
        if (!skipType[kind]) nodes++
      }
      setIfChanged("nodeCount", nodes)
    }

    setIfChanged("connected", true)
    setIfChanged("lastError", "")
  }

  function isGroupName(map, name) {
    var p = map ? map[name] : undefined
    if (!p) return false
    return ["Selector", "URLTest", "Fallback", "LoadBalance", "Relay"].indexOf(p.type) >= 0
  }

  function applyProviders(raw) {
    providersLoading = false
    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return
    }

    proxyProviders = []

    var ruleList = []
    var ruleSource = data.providers || (data.rules && data.rules.providers) || {}
    for (var ruleName in ruleSource) {
      var r = ruleSource[ruleName]
      ruleList.push({
        name: ruleName,
        behavior: String(r.behavior || ""),
        format: String(r.format || ""),
        vehicleType: String(r.vehicleType || ""),
        count: Number(r.ruleCount || 0),
        updatedAt: String(r.updatedAt || "")
      })
    }
    ruleList.sort(function(a, b) { return a.name.localeCompare(b.name) })
    var stamp = ""
    for (var i = 0; i < ruleList.length; i++) {
      var item = ruleList[i]
      stamp += item.name + "\x1f" + item.behavior + "\x1f" + item.count + "\x1f" + item.updatedAt + "\x1e"
    }
    if (stamp === lastProvidersStamp) return
    lastProvidersStamp = stamp
    ruleProviders = ruleList
  }

  function applyRules(raw) {
    rulesLoading = false
    if (raw === lastRulesRaw) return
    try {
      var data = JSON.parse(raw)
      var next = data.rules || []
      lastRulesRaw = raw
      rules = next
      setIfChanged("ruleCount", next.length)
    } catch (e) {
      // Leave the previous list in place rather than blanking the page.
    }
  }

  function applyConnections(raw) {
    connectionsLoading = false
    try {
      var data = JSON.parse(raw)
      var list = data.connections || []
      var rows = []
      var bytes = {}
      var idents = []
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        var meta = c.metadata || {}
        var chains = c.chains || []
        var id = String(c.id || "")
        var host = String(meta.host || meta.destinationIP || "") + ":" + String(meta.destinationPort || "")
        var process = String(meta.process || "")
        var chain = chains.slice().reverse().join(" / ")
        var rule = String(c.rule || "") + (c.rulePayload ? "(" + c.rulePayload + ")" : "")
        bytes[id] = { upload: Number(c.upload || 0), download: Number(c.download || 0) }
        idents.push(id + "\x1f" + host + "\x1f" + process + "\x1f" + chain + "\x1f" + rule)
        rows.push({
          id: id,
          host: host,
          process: process,
          network: String(meta.network || "").toUpperCase(),
          type: String(meta.type || ""),
          start: String(c.start || ""),
          // The core lists the chain innermost-first; read it the way the
          // request actually travels.
          chain: chain,
          rule: rule
        })
      }
      rows.sort(function(a, b) { return b.start.localeCompare(a.start) })
      idents.sort()
      var ident = idents.join("\x1e")
      connectionBytes = bytes
      if (ident !== lastConnIdent) {
        lastConnIdent = ident
        connections = rows
      }
    } catch (e) {
      // Same as rules: a failed poll should not clear a good list.
    }
  }

  // --- writes --------------------------------------------------------------

  // One queue, one process. Mutations are cheap and ordering matters (a mode
  // switch followed by a node switch must not race), so they run serially.
  property var actionQueue: []

  function enqueue(args, note, kind) {
    var queue = actionQueue.slice()
    queue.push({ args: args, note: note || "", kind: kind || "" })
    actionQueue = queue
    runNextAction()
  }

  function runNextAction() {
    if (actionProc.running || actionQueue.length === 0) return
    var queue = actionQueue.slice()
    var next = queue.shift()
    actionQueue = queue
    if (next.note) notice = next.note
    actionProc.actionKind = next.kind || ""
    if (next.kind === "reload") configReloading = true
    actionProc.command = ["/usr/bin/bash", runner].concat(next.args)
    actionProc.running = true
  }

  function selectNode(group, name) {
    if (!ready) return
    // Optimistic: the row highlights immediately, the next poll confirms it.
    var current = proxies[group]
    if (current) {
      var copy = {}
      for (var key in proxies) copy[key] = proxies[key]
      var updated = {}
      for (var field in current) updated[field] = current[field]
      updated.now = name
      copy[group] = updated
      proxies = copy
    }
    enqueue(["put", "/proxies/" + encode(group), JSON.stringify({ name: name })],
            t("switchedTo", group, name))
  }

  function setMode(value) {
    if (!ready || ["rule", "global", "direct"].indexOf(value) < 0) return
    mode = value
    enqueue(["patch", "/configs", JSON.stringify({ mode: value })], t("modeTo", modeLabel))
  }

  function closeConnection(id) {
    if (!ready || !id) return
    enqueue(["delete", "/connections/" + encode(id)], "")
  }

  function closeAllConnections() {
    if (!ready) return
    enqueue(["delete", "/connections"], t("closedAll"))
  }

  function updateRuleProvider(name) {
    if (!ready) return
    enqueue(["put", "/providers/rules/" + encode(name)], t("updatingRules", name))
  }

  function applyConfigInfo(raw) {
    configLoading = false
    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return
    }
    if (data.error) {
      setIfChanged("lastError", String(data.error))
      return
    }
    setIfChanged("configPath", String(data.path || ""))
    setIfChanged("configSize", Number(data.size || 0))
    setIfChanged("configMtime", Number(data.mtime || 0))
    setIfChanged("dnsEnabled", data.dnsEnable === true)
    setIfChanged("dnsListen", String(data.dnsListen || ""))
    setIfChanged("dnsMode", String(data.dnsMode || ""))
    setIfChanged("dnsFakeIp", String(data.dnsFakeIp || ""))
  }

  function actionErrorMessage(raw) {
    var text = String(raw || "").trim()
    if (text === "") return ""
    try {
      var data = JSON.parse(text)
      if (data && data.message) return String(data.message)
      if (data && data.error) return String(data.error)
    } catch (e) {
      return text
    }
    return ""
  }

  function reloadConfig() {
    if (!ready || configReloading) return
    if (configPath === "") {
      notice = t("noConfigPath")
      return
    }
    configReloading = true
    enqueue(["put", "/configs?force=true", JSON.stringify({ path: configPath })],
            t("reloadingConfig"), "reload")
  }

  function openConfig() {
    if (!ready) return
    enqueue(["open-config"], t("openingConfig"), "open")
  }

  // --- latency probes ------------------------------------------------------

  // Kept off the mutation queue: a group probe can take the full timeout, and
  // blocking a node switch behind it would feel broken.
  readonly property string testUrl: "http://www.gstatic.com/generate_204"
  readonly property int testTimeout: 5000
  property var testQueue: []

  function enqueueTest(name, isGroupTest) {
    markTesting(name, true)
    var queue = testQueue.slice()
    queue.push({ name: name, group: isGroupTest })
    testQueue = queue
    runNextTest()
  }

  function runNextTest() {
    if (testProc.running || testQueue.length === 0) return
    var queue = testQueue.slice()
    var next = queue.shift()
    testQueue = queue
    testProc.pendingName = next.name
    testProc.pendingGroup = next.group
    var path = (next.group ? "/group/" : "/proxies/") + encode(next.name)
      + "/delay?timeout=" + testTimeout + "&url=" + encodeURIComponent(testUrl)
    testProc.command = ["/usr/bin/bash", runner, "get", path]
    testProc.running = true
  }

  function testNode(name) {
    if (!ready || isTesting(name)) return
    enqueueTest(name, false)
  }

  function testGroup(name) {
    if (!ready || isTesting(name)) return
    enqueueTest(name, true)
  }

  function applyDelayResult(raw) {
    var name = testProc.pendingName
    markTesting(name, false)

    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return
    }

    var next = {}
    for (var key in delays) next[key] = delays[key]

    if (testProc.pendingGroup) {
      // Group probes answer with { nodeName: delayMs, ... }.
      for (var node in data) {
        if (node === "message") continue
        next[node] = Number(data[node])
      }
    } else if (data.delay !== undefined) {
      next[name] = Number(data.delay)
    } else {
      // { "message": "..." } means the probe failed; 0 renders as timeout.
      next[name] = 0
    }

    delays = next
  }

  // --- lifecycle -----------------------------------------------------------

  onReadyChanged: {
    if (!ready) return
    endpointProc.running = true
    langProc.running = true
    refresh(true)
  }

  onActiveChanged: {
    if (active) {
      refresh()
      refreshPage()
    }
  }

  onPageChanged: {
    if (active) refreshPage()
  }

  Timer {
    interval: root.active ? 2000 : 30000
    running: root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    running: root.ready && root.active && root.page === "connections"
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshConnections()
  }

  Process {
    id: langProc
    command: ["/usr/bin/bash", root.runner, "lang"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.language === "zh" || data.language === "en")
            root.language = String(data.language)
        } catch (e) {
          // Keep the English default.
        }
      }
    }
  }

  Process {
    id: langSetProc
    command: ["/usr/bin/bash", root.runner, "set-lang", "en"]
  }

  Process {
    id: endpointProc
    command: ["/usr/bin/bash", root.runner, "endpoint"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.endpointTarget = String(data.target || "")
          root.endpointTransport = String(data.transport || "")
          root.endpointSource = String(data.source || "")
        } catch (e) {
          // Endpoint info is cosmetic; core polling reports real failures.
        }
      }
    }
  }

  Process {
    id: coreProc
    command: ["/usr/bin/bash", root.runner, "core"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCore(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.lastError === "") {
        root.connected = false
        root.lastError = root.t("connectFailed")
      }
    }
  }

  Process {
    id: configInfoProc
    command: ["/usr/bin/bash", root.runner, "configinfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyConfigInfo(text)
    }
    onExited: root.configLoading = false
  }

  Process {
    id: providersProc
    command: ["/usr/bin/bash", root.runner, "get", "/providers/rules"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProviders(text)
    }
    onExited: root.providersLoading = false
  }

  Process {
    id: rulesProc
    command: ["/usr/bin/bash", root.runner, "get", "/rules"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRules(text)
    }
    onExited: root.rulesLoading = false
  }

  Process {
    id: connectionsProc
    command: ["/usr/bin/bash", root.runner, "get", "/connections"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyConnections(text)
    }
    onExited: root.connectionsLoading = false
  }

  Process {
    id: actionProc
    property string actionKind: ""
    stdout: StdioCollector {
      id: actionOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var err = root.actionErrorMessage(actionOut.text)
      var kind = actionProc.actionKind
      root.configReloading = false
      if (exitCode !== 0 || err !== "") {
        root.notice = err !== "" ? err : root.t("actionFailed")
      } else if (kind === "reload") {
        root.notice = root.t("configReloaded")
      } else if (kind === "open") {
        root.notice = root.t("editorOpened")
      }
      root.runNextAction()
      root.refresh(true)
      if (root.page === "connections") root.refreshConnections()
      else if (root.page === "config" || kind === "reload") {
        root.refreshConfigInfo()
        root.refreshProviders()
        root.refreshRules()
      }
    }
  }

  Process {
    id: testProc
    property string pendingName: ""
    property bool pendingGroup: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDelayResult(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.markTesting(testProc.pendingName, false)
      root.runNextTest()
    }
  }

  // Line-delimited JSON, one line per second, only while the panel is open.
  Process {
    id: trafficProc
    running: root.ready && root.active
    command: ["/usr/bin/bash", root.runner, "stream", "/traffic"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var data = JSON.parse(line)
          root.setIfChanged("upSpeed", Number(data.up || 0))
          root.setIfChanged("downSpeed", Number(data.down || 0))
          if (data.upTotal !== undefined) root.setIfChanged("upTotal", Number(data.upTotal))
          if (data.downTotal !== undefined) root.setIfChanged("downTotal", Number(data.downTotal))
        } catch (e) {
          // Partial line during core restart — the next tick recovers.
        }
      }
    }
  }

  Process {
    id: memoryProc
    running: root.ready && root.active
    command: ["/usr/bin/bash", root.runner, "stream", "/memory"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var data = JSON.parse(line)
          if (Number(data.inuse) > 0) root.setIfChanged("memInuse", Number(data.inuse))
        } catch (e) {
          // Same as traffic.
        }
      }
    }
  }

  IpcHandler {
    target: "io.github.lijiawei0305-pixel.mihomo.service"

    function state(): string {
      return JSON.stringify({
        connected: root.connected,
        version: root.version,
        mode: root.mode,
        endpoint: root.endpointTarget,
        transport: root.endpointTransport,
        groups: root.groupNames,
        up: root.upSpeed,
        down: root.downSpeed
      })
    }

    function refresh(): void { root.refresh(true) }
    function mode(value: string): void { root.setMode(value) }
    function select(group: string, name: string): void { root.selectNode(group, name) }
    function reload(): void { root.reloadConfig() }
  }
}
