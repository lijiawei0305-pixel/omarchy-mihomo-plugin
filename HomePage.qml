import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family

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

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: "首页"
    subtitle: {
      if (!svc) return ""
      if (!svc.connected) return svc.lastError !== "" ? svc.lastError : "未连接"
      return "mihomo " + svc.version + " · " + svc.endpointTransport + " · " + svc.endpointTarget
    }
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: "立即刷新"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      onClicked: if (root.svc) root.svc.refresh()
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

      // --- 当前节点 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg

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
              text: root.leafNode !== "" ? root.leafNode : "无可用节点"
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
              tooltipText: "测试该节点延迟"
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              enabled: root.leafNode !== ""
              onClicked: root.svc.testNode(root.leafNode)
            }
          }
        }

        Dropdown {
          width: parent.width
          label: "代理组"
          foreground: root.fg
          fontFamily: root.fontFamily
          options: root.groups
          value: root.activeGroup
          onChanged: function(v) { root.selectedGroup = v }
        }

        Dropdown {
          width: parent.width
          label: "节点"
          foreground: root.fg
          fontFamily: root.fontFamily
          enabled: root.groupProxy !== null && String(root.groupProxy.type) === "Selector"
          opacity: enabled ? 1.0 : 0.55
          options: root.svc && root.activeGroup !== "" ? root.svc.nodesOf(root.activeGroup) : []
          value: root.groupNow
          onChanged: function(v) {
            if (v !== root.groupNow) root.svc.selectNode(root.activeGroup, v)
          }
        }

        Text {
          width: parent.width
          visible: root.groupProxy !== null && String(root.groupProxy.type) !== "Selector"
          text: "该组是 " + (root.groupProxy ? root.groupProxy.type : "") + "，节点由内核按延迟自动选择。"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }
      }

      // --- 网络设置 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: "网络设置"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: "混合端口"
          value: root.svc && root.svc.mixedPort > 0 ? String(root.svc.mixedPort) : "未启用"
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: "虚拟网卡 (TUN)"
          value: root.svc && root.svc.tunEnabled
            ? "已启用 · " + root.svc.tunDevice + " · " + root.svc.tunStack
            : "已关闭"
          valueColor: root.svc && root.svc.tunEnabled ? Color.accent : Util.alpha(root.fg, 0.75)
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: "局域网连接"
          value: root.svc && root.svc.allowLan ? "允许" : "禁止"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: "IPv6"
          value: root.svc && root.svc.ipv6 ? "开启" : "关闭"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        InfoRow {
          width: parent.width
          label: "进程匹配 / 日志"
          value: (root.svc ? root.svc.findProcessMode : "") + " · " + (root.svc ? root.svc.logLevel : "")
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: "这些值来自内核当前配置，只读。改动请编辑配置文件，再到配置页点重载。"
          color: Util.alpha(root.fg, 0.42)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }
      }

      // --- 代理模式 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: "代理模式"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        ModeSwitch {
          svc: root.svc
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: root.svc && root.svc.mode === "global"
            ? "全局：所有流量都走 GLOBAL 组选中的节点，规则不生效。"
            : root.svc && root.svc.mode === "direct"
              ? "直连：所有流量绕过代理，等同于临时关闭。"
              : "规则：按配置文件里的规则分流，日常使用的默认模式。"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          renderType: Text.NativeRendering
        }
      }

      // --- 流量统计 --------------------------------------------------------

      Card {
        width: parent.width
        foreground: root.fg

        PanelSectionHeader {
          text: "流量统计"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          SpeedCell {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰁝"
            caption: "上传"
            value: root.svc ? root.svc.fmtSpeed(root.svc.upSpeed) : "--"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          SpeedCell {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰁅"
            caption: "下载"
            value: root.svc ? root.svc.fmtSpeed(root.svc.downSpeed) : "--"
            foreground: root.fg
            fontFamily: root.fontFamily
          }
        }

        InfoRow {
          width: parent.width
          label: "累计上传 / 下载"
          value: root.svc
            ? root.svc.fmtBytes(root.svc.upTotal) + "  /  " + root.svc.fmtBytes(root.svc.downTotal)
            : "--"
          foreground: root.fg
          fontFamily: root.fontFamily
          valueBold: true
        }

        InfoRow {
          width: parent.width
          label: "内核内存占用"
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
