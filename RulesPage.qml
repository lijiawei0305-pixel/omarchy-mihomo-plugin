import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family

  readonly property bool editing: filterField.activeFocus

  property string filter: ""

  readonly property var rows: {
    var all = svc ? svc.rules : []
    var needle = filter.trim().toLowerCase()
    if (needle === "") return all
    var out = []
    for (var i = 0; i < all.length; i++) {
      var rule = all[i]
      if (String(rule.payload).toLowerCase().indexOf(needle) >= 0
        || String(rule.proxy).toLowerCase().indexOf(needle) >= 0
        || String(rule.type).toLowerCase().indexOf(needle) >= 0) out.push(rule)
    }
    return out
  }

  // DIRECT and REJECT are terminal outcomes rather than proxies; colour them
  // so a long list can be skimmed for "what actually leaves the machine".
  function targetColor(target) {
    if (target === "DIRECT") return Util.alpha(fg, 0.6)
    if (target === "REJECT" || target === "REJECT-DROP") return Color.urgent
    return Color.accent
  }

  function focusFilter() {
    filterField.forceActiveFocus()
    filterField.selectAll()
  }

  function scrollBy(delta) {
    listView.contentY = Math.max(0, Math.min(Math.max(0, listView.contentHeight - listView.height),
                                             listView.contentY + delta))
  }

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: root.svc ? root.svc.t("rulesTitle") : "Rules"
    subtitle: root.svc
      ? (root.filter === ""
          ? root.svc.t("rulesCount", root.svc.ruleCount)
          : root.svc.t("rulesFiltered", root.rows.length, root.svc.ruleCount))
      : ""
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: root.svc ? root.svc.t("refreshRules") : "Reload rules"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc !== null && !root.svc.rulesLoading
      onClicked: root.svc.refreshRules()
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

  TextField {
    id: filterField
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: headerRule.bottom
    anchors.topMargin: Style.space(12)
    placeholderText: root.svc ? root.svc.t("filterRules") : "Filter domain / type / target"
    foreground: root.fg
    accent: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    onTextChanged: root.filter = text
    Keys.onEscapePressed: function(event) {
      if (text !== "") { text = "" ; event.accepted = true }
      else focus = false
    }
  }

  ListView {
    id: listView
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterField.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(10)
    clip: true
    spacing: Style.space(2)
    model: root.rows
    cacheBuffer: Style.space(200)

    ScrollBar.vertical: ScrollBar {
      policy: listView.contentHeight > listView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    delegate: Rectangle {
      id: ruleRow
      required property var modelData
      required property int index
      width: ListView.view.width
      height: Style.space(38)
      radius: Style.cornerRadius
      color: ruleMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent"

      MouseArea {
        id: ruleMouse
        anchors.fill: parent
        hoverEnabled: true
      }

      Text {
        id: ruleIndex
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        text: String(ruleRow.modelData.index !== undefined ? ruleRow.modelData.index + 1 : ruleRow.index + 1)
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        renderType: Text.NativeRendering
      }

      Column {
        anchors.left: ruleIndex.right
        anchors.leftMargin: Style.space(10)
        anchors.right: ruleTarget.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: String(ruleRow.modelData.payload || "")
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: String(ruleRow.modelData.type || "")
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
      }

      Text {
        id: ruleTarget
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(120)
        text: String(ruleRow.modelData.proxy || "")
        textFormat: Text.PlainText
        color: root.targetColor(String(ruleRow.modelData.proxy || ""))
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }
  }

  Text {
    anchors.centerIn: listView
    width: listView.width - Style.space(40)
    visible: root.rows.length === 0
    text: root.svc && root.svc.rulesLoading ? root.svc.t("loadingRules")
      : root.svc && !root.svc.connected ? root.svc.t("notConnected")
      : root.filter !== "" ? root.svc.t("noMatchRules")
      : (root.svc ? root.svc.t("noRules") : "")
    textFormat: Text.PlainText
    color: Util.alpha(root.fg, 0.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    renderType: Text.NativeRendering
  }
}
