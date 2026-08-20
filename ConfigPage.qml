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

  function portLabel(name, value) {
    return name + " " + (value > 0 ? String(value) : (svc ? svc.t("portOff") : "off"))
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
    subtitle: root.svc && root.svc.configPath !== "" ? root.svc.configPath
      : (root.svc ? root.svc.t("configNotFound") : "")
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
          text: root.svc ? root.svc.t("language") : "Language"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        LanguageSwitch {
          svc: root.svc
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: root.svc ? root.svc.t("languageHint") : ""
          color: Util.alpha(root.fg, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }
      }

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: root.svc ? root.svc.t("configFile") : "Config file"
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
          color: Util.alpha(root.fg, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }
      }

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: root.svc ? root.svc.t("kernelOverview") : "Core overview"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: "DNS"
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
            return root.portLabel("mixed", root.svc.mixedPort)
              + "  ·  " + root.portLabel("socks", root.svc.socksPort)
              + "  ·  " + root.portLabel("http", root.svc.httpPort)
              + "  ·  " + root.portLabel("redir", root.svc.redirPort)
              + "  ·  " + root.portLabel("tproxy", root.svc.tproxyPort)
          }
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: "TUN"
          value: {
            if (!root.svc) return "--"
            if (!root.svc.tunEnabled) return root.svc.t("tunOff")
            return root.svc.tunDevice + " · " + root.svc.tunStack
              + " · auto-route " + (root.svc.tunAutoRoute ? root.svc.t("autoRouteOn") : root.svc.t("autoRouteOff"))
              + (root.svc.tunDnsHijack !== "" ? " · hijack " + root.svc.tunDnsHijack : "")
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
              + "  ·  " + (root.svc.geodataMode ? "dat" : "mmdb")
              + "  ·  " + (root.svc.geoAutoUpdate ? root.svc.t("geoAutoOn") : root.svc.t("geoAutoOff"))
          }
          foreground: root.fg
          fontFamily: root.fontFamily
        }
      }

      PanelSectionHeader {
        text: root.svc ? root.svc.t("ruleProviders") : "Rule providers"
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.svc ? root.svc.ruleProviders : []

        Rectangle {
          required property var modelData
          width: column.width
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
                ? root.svc.t("ruleProviderMeta", modelData.behavior, modelData.count, root.fmtUpdated(modelData.updatedAt))
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
