import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family

  // Group name -> expanded. Plain object so a poll that rebuilds the group
  // list does not collapse whatever the user had open.
  property var expanded: ({})

  // GLOBAL only matters in global mode; in rule mode it is noise.
  readonly property var visibleGroups: {
    var out = []
    if (!svc) return out
    var names = svc.groupNames
    for (var i = 0; i < names.length; i++) {
      var proxy = svc.proxyFor(names[i])
      if (proxy && proxy.hidden === true) continue
      out.push(names[i])
    }
    if (svc.mode === "global" && svc.proxyFor("GLOBAL")) out.unshift("GLOBAL")
    return out
  }

  function toggleGroup(name) {
    var next = {}
    for (var key in expanded) next[key] = expanded[key]
    next[name] = !next[name]
    expanded = next
  }

  function isExpanded(name) {
    return expanded[name] === true
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
    title: "代理组"
    subtitle: root.visibleGroups.length + " 个组 · 当前模式 " + (root.svc ? root.svc.modeLabel : "")
    foreground: root.fg
    fontFamily: root.fontFamily

    ModeSwitch {
      anchors.verticalCenter: parent.verticalCenter
      svc: root.svc
      foreground: root.fg
      fontFamily: root.fontFamily
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
      spacing: Style.space(10)

      Text {
        width: parent.width
        visible: root.visibleGroups.length === 0
        text: root.svc && root.svc.connected
          ? "当前配置里没有代理组。"
          : "未连接到 mihomo 内核。"
        color: Util.alpha(root.fg, 0.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.visibleGroups

        GroupCard {
          required property var modelData
          width: column.width
          groupName: modelData
        }
      }

      Item { width: 1; height: Style.space(4) }
    }
  }

  component GroupCard: Card {
    id: card
    required property string groupName

    readonly property var proxy: root.svc ? root.svc.proxyFor(groupName) : null
    readonly property string groupType: proxy ? String(proxy.type || "") : ""
    readonly property string currentNode: proxy ? String(proxy.now || "") : ""
    readonly property var nodes: root.svc ? root.svc.nodesOf(groupName) : []
    // Only Selector groups accept PUT /proxies/{name}; the automatic kinds pick
    // for themselves and reject a forced choice.
    readonly property bool selectable: groupType === "Selector"
    readonly property bool open: root.isExpanded(groupName)

    foreground: root.fg
    gap: Style.space(10)

    Item {
      width: parent.width
      implicitHeight: Math.max(titleColumn.implicitHeight, headerActions.implicitHeight)

      Column {
        id: titleColumn
        anchors.left: parent.left
        anchors.right: headerActions.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: card.groupName
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Row {
          spacing: Style.space(8)

          Badge {
            text: card.groupType
            tint: card.selectable ? Color.accent : Util.alpha(root.fg, 0.55)
            fontFamily: root.fontFamily
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, titleColumn.width - Style.space(90))
            text: card.currentNode
            color: Util.alpha(root.fg, 0.62)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }
      }

      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Badge {
          anchors.verticalCenter: parent.verticalCenter
          text: String(card.nodes.length)
          tint: Util.alpha(root.fg, 0.5)
          fontFamily: root.fontFamily
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰓅"
          tooltipText: "测试整组延迟"
          foreground: root.fg
          hoverColor: Color.accent
          fontFamily: root.fontFamily
          enabled: !root.svc.isTesting(card.groupName)
          onClicked: root.svc.testGroup(card.groupName)
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: card.open ? "󰅀" : "󰅂"
          tooltipText: card.open ? "收起节点" : "展开节点"
          foreground: root.fg
          hoverColor: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.toggleGroup(card.groupName)
        }
      }
    }

    Column {
      width: parent.width
      visible: card.open
      spacing: Style.space(4)

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(root.fg, 0.1)
      }

      Repeater {
        // Collapsed groups build nothing, so a 28-node GLOBAL costs nothing
        // until it is opened.
        model: card.open ? card.nodes : []

        NodeRow {
          required property var modelData
          width: parent.width
          nodeName: modelData
          groupName: card.groupName
          selectable: card.selectable
          selected: modelData === card.currentNode
        }
      }

      Text {
        width: parent.width
        visible: !card.selectable
        text: groupTypeHint(card.groupType)
        color: Util.alpha(root.fg, 0.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        topPadding: Style.space(4)
        renderType: Text.NativeRendering

        function groupTypeHint(type) {
          if (type === "URLTest") return "URLTest 组由内核按延迟自动挑选，无法手动指定节点。"
          if (type === "Fallback") return "Fallback 组按顺序使用第一个可用节点。"
          if (type === "LoadBalance") return "LoadBalance 组在节点之间分摊连接。"
          return "该组类型不支持手动切换节点。"
        }
      }
    }
  }

  component NodeRow: Rectangle {
    id: nodeRow
    required property string nodeName
    required property string groupName
    required property bool selectable
    required property bool selected

    height: Style.space(30)
    radius: Style.cornerRadius
    color: selected ? Util.alpha(Color.accent, 0.14)
      : nodeMouse.containsMouse && selectable ? Util.alpha(root.fg, 0.07)
      : "transparent"

    MouseArea {
      id: nodeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: nodeRow.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.svc.testNode(nodeRow.nodeName)
          return
        }
        if (nodeRow.selectable && !nodeRow.selected)
          root.svc.selectNode(nodeRow.groupName, nodeRow.nodeName)
      }
    }

    Text {
      id: nodeCheck
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: nodeRow.selected ? "󰄬" : ""
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      width: Style.space(14)
      renderType: Text.NativeRendering
    }

    Text {
      anchors.left: nodeCheck.right
      anchors.leftMargin: Style.space(4)
      anchors.right: nodeDelay.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: nodeRow.nodeName
      color: nodeRow.selected ? Color.accent : Util.alpha(root.fg, 0.85)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: nodeRow.selected
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    DelayBadge {
      id: nodeDelay
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      svc: root.svc
      proxyName: nodeRow.nodeName
      foreground: root.fg
      fontFamily: root.fontFamily
    }
  }
}
