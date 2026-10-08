import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

// Config = the handwritten yaml the core is running, plus rule-providers.
// Node lists live on the proxy page; this page is the file and the rule sets.
Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family
  property bool customizeNetwork: false
  property bool showAdvancedNetwork: false
  property bool showCoreOverview: false
  property string mixedPortDraft: ""

  function fmtUpdated(stamp) {
    var text = String(stamp || "")
    if (text === "" || text.indexOf("0001-01-01") === 0)
      return svc ? svc.t("neverFetched") : "Never fetched"
    var parsed = new Date(text)
    if (isNaN(parsed.getTime())) return text
    return Qt.formatDateTime(parsed, "yyyy-MM-dd hh:mm")
  }

  function fmtMtime(epoch) {
    if (!epoch) return "--"
    return Qt.formatDateTime(new Date(Number(epoch) * 1000), "yyyy-MM-dd hh:mm")
  }

  function fmtSize(bytes) {
    if (!svc || !bytes) return "--"
    return svc.fmtBytes(bytes)
  }

  function statsLine() {
    if (!svc) return ""
    return svc.t("statsLine", svc.nodeCount, svc.groupNames.length,
                 svc.ruleCount, svc.ruleProviders.length)
  }

  function managerValue(section, key, fallback) {
    var settings = root.svc ? root.svc.managerSettings : null
    var group = settings ? settings[section] : null
    return group && group[key] !== undefined ? group[key] : fallback
  }

  function managerBool(section, key, fallback) {
    return managerValue(section, key, fallback) === true
  }

  function managerList(section, key, fallback) {
    var value = managerValue(section, key, fallback || [])
    return Array.isArray(value) ? value.join(", ") : String(value || "")
  }

  function managerIsManaged(section) {
    if (!root.svc) return false
    var key = section === "dns" ? "dnsManagement" : "tunManagement"
    return String(root.svc.managerSettings[key] || "managed") === "managed"
  }

  function portLabel(key, fallback, value) {
    var label = root.svc ? root.svc.t(key) : fallback
    return label + " " + (value > 0 ? String(value) : (root.svc ? root.svc.t("portOff") : "off"))
  }

  function scrollBy(delta) {
    var flick = scrollArea.contentItem
    if (!flick) return
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height),
                                          flick.contentY + delta))
  }

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: root.svc ? root.svc.t("configTitle") : "Config"
    subtitle: root.svc ? root.svc.t("runningConfiguration") : "Running configuration"
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: root.svc ? root.svc.t("refreshConfig") : "Reload the file info and rule providers"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc !== null && !root.svc.configLoading && !root.svc.providersLoading
      onClicked: root.svc.refreshConfig()
    }
  }

  Rectangle {
    id: headerRule
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    height: 1
    color: Util.alpha(root.fg, 0.12)
  }

  ScrollView {
    id: scrollArea
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: headerRule.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(14)
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

    Column {
      id: column
      width: scrollArea.availableWidth
      spacing: Style.space(12)

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: root.svc ? root.svc.t("runningConfiguration") : "Running configuration"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("activeProfile") : "Active profile"
          value: root.svc && root.svc.activeProfile !== "" ? (root.svc.activeProfileName || root.svc.activeProfile) : (root.svc ? root.svc.t("rawConfigMode") : "Raw Config Mode")
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("kernelLoaded") : "Loaded by the core"
          value: root.statsLine()
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: root.svc && root.svc.configReloading
              ? root.svc.t("reloading") : (root.svc ? root.svc.t("reload") : "Reload config")
            tooltipText: root.svc ? root.svc.t("reloadTip") : ""
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: root.svc !== null && root.svc.connected && !root.svc.configReloading
            onClicked: root.svc.reloadConfig()
          }

          Button {
            text: root.svc ? root.svc.t("openEditor") : "Open in editor"
            tooltipText: root.svc ? root.svc.t("openEditorTip") : ""
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: root.svc !== null && root.svc.configPath !== ""
            onClicked: root.svc.openConfig()
          }
        }

        Text {
          width: parent.width
          text: root.svc ? root.svc.t("reloadHint") : ""
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }

        Button {
          text: root.showCoreOverview
            ? (root.svc ? root.svc.t("hideCoreOverview") : "Hide core details")
            : (root.svc ? root.svc.t("advancedCoreDetails") : "Advanced core details")
          onClicked: root.showCoreOverview = !root.showCoreOverview
        }
      }

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.showCoreOverview
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("kernelOverview") : "Core overview"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("path") : "Path"
          value: root.svc && root.svc.configPath !== "" ? root.svc.configPath : "--"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("sizeMtime") : "Size / modified"
          value: root.fmtSize(root.svc ? root.svc.configSize : 0)
            + "  ·  " + root.fmtMtime(root.svc ? root.svc.configMtime : 0)
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("dns") : "DNS"
          value: {
            if (!root.svc) return "--"
            var parts = [root.svc.dnsEnabled ? root.svc.t("dnsOn") : root.svc.t("dnsOff")]
            if (root.svc.dnsMode !== "") parts.push(root.svc.dnsMode)
            if (root.svc.dnsListen !== "") parts.push(root.svc.dnsListen)
            if (root.svc.dnsFakeIp !== "") parts.push(root.svc.dnsFakeIp)
            return parts.join(" · ")
          }
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("listenPorts") : "Listen ports"
          value: {
            if (!root.svc) return "--"
            return root.portLabel("portMixed", "Mixed", root.svc.mixedPort)
              + "  ·  " + root.portLabel("portSocks", "SOCKS", root.svc.socksPort)
              + "  ·  " + root.portLabel("portHttp", "HTTP", root.svc.httpPort)
              + "  ·  " + root.portLabel("portRedir", "Redir", root.svc.redirPort)
              + "  ·  " + root.portLabel("portTproxy", "TProxy", root.svc.tproxyPort)
          }
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("tun") : "TUN"
          value: {
            if (!root.svc) return "--"
            if (!root.svc.tunEnabled) return root.svc.t("tunOff")
            var parts = []
            if (root.svc.tunDevice !== "") parts.push(root.svc.tunDevice)
            if (root.svc.tunStack !== "") parts.push(root.svc.tunStack)
            parts.push(root.svc.t("tunAutoRoute") + ": " + (root.svc.tunAutoRoute ? root.svc.t("autoRouteOn") : root.svc.t("autoRouteOff")))
            parts.push(root.svc.t("tunAutoDetect") + ": " + (root.svc.tunAutoDetect ? root.svc.t("enabled") : root.svc.t("disabled")))
            if (root.svc.tunDnsHijack !== "") parts.push(root.svc.t("tunDNSHijack") + ": " + root.svc.tunDnsHijack)
            return parts.join(" · ")
          }
          valueColor: root.svc && root.svc.tunEnabled ? Color.accent : Util.alpha(root.fg, 0.75)
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("sniffGeo") : "Sniffer / geo"
          value: {
            if (!root.svc) return "--"
            return (root.svc.sniffing ? root.svc.t("sniffOn") : root.svc.t("sniffOff"))
              + "  ·  " + root.svc.t(root.svc.geodataMode ? "geodataDat" : "geodataMmdb")
              + "  ·  " + (root.svc.geoAutoUpdate ? root.svc.t("geoAutoOn") : root.svc.t("geoAutoOff"))
          }
          foreground: root.fg
          fontFamily: root.fontFamily
        }
      }

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.svc && root.svc.managerInstalled
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("networkSettings") : "Network"
          foreground: root.fg
          fontFamily: root.fontFamily
        }
        Text {
          width: parent.width
          visible: !root.customizeNetwork
          height: visible ? implicitHeight : 0
          text: root.svc ? root.svc.t("networkAutomatic") : "Automatic"
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }
        Button {
          text: root.customizeNetwork
            ? (root.svc ? root.svc.t("hideNetworkCustomization") : "Hide customization")
            : (root.svc ? root.svc.t("customizeNetwork") : "Customize")
          onClicked: {
            root.customizeNetwork = !root.customizeNetwork
            if (!root.customizeNetwork) root.showAdvancedNetwork = false
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(12)
          visible: root.customizeNetwork
          height: visible ? implicitHeight : 0

          Text {
            width: (parent.width - Style.space(12)) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.svc ? root.svc.t("mixedPort") : "Mixed port"
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          TextField {
            id: mixedPortField
            width: (parent.width - Style.space(12)) / 2
            placeholderText: "7890"
            foreground: root.fg
            accent: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            enabled: root.svc && !root.svc.managerSettingsMutating
            onTextChanged: if (activeFocus) root.mixedPortDraft = text
            onEditingFinished: {
              root.svc.setManagerSetting("mixed-port", text)
              root.mixedPortDraft = ""
            }
            Binding {
              target: mixedPortField
              property: "text"
              value: String(root.managerValue("network", "mixedPort", 7890))
              when: !mixedPortField.activeFocus && root.mixedPortDraft === ""
            }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(12)
          visible: root.customizeNetwork
          height: visible ? implicitHeight : 0
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("dnsManagement") : "DNS"
            options: [{label: root.svc ? root.svc.t("managed") : "Managed", value: "managed"}, {label: root.svc ? root.svc.t("inherit") : "Inherit", value: "inherit"}]
            value: root.svc && root.svc.managerSettings.dnsManagement ? root.svc.managerSettings.dnsManagement : "managed"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: !root.svc.managerSettingsMutating
            onChanged: root.svc.setManagerSetting("dns-management", value)
          }
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunManagement") : "TUN"
            options: [{label: root.svc ? root.svc.t("managed") : "Managed", value: "managed"}, {label: root.svc ? root.svc.t("inherit") : "Inherit", value: "inherit"}]
            value: root.svc && root.svc.managerSettings.tunManagement ? root.svc.managerSettings.tunManagement : "managed"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: !root.svc.managerSettingsMutating
            onChanged: root.svc.setManagerSetting("tun-management", value)
          }
        }

        Text {
          width: parent.width
          text: {
            if (!root.svc) return ""
            var dnsManaged = root.managerIsManaged("dns")
            var tunManaged = root.managerIsManaged("tun")
            if (dnsManaged && tunManaged) return root.svc.t("networkSettingsManagedHint")
            if (!dnsManaged && !tunManaged) return root.svc.t("networkSettingsInheritHint")
            return root.svc.t("networkSettingsMixedHint")
          }
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }

        Button {
          visible: root.customizeNetwork
          height: visible ? implicitHeight : 0
          text: root.showAdvancedNetwork
            ? (root.svc ? root.svc.t("hideAdvancedNetwork") : "Hide advanced network")
            : (root.svc ? root.svc.t("advancedNetwork") : "Advanced network")
          onClicked: root.showAdvancedNetwork = !root.showAdvancedNetwork
        }

        Column {
          id: advancedNetwork
          width: parent.width
          visible: root.customizeNetwork && root.showAdvancedNetwork
          height: visible ? implicitHeight : 0
          spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(12)
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("dnsEnabled") : "DNS enabled"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("dns", "enable", true) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("dns-enable", value) }
          }
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("dnsIPv6") : "DNS IPv6"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("dns", "ipv6", false) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("dns-ipv6", value) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("dnsEnhancedMode") : "DNS mode"
            options: [
              {label: root.svc ? root.svc.t("dnsModeFakeIP") : "Fake-IP", value: "fake-ip"},
              {label: root.svc ? root.svc.t("dnsModeRedirHost") : "Redir-host", value: "redir-host"}
            ]
            value: String(root.managerValue("dns", "enhancedMode", "fake-ip"))
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("dns-enhanced-mode", value) }
          }
          TextField {
            id: dnsFakeIpRange
            width: (parent.width - Style.space(12)) / 2
            placeholderText: root.svc ? root.svc.t("dnsFakeIPRange") : "Fake-IP range"
            foreground: root.fg
            accent: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
            onEditingFinished: root.svc.setManagerSetting("dns-fake-ip-range", text)
            Binding { target: dnsFakeIpRange; property: "text"; value: String(root.managerValue("dns", "fakeIPRange", "198.18.0.1/16")); when: !dnsFakeIpRange.activeFocus }
          }
        }

        Text {
          width: parent.width
          text: root.svc ? root.svc.t("listHint") : ""
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.42)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }

        TextField {
          id: dnsDefaultNameserver
          width: parent.width
          placeholderText: root.svc ? root.svc.t("dnsDefaultNameserver") : "Bootstrap nameservers"
          foreground: root.fg
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
          onEditingFinished: root.svc.setManagerSetting("dns-default-nameserver", text)
          Binding { target: dnsDefaultNameserver; property: "text"; value: root.managerList("dns", "defaultNameserver", []); when: !dnsDefaultNameserver.activeFocus }
        }
        TextField {
          id: dnsNameserver
          width: parent.width
          placeholderText: root.svc ? root.svc.t("dnsNameserver") : "Nameservers"
          foreground: root.fg
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
          onEditingFinished: root.svc.setManagerSetting("dns-nameserver", text)
          Binding { target: dnsNameserver; property: "text"; value: root.managerList("dns", "nameserver", []); when: !dnsNameserver.activeFocus }
        }
        TextField {
          id: dnsProxyNameserver
          width: parent.width
          placeholderText: root.svc ? root.svc.t("dnsProxyNameserver") : "Proxy nameservers"
          foreground: root.fg
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
          onEditingFinished: root.svc.setManagerSetting("dns-proxy-server-nameserver", text)
          Binding { target: dnsProxyNameserver; property: "text"; value: root.managerList("dns", "proxyServerNameserver", []); when: !dnsProxyNameserver.activeFocus }
        }
        TextField {
          id: dnsFakeIpFilter
          width: parent.width
          placeholderText: root.svc ? root.svc.t("dnsFakeIPFilter") : "Fake-IP filter"
          foreground: root.fg
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          enabled: root.svc && root.managerIsManaged("dns") && !root.svc.managerSettingsMutating
          onEditingFinished: root.svc.setManagerSetting("dns-fake-ip-filter", text)
          Binding { target: dnsFakeIpFilter; property: "text"; value: root.managerList("dns", "fakeIPFilter", []); when: !dnsFakeIpFilter.activeFocus }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunEnabledSetting") : "TUN enabled"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("tun", "enable", false) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("tun-enable", value) }
          }
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunStack") : "TUN stack"
            options: [
              {label: root.svc ? root.svc.t("tunStackGvisor") : "gVisor", value: "gvisor"},
              {label: root.svc ? root.svc.t("tunStackSystem") : "System", value: "system"},
              {label: root.svc ? root.svc.t("tunStackMixed") : "Mixed", value: "mixed"}
            ]
            value: String(root.managerValue("tun", "stack", "gvisor"))
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("tun-stack", value) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunAutoRoute") : "Auto route"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("tun", "autoRoute", true) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("tun-auto-route", value) }
          }
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunAutoDetect") : "Auto-detect interface"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("tun", "autoDetectInterface", true) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("tun-auto-detect-interface", value) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)
          PlainTextDropdown {
            width: (parent.width - Style.space(12)) / 2
            label: root.svc ? root.svc.t("tunStrictRoute") : "Strict route"
            options: [
              {label: root.svc ? root.svc.t("enabled") : "Enabled", value: "true"},
              {label: root.svc ? root.svc.t("disabled") : "Disabled", value: "false"}
            ]
            value: root.managerBool("tun", "strictRoute", false) ? "true" : "false"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onChanged: function(value) { root.svc.setManagerSetting("tun-strict-route", value) }
          }
          TextField {
            id: tunDnsHijack
            width: (parent.width - Style.space(12)) / 2
            placeholderText: root.svc ? root.svc.t("tunDNSHijack") : "DNS hijack"
            foreground: root.fg
            accent: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            enabled: root.svc && root.managerIsManaged("tun") && !root.svc.managerSettingsMutating
            onEditingFinished: root.svc.setManagerSetting("tun-dns-hijack", text)
            Binding { target: tunDnsHijack; property: "text"; value: root.managerList("tun", "dnsHijack", []); when: !tunDnsHijack.activeFocus }
          }
        }

      }

    }

      Column {
        id: advancedProviders
        width: parent.width
        visible: root.showCoreOverview
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)

        PanelSectionHeader {
          text: root.svc ? root.svc.t("ruleProviders") : "Rule providers"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.svc ? root.svc.ruleProviders : []

          Rectangle {
            required property var modelData
            width: advancedProviders.width
          height: Style.space(42)
          radius: Style.cornerRadius
          color: ruleMouse.containsMouse ? Util.alpha(root.fg, 0.06) : Util.alpha(root.fg, 0.03)

          MouseArea {
            id: ruleMouse
            anchors.fill: parent
            hoverEnabled: true
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: ruleUpdate.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: modelData.name
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              text: root.svc
                ? root.svc.t(modelData.count === 1 ? "ruleProviderMetaOne" : "ruleProviderMetaMany", modelData.behavior, modelData.count, root.fmtUpdated(modelData.updatedAt))
                : ""
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }

          PanelActionButton {
            id: ruleUpdate
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰑐"
            tooltipText: root.svc ? root.svc.t("updateRuleSet") : "Fetch this rule provider again"
            foreground: root.fg
            hoverColor: Color.accent
            fontFamily: root.fontFamily
            enabled: modelData.vehicleType !== "Inline"
            onClicked: root.svc.updateRuleProvider(modelData.name)
          }
          }
        }

        Item { width: 1; height: Style.space(4) }
      }
    }
  }
}
