import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family

  // Tells the panel's key catcher to stand down while the filter has focus.
  readonly property bool editing: filterField.activeFocus

  property string filter: ""

  readonly property var rows: {
    var all = svc ? svc.connections : []
    var needle = filter.trim().toLowerCase()
    if (needle === "") return all
    var out = []
    for (var i = 0; i < all.length; i++) {
      var row = all[i]
      if (row.host.toLowerCase().indexOf(needle) >= 0
        || row.process.toLowerCase().indexOf(needle) >= 0
        || row.chain.toLowerCase().indexOf(needle) >= 0
        || row.rule.toLowerCase().indexOf(needle) >= 0) out.push(row)
    }
    return out
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
    title: root.svc ? root.svc.t("connectionsTitle") : "Connections"
    subtitle: root.svc
      ? root.svc.t("connectionsSubtitle",
                   root.svc.connections.length,
                   root.svc.fmtBytes(root.svc.downTotal),
                   root.svc.fmtBytes(root.svc.upTotal))
      : ""
    foreground: root.fg
    fontFamily: root.fontFamily

    Button {
      anchors.verticalCenter: parent.verticalCenter
      text: root.svc ? root.svc.t("closeAll") : "Close all"
      foreground: root.fg
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      bordered: true
      accent: Color.urgent
      enabled: root.svc !== null && root.svc.connections.length > 0
      onClicked: root.svc.closeAllConnections()
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
    placeholderText: root.svc ? root.svc.t("filterConnections") : "Filter host / process / chain / rule"
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
    spacing: Style.space(4)
    model: root.rows
    cacheBuffer: Style.space(200)

    ScrollBar.vertical: ScrollBar {
      policy: listView.contentHeight > listView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    delegate: Rectangle {
      id: connRow
      required property var modelData
      width: ListView.view.width
      height: Style.space(46)
      radius: Style.cornerRadius
      color: connMouse.containsMouse ? Util.alpha(root.fg, 0.07) : Util.alpha(root.fg, 0.03)

      MouseArea {
        id: connMouse
        anchors.fill: parent
        hoverEnabled: true
      }

      Column {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.right: connMeter.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: connRow.modelData.host
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideMiddle
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: {
            var parts = []
            if (connRow.modelData.process !== "") parts.push(connRow.modelData.process)
            if (connRow.modelData.chain !== "") parts.push(connRow.modelData.chain)
            if (connRow.modelData.rule !== "") parts.push(connRow.modelData.rule)
            return parts.join("  ·  ")
          }
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
      }

      Column {
        id: connMeter
        anchors.right: connClose.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(78)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: "󰁝 " + root.svc.fmtBytes(root.svc.connUpload(connRow.modelData.id))
          color: Util.alpha(root.fg, 0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: "󰁅 " + root.svc.fmtBytes(root.svc.connDownload(connRow.modelData.id))
          color: Util.alpha(root.fg, 0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          renderType: Text.NativeRendering
        }
      }

      PanelActionButton {
        id: connClose
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        tooltipText: root.svc ? root.svc.t("closeConnection") : "Close this connection"
        foreground: root.fg
        hoverColor: Color.urgent
        fontFamily: root.fontFamily
        onClicked: root.svc.closeConnection(connRow.modelData.id)
      }
    }
  }

  Text {
    anchors.centerIn: listView
    width: listView.width - Style.space(40)
    visible: root.rows.length === 0
    text: root.svc && !root.svc.connected ? root.svc.t("notConnected")
      : root.filter !== "" ? (root.svc ? root.svc.t("noMatchConnections") : "")
      : (root.svc ? root.svc.t("noActiveConnections") : "")
    color: Util.alpha(root.fg, 0.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    renderType: Text.NativeRendering
  }
}
