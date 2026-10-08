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

  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) return url.substring(7).replace(/\/$/, "")
    return (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/io.github.lijiawei0305-pixel.mihomo"
  }
  readonly property string runner: pluginDir + "/bin/mihomo-ctl"
  readonly property bool ready: runner !== ""
  readonly property string managerRunner: pluginDir + "/bin/mihomo-manager"
  readonly property string setupRunner: pluginDir + "/bin/mihomo-setup"

  // Profile operations have their own queue. Subscription requests can take up
  // to 30 seconds and must never block node/mode/system-proxy actions.
  property var profiles: []
  property string activeProfile: ""
  property string activeProfileName: ""
  property bool profileLoading: false
  property bool profileMutating: false
  property string profileError: ""
  property string managerFailureMessage: ""
  property bool managerInstalled: false
  property bool managerChecking: false
  property bool managerInstalling: false
  property string setupState: "checking"
  property string setupMessage: ""
  property string setupBinaryPath: ""
  property string setupCoreHome: ""
  property string setupServicePath: ""
  property bool setupLoading: false
  property bool setupManagerPending: false
  property bool tunPreflightLoading: false
  property bool tunPreflightTarget: false
  property bool tunPreflightIssue: false
  property bool tunFixLoading: false
  property bool tunOwnershipPromptVisible: false
  property bool tunAdoptionTarget: false
  property var managerSettings: ({})
  property bool managerSettingsLoading: false
  property bool managerSettingsMutating: false
  property var pendingManagerSettings: ({})
  property var diagnostics: []
  property bool diagnosticsLoading: false
  property string profileSourceId: ""
  property string profileSourceText: ""
  property var profileSourceCallback: null
  property string profileURL: ""
  property var profileURLCallback: null
  property string profileURLRequestId: ""
  property int profileURLRequestSerial: 0
  property bool profileURLLoading: false
  property string profileRuntimeText: ""
  property bool profileRuntimeLoading: false
  property var profileRuntimeCallback: null
  property string profileOverrideText: ""
  property bool profileOverrideLoading: false
  property var profileOverrideCallback: null
  property string globalOverrideText: ""
  property bool globalOverrideEmpty: true
  property bool globalOverrideLoading: false
  property var globalOverrideCallback: null
  property var overrideSaveCallback: null
  property bool overrideSavePending: false
  property bool profileSourceLoading: false

  property var customRules: []
  property bool customRulesLoading: false
  property bool bindingRequired: false
  property var bindingRequiredCandidates: []
  property string bindingRequiredProfileId: ""
  property string bindingRequiredPolicy: ""
  property bool bindingCandidatesLoading: false
  property var pendingManagerActionAfterBinding: null

  // Set by the panel. Drives poll cadence and the streaming subscriptions.
  property bool active: false
  property string page: "home"

  property bool connected: false
  property bool hadConnection: false
  property bool managerReconcilePending: false
  property bool managerInitialReconcileDone: false
  // onReadyChanged and onCompleted can both see the initial ready=true.
  property bool readyWorkStarted: false
  property bool coreRefreshPending: false
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
  property bool tunAutoDetect: false
  property bool tunStrictRoute: false

  // OS-level system proxy. Not a core setting — Clash Verge keeps this on the
  // GUI side and writes gsettings / the session environment itself.
  property bool sysproxyEnabled: false
  property string sysproxyHost: ""
  property int sysproxyPort: 0
  property string sysproxyBackend: ""
  property bool sysproxyWanted: false
  property bool sysproxyWritePending: false
  property bool mixedPortSeen: false
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
  property string lastConnBytesStamp: ""
  property string lastRulesRaw: ""
  property string lastProvidersStamp: ""

  readonly property var skipNodeType: ({
    Selector: true, URLTest: true, Fallback: true, LoadBalance: true, Relay: true,
    Direct: true, Reject: true, RejectDrop: true, Pass: true, PassRule: true,
    Compatible: true, Dns: true
  })

  readonly property int pollInterval: !active ? 30000
    : (page === "home" || page === "proxies") ? 2000
    : 5000

  property string notice: ""
  property string language: "en"

  I18n {
    id: i18n
    language: root.language
  }

  // System Proxy writes HTTP, HTTPS, and SOCKS to one endpoint. A regular
  // HTTP or SOCKS listener is not a valid fallback for that contract.
  readonly property int systemProxyPort: mixedPort > 0 ? mixedPort : 0

  readonly property string captureMode: tunEnabled ? "tun"
    : (sysproxyEnabled ? "sysproxy" : "off")

  // The normal path is complete only when the core is reachable, the helper is
  // available, and a profile has been selected. Raw-config users can still use
  // the panel, but the home page uses this flag to present a short setup path.
  readonly property bool onboardingComplete: connected && managerInstalled && activeProfile !== ""

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

  function profileNameFor(id) {
    for (var i = 0; i < profiles.length; i++) {
      if (String(profiles[i].id || "") === String(id || ""))
        return String(profiles[i].name || id || "")
    }
    return String(id || "")
  }

  function applyProfiles(raw) {
    profileLoading = false
    try {
      var data = JSON.parse(raw)
      if (!data.ok) { profileError = String(data.error || t("actionFailed")); return }
      var payload = data.data
      if (payload && payload.profiles !== undefined) {
        profiles = payload.profiles
        activeProfile = String(payload.activeProfile || "")
        activeProfileName = profileNameFor(activeProfile)
        syncManagedConfigInfo()
        syncSetupState()
      } else if (Array.isArray(payload)) {
        profiles = payload
      }
      profileError = ""
    } catch (e) {
      profileError = t("parseError")
    }
  }

  function refreshProfiles() {
    if (!ready || !managerInstalled || profileProc.running) return
    profileLoading = true
    profileProc.command = ["/usr/bin/bash", managerRunner, "status"]
    profileProc.running = true
  }

  function refreshGlobalOverride() {
    if (!ready || !managerInstalled || globalOverrideProc.running) return
    globalOverrideLoading = true
    globalOverrideProc.running = true
  }

  function refreshManagerSettings() {
    if (!ready || !managerInstalled || managerSettingsProc.running) return
    managerSettingsLoading = true
    managerSettingsProc.running = true
  }

  function refreshSetupStatus() {
    if (!ready || setupStatusProc.running) return
    setupStatusProc.running = true
  }

  function applySetupStatus(raw) {
    try {
      var data = JSON.parse(raw)
      setupState = String(data.state || (data.ok ? "ready" : "attention"))
      if (setupState === "needs-core") setupMessage = t("setupNeedsCore")
      else if (setupState === "needs-setup") setupMessage = t("setupNeedsSetup")
      else if (setupState === "controller-unavailable") setupMessage = t("setupControllerUnavailable")
      else if (setupState === "ready") setupMessage = t("setupReady")
      else if (setupState === "service-conflict") setupMessage = t("setupServiceConflict")
      else if (setupState === "start-failed") setupMessage = t("setupStartFailed")
      else setupMessage = String(data.message || "")
      setupBinaryPath = String(data.binaryPath || "")
      setupCoreHome = String(data.coreHome || "")
      setupServicePath = String(data.service || "")
    } catch (e) {
      setupState = "attention"
      setupMessage = t("parseError")
    }
    syncSetupState()
  }

  function syncSetupState() {
    if (setupLoading || setupManagerPending) return
    if (connected) {
      if (managerInstalled) {
        setupState = activeProfile === "" ? "needs-profile" : "ready"
        setupMessage = activeProfile === "" ? t("setupAddProfile") : t("setupReady")
      } else if (setupState !== "needs-core" && setupState !== "controller-unavailable") {
        setupState = "needs-setup"
        setupMessage = t("setupManagerPending")
      }
    }
  }

  function setup() {
    if (!ready || setupLoading || setupProc.running) return
    setupLoading = true
    setupManagerPending = false
    setupState = "setting-up"
    setupMessage = t("setupInProgress")
    setupProc.running = true
  }

  function finishSetup() {
    setupLoading = false
    setupManagerPending = false
    setupState = connected && managerInstalled
      ? (activeProfile === "" ? "needs-profile" : "ready")
      : "starting"
    setupMessage = connected && managerInstalled ? t("setupReady") : t("setupInProgress")
    refreshSetupStatus()
    refresh(true)
    if (managerInstalled) {
      refreshProfiles()
      refreshManagerSettings()
    }
  }

  function setManagerSetting(key, value) {
    if (!ready || !managerInstalled || !key || value === undefined || value === null) return
    var pending = {}
    for (var field in pendingManagerSettings) pending[field] = pendingManagerSettings[field]
    pending[key] = String(value)
    pendingManagerSettings = pending
    settingsBatchTimer.restart()
  }

  function flushManagerSettings() {
    var patch = ["settings", "patch"]
    for (var key in pendingManagerSettings) {
      patch.push(key)
      patch.push(String(pendingManagerSettings[key]))
    }
    pendingManagerSettings = ({})
    if (patch.length === 2) return
    managerSettingsMutating = true
    enqueueManager(patch)
  }

  function managerActionPending(kind) {
    if (managerCurrentAction.length > 0 && managerCurrentAction[0] === kind) return true
    for (var i = 0; i < managerActionQueue.length; i++) {
      if (managerActionQueue[i].length > 0 && managerActionQueue[i][0] === kind) return true
    }
    return false
  }

  function reconcileProfiles() {
    if (!ready || !managerInstalled || managerReconcilePending) return
    // Reconcile is a manager mutation: serialize it with profile updates and
    // selections so a core restart cannot race a queued subscription apply.
    managerReconcilePending = true
    enqueueManager(["reconcile"])
    if (managerCurrentAction.length === 0 && managerActionQueue.length === 0)
      managerReconcilePending = false
  }

  function maybeInitialReconcile() {
    if (!ready || !managerInstalled || !connected || managerInitialReconcileDone) return
    // The manager status probe and the first controller probe are independent
    // processes. Mark this edge once and let the manager queue serialize the
    // actual restore with any profile action already in flight.
    managerInitialReconcileDone = true
    reconcileProfiles()
  }

  function enqueueManager(args) {
    if (!ready || !managerInstalled) return
    var key = JSON.stringify(args)
    if (managerCurrentAction.length > 0 && JSON.stringify(managerCurrentAction) === key) return
    for (var i = 0; i < managerActionQueue.length; i++) {
      if (JSON.stringify(managerActionQueue[i]) === key) return
    }
    var queue = managerActionQueue.slice()
    queue.push(args)
    managerActionQueue = queue
    runNextManagerAction()
  }

  function markManagerFailure(raw) {
    var message = root.actionErrorMessage(raw)
    root.profileError = message !== "" ? message : root.t("actionFailed")
  }

  function runNextManagerAction() {
    if (managerProc.running || managerActionQueue.length === 0) return
    var queue = managerActionQueue.slice()
    var args = queue.shift()
    managerActionQueue = queue
    managerCurrentAction = args
    managerFailureMessage = ""
    managerOutput = ""
    profileMutating = true
    notice = t("profileActionInProgress")
    managerProc.command = ["/usr/bin/bash", managerRunner].concat(args)
    managerProc.running = true
  }

  function installManager(forSetup) {
    if (!ready || managerInstalling || installProc.running) return
    if (forSetup === true) setupManagerPending = true
    managerInstalling = true
    installProc.running = true
  }

  function importCurrent(name) {
    enqueueManager(["profile", "import-current", "--name", name || "Local Config"])
  }

  function addProfile(url, name, intervalSec) {
    var interval = intervalSec === undefined ? 21600 : Number(intervalSec)
    enqueueManager(["profile", "add", "--url", url, "--name", name,
                    "--update-interval", String(interval), "--activate-if-empty"])
  }
  function selectProfile(id) { enqueueManager(["profile", "select", id]) }
  function updateProfile(id, viaProxy) {
    var args = ["profile", "update", id]
    if (viaProxy) args.push("--via-proxy")
    enqueueManager(args)
  }
  function updateProfileViaProxy(id) { updateProfile(id, true) }
  function deleteProfile(id) { enqueueManager(["profile", "delete", id]) }
  function renameProfile(id, name) { enqueueManager(["profile", "rename", id, name]) }
  function setProfileURL(id, url) { enqueueManager(["profile", "set-url", id, url]) }
  function readProfileSource(id, callback) {
    if (!ready || !managerInstalled || sourceProc.running) return
    profileSourceId = id
    profileSourceText = ""
    profileSourceCallback = callback
    profileSourceLoading = true
    sourceProc.command = ["/usr/bin/bash", managerRunner, "profile", "source", id]
    sourceProc.running = true
  }

  function readProfileURL(id, callback) {
    if (!ready || !managerInstalled || urlProc.running) return
    profileURL = ""
    profileURLRequestSerial += 1
    profileURLRequestId = id + ":" + String(profileURLRequestSerial)
    profileURLCallback = callback
    profileURLLoading = true
    urlProc.command = ["/usr/bin/bash", managerRunner, "profile", "url", id]
    urlProc.running = true
  }

  function readProfileRuntime(id, callback) {
    if (!ready || !managerInstalled || runtimeProc.running) return
    profileRuntimeLoading = true
    profileRuntimeCallback = callback
    runtimeProc.command = ["/usr/bin/bash", managerRunner, "profile", "runtime", id]
    runtimeProc.running = true
  }

  function readProfileOverride(id, callback) {
    if (!ready || !managerInstalled || overrideProc.running) return
    profileOverrideLoading = true
    profileOverrideCallback = callback
    overrideProc.command = ["/usr/bin/bash", managerRunner, "profile", "override", id]
    overrideProc.running = true
  }

  function readGlobalOverride(callback) {
    if (!ready || !managerInstalled || globalOverrideProc.running) return
    globalOverrideText = ""
    globalOverrideLoading = true
    globalOverrideCallback = callback
    globalOverrideProc.running = true
  }

  function saveOverride(globalScope, id, text, callback) {
    if (!ready || !managerInstalled || overrideSavePending) return
    overrideSavePending = true
    overrideSaveCallback = callback
    var args = ["override"]
    if (globalScope) {
      args = args.concat(["global", "set", "--text", String(text || "")])
    } else if (id) {
      args = args.concat(["profile", id, "set", "--text", String(text || "")])
    } else {
      overrideSavePending = false
      overrideSaveCallback = null
      return
    }
    enqueueManager(args)
  }

  function openGlobalOverride() {
    if (!ready || !managerInstalled || overrideOpenProc.running) return
    overrideOpenProc.command = ["/usr/bin/bash", managerRunner, "override", "open-global"]
    overrideOpenProc.running = true
  }

  function openProfileOverride(id) {
    if (!ready || !managerInstalled || overrideOpenProc.running || !id) return
    overrideOpenProc.command = ["/usr/bin/bash", managerRunner, "override", "open-profile", id]
    overrideOpenProc.running = true
  }

  // Recompile/apply is intentionally kept on the manager queue. It must not
  // race a subscription update or a profile selection.
  function recompileActiveProfile() {
    if (!managerInstalled || activeProfile === "") return
    enqueueManager(["config", "apply", activeProfile])
  }

  function refreshCustomRules() {
    if (!ready || !managerInstalled || customRulesProc.running) return
    customRulesLoading = true
    customRulesProc.running = true
  }

  function addCustomRule(domain, matchType, policyName) {
    enqueueManager(["rule", "add", "--domain", String(domain || ""),
                    "--match", String(matchType || "domain-suffix"),
                    "--policy", String(policyName || "proxy")])
  }

  function updateCustomRule(id, domain, matchType, policyName) {
    var args = ["rule", "update", id]
    if (domain !== undefined && domain !== null) args.push("--domain", String(domain))
    if (matchType !== undefined && matchType !== null) args.push("--match", String(matchType))
    if (policyName !== undefined && policyName !== null) args.push("--policy", String(policyName))
    enqueueManager(args)
  }

  function deleteCustomRule(id) { enqueueManager(["rule", "delete", id]) }
  function enableCustomRule(id) { enqueueManager(["rule", "enable", id]) }
  function disableCustomRule(id) { enqueueManager(["rule", "disable", id]) }

  function setPolicyBinding(profileId, policyName, target) {
    if (!profileId || !policyName || !target) return
    enqueueManager(["policy", "binding", "set", profileId, policyName, target])
  }

  function openProxyBindingEditor() {
    if (!ready || !managerInstalled || activeProfile === "" || bindingCandidatesProc.running) return
    bindingCandidatesLoading = true
    bindingCandidatesProc.command = ["/usr/bin/bash", managerRunner,
                                     "policy", "binding", "candidates", activeProfile]
    bindingCandidatesProc.running = true
  }

  function clearBindingRequired() {
    pendingManagerActionAfterBinding = null
    bindingRequired = false
    bindingRequiredCandidates = []
    bindingRequiredProfileId = ""
    bindingRequiredPolicy = ""
  }

  // --- reads ---------------------------------------------------------------

  function refresh(forceProxies) {
    if (!ready) return
    if (coreProc.running) {
      if (forceProxies === true) coreRefreshPending = true
      return
    }
    coreRefreshPending = false
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
    if (page === "profiles") {
      refreshProfiles()
      refreshGlobalOverride()
      refreshCustomRules()
    } else if (page === "config") refreshConfig()
    else if (page === "rules") {
      refreshRules()
      refreshCustomRules()
    }
    else if (page === "connections") refreshConnections()
    else if (page === "diagnostics") refreshDiagnostics()
    else refresh()
  }

  function refreshDiagnostics() {
    if (!ready || !managerInstalled || diagnosticsProc.running) return
    diagnosticsLoading = true
    diagnosticsProc.running = true
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

  function markDisconnected(message) {
    var wasConnected = connected
    connected = false
    lastError = message || t("connectFailed")
    if (wasConnected) {
      // Preserve the fact that a live connection existed. The next successful
      // edge is therefore a reconnect and must reconcile the active profile.
      hadConnection = true
    }
  }

  function applyCore(raw) {
    var data
    try {
      data = JSON.parse(raw)
    } catch (e) {
      markDisconnected(t("parseError"))
      return
    }

    if (data.error) {
      markDisconnected(String(data.error))
      return
    }

    if (data.version) setIfChanged("version", String(data.version.version || ""))

    var configs = data.configs
    if (configs) {
      setIfChanged("mode", String(configs.mode || "rule"))
      setIfChanged("mixedPort", Number(configs["mixed-port"] || 0))
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
      setIfChanged("tunAutoDetect", tun["auto-detect-interface"] === true)
      setIfChanged("tunStrictRoute", tun["strict-route"] === true)
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

      var nodes = 0
      for (var proxyName in nextProxies) {
        var kind = String(nextProxies[proxyName].type || "")
        if (!skipNodeType[kind]) nodes++
      }
      setIfChanged("nodeCount", nodes)
    }

    if (data.sysproxy) applySysproxy(data.sysproxy)

    setIfChanged("connected", true)
    setIfChanged("lastError", "")
    maybeRefreshSysproxyPort()
  }

  function applySysproxy(data) {
    if (!data || sysproxyWritePending) return
    setIfChanged("sysproxyEnabled", data.enabled === true)
    setIfChanged("sysproxyHost", String(data.host || ""))
    setIfChanged("sysproxyPort", Number(data.port || 0))
    setIfChanged("sysproxyBackend", String(data.backend || ""))
    setIfChanged("sysproxyWanted", data.wanted === true)
  }

  // Clash Verge rewrites the OS proxy when mixed-port changes while system
  // proxy is on. Skip the first poll so we do not surprise an existing session.
  function maybeRefreshSysproxyPort() {
    var port = systemProxyPort
    if (!mixedPortSeen) {
      if (port > 0) mixedPortSeen = true
      return
    }
    if (sysproxyWritePending || !sysproxyWanted || !sysproxyEnabled) return
    if (port <= 0) {
      // A runtime that loses mixed-port must not leave the desktop pointed at
      // a dead endpoint. The ctl-side preflight also protects the transition
      // itself from races.
      enqueue(["sysproxy", "off"], "", "sysproxy")
      return
    }
    if (port === sysproxyPort) return
    enqueue(["sysproxy", "on", "127.0.0.1", String(port)], "", "sysproxy")
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

  function applyCustomRules(raw) {
    customRulesLoading = false
    try {
      var data = JSON.parse(raw)
      if (!data.ok) return
      var next = data.data || []
      if (!Array.isArray(next) && next.rules !== undefined) next = next.rules
      if (Array.isArray(next)) customRules = next
    } catch (e) {}
  }

  function applyConnections(raw) {
    connectionsLoading = false
    try {
      var data = JSON.parse(raw)
      var list = data.connections || []
      var rows = []
      var bytes = {}
      var idents = []
      var byteParts = []
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        var meta = c.metadata || {}
        var chains = c.chains || []
        var id = String(c.id || "")
        var domain = String(meta.host || meta.destinationIP || "")
        var host = domain + ":" + String(meta.destinationPort || "")
        var process = String(meta.process || "")
        var chain = chains.slice().reverse().join(" / ")
        var rule = String(c.rule || "") + (c.rulePayload ? "(" + c.rulePayload + ")" : "")
        var upload = Number(c.upload || 0)
        var download = Number(c.download || 0)
        bytes[id] = { upload: upload, download: download }
        idents.push(id + "\x1f" + domain + "\x1f" + host + "\x1f" + process + "\x1f" + chain + "\x1f" + rule)
        byteParts.push(id + "=" + upload + "," + download)
        rows.push({
          id: id,
          host: host,
          domain: domain,
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
      byteParts.sort()
      var ident = idents.join("\x1e")
      var byteStamp = byteParts.join("\x1e")
      if (byteStamp !== lastConnBytesStamp) {
        lastConnBytesStamp = byteStamp
        connectionBytes = bytes
      }
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
  property var managerActionQueue: []
  property var managerCurrentAction: []
  property string managerOutput: ""

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

  // Off clears both. The Home buttons toggle each path on its own.
  function setCaptureMode(modeName) {
    if (!ready) return
    if (modeName === "sysproxy") {
      setSysproxy(true)
    } else if (modeName === "tun") {
      setTun(true)
    } else {
      if (sysproxyEnabled) setSysproxy(false)
      if (tunEnabled) setTun(false)
    }
  }

  function setSysproxy(enabled) {
    if (!ready) return
    if (enabled) {
      var port = systemProxyPort
      if (port <= 0) {
        notice = t("sysproxyNoPort")
        return
      }
      sysproxyEnabled = true
      sysproxyWanted = true
      sysproxyWritePending = true
      enqueue(["sysproxy", "on", "127.0.0.1", String(port)], t("sysproxyOn"), "sysproxy")
    } else {
      sysproxyEnabled = false
      sysproxyWanted = false
      sysproxyWritePending = true
      enqueue(["sysproxy", "off"], t("sysproxyOff"), "sysproxy")
    }
  }

  function requestTunPreflight(enabled) {
    if (!enabled) {
      applyTunEnabled(false)
      return
    }
    if (activeProfile !== "" && managerSettingsLoading) {
      notice = t("settingsApplying")
      return
    }
    if (tunPreflightLoading) {
      notice = t("tunCheckInProgress")
      return
    }
    tunPreflightTarget = true
    tunPreflightLoading = true
    notice = t("tunCheckInProgress")
    var stack = tunStack !== "" ? tunStack : "gvisor"
    if (managerInstalled && managerRunner !== "") {
      tunPreflightProc.command = ["/usr/bin/bash", managerRunner, "doctor", "tun",
                                  "--stack", stack]
    } else if (setupRunner !== "") {
      tunPreflightProc.command = ["/usr/bin/bash", setupRunner, "preflight", "--stack", stack]
    } else {
      tunPreflightLoading = false
      tunPreflightTarget = false
      applyTunEnabled(true)
      return
    }
    tunPreflightProc.running = true
  }

  function applyTunPreflight(raw) {
    var checks = []
    try {
      var data = JSON.parse(raw)
      checks = Array.isArray(data.checks) ? data.checks : []
    } catch (e) {
      tunPreflightLoading = false
      tunPreflightIssue = true
      notice = t("tunPreflightBlocked")
      return
    }
    if (checks.length === 0) {
      tunPreflightLoading = false
      tunPreflightIssue = true
      notice = t("tunPreflightBlocked")
      return
    }
    for (var i = 0; i < checks.length; i++) {
      var check = checks[i]
      // Raw Config mode used to enable TUN without getcap. Missing libcap is
      // not proof the core lacks permission (it may be root), so do not block.
      if (check.id === "tunCapability" && check.messageKey === "diagnosticGetcapUnavailable") continue
      if ((check.id === "tunCapability" || check.id === "firewallTunCompatibility")
          && check.status !== "ok") {
        tunPreflightLoading = false
        tunPreflightIssue = true
        diagnostics = checks
        notice = check.id === "tunCapability"
          ? t("tunPermissionRequired")
          : t("tunPreflightBlocked")
        return
      }
    }
    tunPreflightLoading = false
    tunPreflightIssue = false
    var target = tunPreflightTarget
    tunPreflightTarget = false
    applyTunEnabled(target)
  }

  function setTun(enabled) {
    if (!ready) return
    if (enabled) {
      requestTunPreflight(true)
      return
    }
    tunPreflightTarget = false
    if (tunPreflightLoading) {
      tunPreflightLoading = false
      tunPreflightProc.running = false
    }
    applyTunEnabled(false)
  }

  function fixTunPermission() {
    if (!ready || !managerInstalled || tunFixLoading || tunFixProc.running) return
    tunPreflightTarget = true
    tunFixLoading = true
    notice = t("fixingTunPermission")
    tunFixProc.running = true
  }

  function applyTunEnabled(enabled) {
    if (!ready) return
    if (activeProfile !== "") {
      if (!managerInstalled) {
        notice = t("setupInProgress")
        return
      }
      if (managerSettingsLoading || managerSettingsMutating) {
        notice = t("settingsApplying")
        return
      }
      var management = String(managerSettings.tunManagement || "managed")
      if (management === "managed") {
        tunEnabled = enabled
        setManagerSetting("tun-enable", enabled ? "true" : "false")
        notice = enabled ? t("tunOnNotice") : t("tunOffNotice")
        return
      }
      tunAdoptionTarget = enabled
      tunOwnershipPromptVisible = true
      return
    }
    tunEnabled = enabled
    var tun = {
      enable: enabled,
      "auto-route": true,
      "auto-detect-interface": true
    }
    // Preserve an explicit system/mixed stack in raw-config mode. The manager
    // default is gVisor, but enabling TUN must not silently rewrite a user's
    // existing Mihomo stack choice.
    tun.stack = tunStack !== "" ? tunStack : "gvisor"
    if (tunDevice !== "") tun.device = tunDevice
    if (tunDnsHijack !== "") tun["dns-hijack"] = tunDnsHijack.split(", ")
    else tun["dns-hijack"] = ["any:53"]
    enqueue(["patch", "/configs", JSON.stringify({ tun: tun })],
            enabled ? t("tunOnNotice") : t("tunOffNotice"))
  }

  function cancelTunAdoption() {
    tunOwnershipPromptVisible = false
  }

  function adoptTunControl() {
    if (!ready || !managerInstalled) return
    tunOwnershipPromptVisible = false
    setManagerSetting("tun-management", "managed")
    setManagerSetting("tun-enable", tunAdoptionTarget ? "true" : "false")
    setManagerSetting("tun-stack", tunStack !== "" ? tunStack : "gvisor")
    setManagerSetting("tun-auto-route", tunAutoRoute ? "true" : "false")
    setManagerSetting("tun-auto-detect-interface", tunAutoDetect ? "true" : "false")
    setManagerSetting("tun-strict-route", tunStrictRoute ? "true" : "false")
    setManagerSetting("tun-dns-hijack", tunDnsHijack)
    tunEnabled = tunAdoptionTarget
    notice = tunAdoptionTarget ? t("tunOnNotice") : t("tunOffNotice")
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
    if (activeProfile !== "") {
      syncManagedConfigInfo()
      return
    }
    setIfChanged("configPath", String(data.path || ""))
    setIfChanged("configSize", Number(data.size || 0))
    setIfChanged("configMtime", Number(data.mtime || 0))
    setIfChanged("dnsEnabled", data.dnsEnable === true)
    setIfChanged("dnsListen", String(data.dnsListen || ""))
    setIfChanged("dnsMode", String(data.dnsMode || ""))
    setIfChanged("dnsFakeIp", String(data.dnsFakeIp || ""))
    syncManagedConfigInfo()
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
    return text
  }

  function applyManagerError(raw, failedAction) {
    bindingRequired = false
    bindingRequiredCandidates = []
    bindingRequiredProfileId = ""
    bindingRequiredPolicy = ""
    try {
      var data = JSON.parse(String(raw || ""))
      if (data.code === "binding_required" || data.code === "binding_unavailable") {
        bindingRequired = true
        bindingRequiredCandidates = data.candidates || []
        bindingRequiredProfileId = String(data.profileId || activeProfile || "")
        bindingRequiredPolicy = String(data.policy || "proxy")
        var pending = failedAction ? failedAction.slice() : null
        // A first profile can be stored as inactive when its Proxy policy
        // needs a human group choice. Retry selection after binding instead
        // of repeating the download and creating a second profile.
        if (pending && pending.length >= 2 && pending[0] === "profile"
            && pending[1] === "add" && bindingRequiredProfileId !== "")
          pending = ["profile", "select", bindingRequiredProfileId]
        pendingManagerActionAfterBinding = pending
      } else {
        pendingManagerActionAfterBinding = null
      }
    } catch (e) {
      pendingManagerActionAfterBinding = null
    }
  }

  function syncManagedConfigInfo() {
    if (!managerInstalled || activeProfile === "") return
    if (managerRuntimeInfoProc.running) return
    managerRuntimeInfoProc.command = ["/usr/bin/bash", managerRunner,
                                      "profile", "runtime", activeProfile]
    managerRuntimeInfoProc.running = true
  }

  function reloadConfig() {
    if (!ready || configReloading) return
    if (activeProfile !== "") {
      configReloading = true
      enqueueManager(["config", "apply", activeProfile])
      return
    }
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

  function startReadyWork() {
    // A second call while the first startup is still armed would set
    // Process.targetRunning and run endpoint, language, setup, and profile
    // checks again when the first process exits.
    if (!ready || readyWorkStarted) return
    readyWorkStarted = true
    managerInitialReconcileDone = false
    endpointProc.running = true
    langProc.running = true
    setupStatusProc.running = true
    managerChecking = true
    profileCheckProc.running = true
    refresh(true)
  }

  Component.onCompleted: {
    ServiceStore.instance = root
    if (ready) startReadyWork()
  }

  onConnectedChanged: {
    if (!connected) {
      if (setupState === "ready") {
        setupState = "controller-unavailable"
        setupMessage = lastError !== "" ? lastError : t("setupControllerUnavailable")
      }
      return
    }
    var wasConnected = hadConnection
    hadConnection = true
    if (wasConnected) reconcileProfiles()
    else maybeInitialReconcile()
    syncSetupState()
  }

  onManagerInstalledChanged: syncSetupState()
  onActiveProfileChanged: syncSetupState()

  onReadyChanged: {
    if (!ready) {
      readyWorkStarted = false
      return
    }
    startReadyWork()
  }

  onActiveChanged: {
    if (active) {
      // Re-detect a Mihomo binary that the user installed while the panel was
      // closed. Setup status is intentionally independent of the controller
      // heartbeat.
      refreshSetupStatus()
      refresh()
      refreshPage()
    }
  }

  onPageChanged: {
    if (active) refreshPage()
  }

  // A light background tick keeps inactive subscriptions fresh without tying
  // it to the visible-page core poll cadence.
  Timer {
    interval: 15 * 60 * 1000
    running: root.ready && root.managerInstalled
    repeat: true
    onTriggered: root.updateDue()
  }

  function updateDue() {
    if (!managerInstalled || managerActionQueue.length > 0) return
    enqueueManager(["profile", "update-due"])
  }

  Timer {
    interval: root.pollInterval
    running: root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Let a short burst of edits become one atomic manager update. This avoids
  // compiling, validating, and applying the active profile once per field.
  Timer {
    id: settingsBatchTimer
    interval: 400
    repeat: false
    onTriggered: root.flushManagerSettings()
  }

  Timer {
    interval: 3000
    running: root.ready && root.active && root.page === "connections"
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshConnections()
  }

  Process {
    id: setupStatusProc
    command: ["/usr/bin/bash", root.setupRunner, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySetupStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.setupLoading) {
        root.setupState = "attention"
        root.setupMessage = root.t("setupStatusUnavailable")
      }
    }
  }

  Process {
    id: setupProc
    command: ["/usr/bin/bash", root.setupRunner, "setup"]
    stdout: StdioCollector {
      id: setupOut
      waitForEnd: true
      onStreamFinished: root.applySetupStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.setupLoading = false
        root.setupManagerPending = false
        if (root.setupMessage === "") root.setupMessage = root.t("setupFailed")
        root.setupState = root.setupState === "needs-core" ? "needs-core" : "attention"
        root.refreshSetupStatus()
        return
      }
      if (root.managerInstalled) root.finishSetup()
      else root.installManager(true)
    }
  }

  Process {
    id: installProc
    command: ["/usr/bin/bash", root.pluginDir + "/bin/install-manager"]
    stdout: StdioCollector {
      id: installOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.managerInstalling = false
      if (exitCode !== 0 && root.setupManagerPending) {
        root.setupLoading = false
        root.setupManagerPending = false
        root.setupState = "attention"
        root.setupMessage = root.actionErrorMessage(installOut.text) || root.t("managerInstallFailed")
        return
      }
      root.managerChecking = true
      profileCheckProc.running = true
    }
  }

  Process {
    id: profileCheckProc
    command: ["/usr/bin/bash", root.managerRunner, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.managerInstalled = data.ok === true
          if (root.managerInstalled) {
            root.applyProfiles(text)
            root.refreshManagerSettings()
            // Cover the race where manager status finishes before the first
            // successful controller poll. onConnectedChanged covers the other
            // ordering and the reconnect path.
            root.maybeInitialReconcile()
            if (root.page === "diagnostics") root.refreshDiagnostics()
          }
        } catch (e) {
          root.managerInstalled = false
          root.managerInitialReconcileDone = false
        }
      }
    }
    onExited: {
      root.managerChecking = false
      if (exitCode !== 0) {
        root.managerInstalled = false
        root.managerInitialReconcileDone = false
      }
      else if (root.managerInstalled) root.refreshManagerSettings()
      if (root.setupManagerPending) {
        if (exitCode === 0 && root.managerInstalled) root.finishSetup()
        else {
          root.setupLoading = false
          root.setupManagerPending = false
          root.setupState = "attention"
          root.setupMessage = root.t("managerInstallFailed")
        }
      }
    }
  }

  Process {
    id: managerSettingsProc
    command: ["/usr/bin/bash", root.managerRunner, "settings", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.managerSettingsLoading = false
        try {
          var data = JSON.parse(text)
          if (data.ok && data.data) root.managerSettings = data.data
        } catch (e) {}
      }
    }
    onExited: root.managerSettingsLoading = false
  }

  Process {
    id: diagnosticsProc
    command: ["/usr/bin/bash", root.managerRunner, "doctor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.diagnosticsLoading = false
        try {
          var data = JSON.parse(text)
          root.diagnostics = data.checks || []
        } catch (e) {
          root.diagnostics = [{id: "diagnostics", status: "error", message: root.t("parseError")}]
        }
      }
    }
    onExited: root.diagnosticsLoading = false
  }

  Process {
    id: tunPreflightProc
    command: ["/usr/bin/bash", root.managerRunner, "doctor", "tun", "--stack", "gvisor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTunPreflight(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.tunPreflightLoading) {
        root.tunPreflightLoading = false
        root.tunPreflightIssue = true
        root.notice = root.t("tunPreflightBlocked")
      }
    }
  }

  Process {
    id: tunFixProc
    command: ["/usr/bin/bash", root.managerRunner, "doctor", "fix-tun-permission"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.tunFixLoading = false
        try {
          var data = JSON.parse(text)
          if (data.ok === true) {
            root.notice = root.t("tunOnNotice")
            root.tunPreflightIssue = false
            // The repair command restarts plugin-managed Mihomo. Re-run the
            // normal preflight so the original enable intent continues only
            // after the new process has been verified.
            if (root.tunPreflightTarget) root.requestTunPreflight(true)
          } else {
            root.tunPreflightIssue = true
            root.notice = root.actionErrorMessage(text) || root.t("tunPermissionFixFailed")
          }
        } catch (e) {
          root.tunPreflightIssue = true
          root.notice = root.t("tunPermissionFixFailed")
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.tunFixLoading) {
        root.tunFixLoading = false
        root.tunPreflightIssue = true
        root.notice = root.t("tunPermissionFixFailed")
      }
    }
  }

  Process {
    id: profileProc
    command: ["/usr/bin/bash", root.managerRunner, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfiles(text)
    }
    onExited: root.profileLoading = false
  }

  Process {
    id: urlProc
    command: ["/usr/bin/bash", root.managerRunner, "profile", "url", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var requestId = root.profileURLRequestId
        root.profileURLLoading = false
        var value = ""
        try {
          var data = JSON.parse(text)
          value = data.ok ? String(data.url || "") : ""
        } catch (e) {}
        if (requestId !== root.profileURLRequestId || requestId === "") return
        root.profileURL = value
        root.profileURLRequestId = ""
        if (root.profileURLCallback) root.profileURLCallback(value)
        root.profileURLCallback = null
      }
    }
    onExited: {
      root.profileURLLoading = false
      if (root.profileURLRequestId !== "") {
        root.profileURLRequestId = ""
        root.profileURLCallback = null
      }
    }
  }

  Process {
    id: globalOverrideProc
    command: ["/usr/bin/bash", root.managerRunner, "override", "global", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.globalOverrideLoading = false
        try {
          var data = JSON.parse(text)
          root.globalOverrideText = data.ok ? String(data.override || "") : String(data.error || "")
          root.globalOverrideEmpty = data.ok ? data.empty === true : true
        } catch (e) { root.globalOverrideText = root.t("parseError") }
        if (root.globalOverrideCallback) root.globalOverrideCallback(root.globalOverrideText)
        root.globalOverrideCallback = null
      }
    }
    onExited: {
      root.globalOverrideLoading = false
      if (exitCode !== 0) root.globalOverrideCallback = null
    }
  }

  Process {
    id: customRulesProc
    command: ["/usr/bin/bash", root.managerRunner, "rule", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCustomRules(text)
    }
    onExited: root.customRulesLoading = false
  }

  Process {
    id: bindingCandidatesProc
    command: ["/usr/bin/bash", root.managerRunner,
              "policy", "binding", "candidates", ""]
    stdout: StdioCollector {
      id: bindingCandidatesOut
      waitForEnd: true
      onStreamFinished: {
        root.bindingCandidatesLoading = false
        try {
          var data = JSON.parse(String(text || ""))
          if (!data.ok) {
            root.bindingRequired = false
            root.notice = root.actionErrorMessage(text)
            if (root.notice === "") root.notice = root.t("actionFailed")
            return
          }
          var payload = data.data || {}
          var candidates = payload.candidates || data.candidates || []
          if (!Array.isArray(candidates)) candidates = []
          root.bindingRequiredCandidates = candidates
          root.bindingRequiredProfileId = String(payload.profileId || data.profileId || root.activeProfile)
          root.bindingRequiredPolicy = "proxy"
          root.pendingManagerActionAfterBinding = null
          root.bindingRequired = true
        } catch (e) {
          root.bindingRequired = false
          root.notice = root.t("parseError")
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.bindingCandidatesLoading) {
        root.bindingCandidatesLoading = false
        root.bindingRequired = false
        root.notice = root.t("actionFailed")
      }
    }
  }

  Process {
    id: overrideOpenProc
    command: ["/usr/bin/bash", root.managerRunner, "override", "open-global"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (exitCode === 0) root.refreshManagerSettings()
      else root.markManagerFailure("")
    }
  }

  Process {
    id: managerRuntimeInfoProc
    command: ["/usr/bin/bash", root.managerRunner, "profile", "runtime", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.activeProfile === "") return
        try {
          var data = JSON.parse(text)
          if (!data.ok) return
          root.configPath = String(data.path || "")
          root.configSize = Number(data.size || 0)
          root.configMtime = Number(data.mtime || 0)
        } catch (e) {}
      }
    }
  }

  Process {
    id: runtimeProc
    command: ["/usr/bin/bash", root.managerRunner, "profile", "runtime", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.profileRuntimeLoading = false
        try {
          var data = JSON.parse(text)
          root.profileRuntimeText = data.ok ? String(data.runtime || "") : String(data.error || "")
        } catch (e) { root.profileRuntimeText = root.t("parseError") }
        if (root.profileRuntimeCallback) root.profileRuntimeCallback(root.profileRuntimeText)
        root.profileRuntimeCallback = null
      }
    }
    onExited: {
      root.profileRuntimeLoading = false
      if (exitCode !== 0) root.profileRuntimeCallback = null
    }
  }

  Process {
    id: overrideProc
    command: ["/usr/bin/bash", root.managerRunner, "profile", "override", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.profileOverrideLoading = false
        try {
          var data = JSON.parse(text)
          root.profileOverrideText = data.ok ? String(data.override || "") : String(data.error || "")
        } catch (e) { root.profileOverrideText = root.t("parseError") }
        if (root.profileOverrideCallback) root.profileOverrideCallback(root.profileOverrideText)
        root.profileOverrideCallback = null
      }
    }
    onExited: {
      root.profileOverrideLoading = false
      if (exitCode !== 0) root.profileOverrideCallback = null
    }
  }

  Process {
    id: sourceProc
    command: ["/usr/bin/bash", root.managerRunner, "profile", "source", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.profileSourceLoading = false
        try {
          var data = JSON.parse(text)
          root.profileSourceText = data.ok ? String(data.source || "") : String(data.error || "")
          if (root.profileSourceCallback) root.profileSourceCallback(root.profileSourceText)
          root.profileSourceCallback = null
        } catch (e) {
          root.profileSourceText = root.t("parseError")
          if (root.profileSourceCallback) root.profileSourceCallback(root.profileSourceText)
          root.profileSourceCallback = null
        }
      }
    }
    onExited: {
      root.profileSourceLoading = false
      if (exitCode !== 0) root.profileSourceCallback = null
    }
  }

  Process {
    id: managerProc
    command: ["/usr/bin/bash", root.managerRunner, "status"]
    stdout: StdioCollector {
      id: managerOut
      waitForEnd: true
      onStreamFinished: root.managerOutput = text
    }
    onExited: function(exitCode) {
      var finishedAction = root.managerCurrentAction.slice()
      var output = root.managerOutput !== "" ? root.managerOutput : managerOut.text
      var failure = exitCode !== 0 ? root.actionErrorMessage(output) : ""
      if (exitCode !== 0) {
        root.applyManagerError(output, finishedAction)
        if (failure === "") failure = root.t("actionFailed")
        root.managerFailureMessage = failure
        root.profileError = failure
        root.notice = failure
      } else {
        if (finishedAction.length > 0 && finishedAction[0] === "policy") {
          root.bindingRequired = false
          root.bindingRequiredCandidates = []
          root.bindingRequiredProfileId = ""
          root.bindingRequiredPolicy = ""
        }
        root.managerFailureMessage = ""
        root.profileError = ""
        root.notice = root.t("profileActionCompleted")
      }
      if (finishedAction.length > 0 && finishedAction[0] === "override") {
        var saveCallback = root.overrideSaveCallback
        root.overrideSaveCallback = null
        root.overrideSavePending = false
        if (saveCallback) saveCallback(exitCode === 0, exitCode === 0 ? "" : failure)
      }
      root.profileMutating = false
      if (finishedAction.length > 0 && finishedAction[0] === "reconcile") root.managerReconcilePending = false
      if (finishedAction.length > 0 && finishedAction[0] === "config") root.configReloading = false
      root.managerCurrentAction = []
      root.runNextManagerAction()
      if (exitCode === 0 && finishedAction.length > 0 && finishedAction[0] === "policy"
          && root.pendingManagerActionAfterBinding !== null) {
        var pending = root.pendingManagerActionAfterBinding
        root.pendingManagerActionAfterBinding = null
        root.enqueueManager(pending)
      }
      if (finishedAction.length > 0 && finishedAction[0] === "settings")
        root.managerSettingsMutating = root.managerActionPending("settings")
      if (finishedAction.length > 0 && finishedAction[0] === "settings")
        root.refresh(true)
      root.refreshProfiles()
      root.refreshManagerSettings()
      if (finishedAction.length > 0 && (finishedAction[0] === "rule" || finishedAction[0] === "policy"))
        root.refreshCustomRules()
      if (finishedAction.length > 0 && finishedAction[0] === "override") {
        root.refreshGlobalOverride()
        root.refresh(true)
      }
      if (finishedAction.length > 0 && finishedAction[0] === "config") root.refreshConfigInfo()
    }
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
        markDisconnected(root.t("connectFailed"))
      }
      if (root.coreRefreshPending) {
        root.coreRefreshPending = false
        root.refresh(true)
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
      if (kind === "sysproxy") root.sysproxyWritePending = false
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
        capture: root.captureMode,
        sysproxy: root.sysproxyEnabled,
        tun: root.tunEnabled,
        endpoint: root.endpointTarget,
        transport: root.endpointTransport,
        groups: root.groupNames,
        up: root.upSpeed,
        down: root.downSpeed
      })
    }

    function refresh(): void { root.refresh(true) }
    function mode(value: string): void { root.setMode(value) }
    function capture(mode: string): void { root.setCaptureMode(mode) }
    function select(group: string, name: string): void { root.selectNode(group, name) }
    function reload(): void { root.reloadConfig() }
  }
}
