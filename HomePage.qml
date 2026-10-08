import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family
  property var openProfiles: null
  property var openDiagnostics: null

  // Which group the "当前节点" card is showing. Sticky across polls, but falls
  // back to a sensible group whenever the selection disappears from the config.
  property string selectedGroup: ""

  readonly property var groups: {
    var names = svc ? svc.groupNames.slice() : []
    // GLOBAL is only meaningful — and only switchable — in global mode.
    if (svc && svc.mode === "global" && svc.proxyFor("GLOBAL")) names.unshift("GLOBAL")
    return names
  }

  readonly property string activeGroup: {
    if (selectedGroup !== "" && groups.indexOf(selectedGroup) >= 0) return selectedGroup
    // Default to a group the user can actually steer; URLTest groups pick for
    // themselves and would open the card with a dead node dropdown.
    for (var i = 0; i < groups.length; i++) {
      var proxy = svc ? svc.proxyFor(groups[i]) : null
      if (proxy && String(proxy.type) === "Selector") return groups[i]
    }
    return groups.length > 0 ? groups[0] : ""
  }

  readonly property var groupProxy: svc && activeGroup !== "" ? svc.proxyFor(activeGroup) : null
  readonly property string groupNow: groupProxy ? String(groupProxy.now || "") : ""

  // A group's `now` is often another group. Follow it down to the node that
  // actually carries the traffic, keeping the hops for the caption.
  readonly property var chain: {
    var hops = []
    if (!svc || activeGroup === "") return hops
    var cursor = activeGroup
    var guard = 0
    while (cursor && guard < 12) {
      hops.push(cursor)
      var proxy = svc.proxyFor(cursor)
      if (!proxy || !proxy.now) break
      cursor = String(proxy.now)
      guard++
    }
    return hops
  }
  readonly property string leafNode: chain.length > 0 ? chain[chain.length - 1] : ""
  readonly property var leafProxy: svc && leafNode !== "" ? svc.proxyFor(leafNode) : null

  function scrollBy(delta) {
    var flick = scrollArea.contentItem
    if (!flick) return
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height),
                                          flick.contentY + delta))
  }

  ConfirmDialog {
    id: tunAdoptionDialog
    anchors.fill: parent
    z: 100
    opened: root.svc && root.svc.tunOwnershipPromptVisible
    message: root.svc
      ? root.svc.t("tunAdoptionMessage", root.svc.activeProfileName || root.svc.t("activeProfile"))
      : "This profile currently controls TUN. Use panel control?"
    cancelText: root.svc ? root.svc.t("cancel") : "Cancel"
    confirmText: root.svc ? root.svc.t("usePanelControl") : "Use panel control"
    foreground: root.fg
    onCanceled: if (root.svc) root.svc.cancelTunAdoption()
    onConfirmed: if (root.svc) root.svc.adoptTunControl()
  }

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: root.svc ? root.svc.t("homeTitle") : "Home"
    subtitle: {
      if (!svc) return ""
      if (!svc.connected) return svc.lastError !== "" ? svc.lastError : svc.t("disconnected")
      return svc.t("connectedProfile", svc.activeProfileName !== "" ? svc.activeProfileName : svc.t("rawConfigMode"))
    }
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: root.svc ? root.svc.t("refreshNow") : "Refresh now"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: {
        if (!root.svc) return
        root.svc.refreshSetupStatus()
        root.svc.refresh()
      }
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
        visible: root.svc && !root.svc.onboardingComplete
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("setupTitle") : "Get started"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: {
            if (!root.svc) return ""
            if (root.svc.setupLoading) return root.svc.t("setupInProgress")
            if (root.svc.setupState === "needs-core") return root.svc.t("setupNeedsCore")
            if (root.svc.setupState === "needs-profile") return root.svc.t("setupAddProfile")
            if (root.svc.setupMessage !== "") return root.svc.setupMessage
            return root.svc.t("setupNeedsCore")
          }
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }

        Row {
          spacing: Style.space(8)
          Button {
            visible: root.svc && root.svc.setupState !== "needs-core" && root.svc.setupState !== "needs-profile"
            text: root.svc && root.svc.setupLoading ? root.svc.t("settingUp") : root.svc ? root.svc.t("setupMihomo") : "Set up Mihomo"
            enabled: root.svc && !root.svc.setupLoading && !root.svc.managerInstalling
            onClicked: root.svc.setup()
          }
          Button {
            visible: root.svc && root.svc.setupState === "needs-profile" && !root.svc.setupLoading
            text: root.svc.t("addSubscription")
            onClicked: if (root.openProfiles) root.openProfiles()
          }
        }
      }

      // --- 当前节点 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.svc && root.svc.connected
        height: visible ? implicitHeight : 0

        Item {
          width: parent.width
          implicitHeight: Math.max(nodeIcon.implicitHeight, nodeLabels.implicitHeight,
                                   nodeDelay.implicitHeight)

          Text {
            id: nodeIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰖂"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            renderType: Text.NativeRendering
          }

          Column {
            id: nodeLabels
            anchors.left: nodeIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: nodeActions.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: root.leafNode !== "" ? root.leafNode : (root.svc ? root.svc.t("noNode") : "No node available")
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              text: {
                var type = root.leafProxy ? String(root.leafProxy.type || "") : ""
                var udp = root.leafProxy && root.leafProxy.udp ? " · UDP" : ""
                return root.chain.length > 1
                  ? type + udp + "  ←  " + root.chain.slice(0, -1).join(" / ")
                  : type + udp
              }
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }

          Row {
            id: nodeActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            DelayBadge {
              id: nodeDelay
              anchors.verticalCenter: parent.verticalCenter
              svc: root.svc
              proxyName: root.leafNode
              foreground: root.fg
              fontFamily: root.fontFamily
              solid: true
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰓅"
              tooltipText: root.svc ? root.svc.t("testNodeDelay") : "Test this node's latency"
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              enabled: root.leafNode !== ""
              onClicked: root.svc.testNode(root.leafNode)
            }
          }
        }

        PlainTextDropdown {
          width: parent.width
          label: root.svc ? root.svc.t("proxyGroup") : "Proxy group"
          foreground: root.fg
          fontFamily: root.fontFamily
          options: root.groups
          value: root.activeGroup
          onChanged: function(v) { root.selectedGroup = v }
        }

        PlainTextDropdown {
          width: parent.width
          label: root.svc ? root.svc.t("node") : "Node"
          foreground: root.fg
          fontFamily: root.fontFamily
          enabled: root.groupProxy !== null && String(root.groupProxy.type) === "Selector"
          options: root.svc && root.activeGroup !== "" ? root.svc.nodesOf(root.activeGroup) : []
          value: root.groupNow
          onChanged: function(v) {
            if (v !== root.groupNow) root.svc.selectNode(root.activeGroup, v)
          }
        }

        Text {
          width: parent.width
          visible: root.groupProxy !== null && String(root.groupProxy.type) !== "Selector"
          text: root.svc ? root.svc.t("autoSelectHint", root.groupProxy ? root.groupProxy.type : "") : ""
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }
      }

      // --- 流量接管：系统代理 / TUN ----------------------------------------

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.svc && root.svc.connected
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("captureTitle") : "Traffic capture"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        CaptureSwitch {
          svc: root.svc
          foreground: root.fg
          fontFamily: root.fontFamily
        }

      }

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.svc && root.svc.tunPreflightIssue
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("needsAttention") : "Needs attention"
          foreground: Color.urgent
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: root.svc ? root.svc.t("tunPreflightBlocked") : "TUN needs attention."
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }

        Button {
          text: root.svc ? root.svc.t("openDiagnostics") : "Open Diagnostics"
          onClicked: if (root.openDiagnostics) root.openDiagnostics()
        }
      }

      // --- 流量统计 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg
        visible: root.svc && root.svc.connected
        height: visible ? implicitHeight : 0

        PanelSectionHeader {
          text: root.svc ? root.svc.t("traffic") : "Traffic"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          SpeedCell {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰁝"
            caption: root.svc ? root.svc.t("upload") : "Upload"
            value: root.svc ? root.svc.fmtSpeed(root.svc.upSpeed) : "--"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          SpeedCell {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰁅"
            caption: root.svc ? root.svc.t("download") : "Download"
            value: root.svc ? root.svc.fmtSpeed(root.svc.downSpeed) : "--"
            foreground: root.fg
            fontFamily: root.fontFamily
          }
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("trafficTotal") : "Total up / down"
          value: root.svc
            ? root.svc.fmtBytes(root.svc.upTotal) + "  /  " + root.svc.fmtBytes(root.svc.downTotal)
            : "--"
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: root.svc ? root.svc.t("kernelMemory") : "Core memory"
          value: root.svc ? root.svc.fmtBytes(root.svc.memInuse) : "--"
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }
      }

      Item { width: 1; height: Style.space(4) }
    }
  }

  component SpeedCell: Rectangle {
    id: cell
    property string glyph: ""
    property string caption: ""
    property string value: ""
    property color foreground: Color.popups.text
    property string fontFamily: Style.font.family

    implicitHeight: cellColumn.implicitHeight + Style.space(18)
    radius: Style.cornerRadius
    color: Util.alpha(foreground, 0.04)

    Column {
      id: cellColumn
      anchors.centerIn: parent
      width: parent.width - Style.space(16)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: cell.value
        textFormat: Text.PlainText
        color: cell.foreground
        font.family: cell.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        text: cell.glyph + " " + cell.caption
        textFormat: Text.PlainText
        color: Util.alpha(cell.foreground, 0.5)
        font.family: cell.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.8
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }
    }
  }
}
