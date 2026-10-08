import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

// Small, reusable context menu for actions that originate from a connection
// or an effective rule row. It deliberately opens the existing rule editor so
// the user can confirm the match type and proxy policy before anything is
// persisted.
Popup {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property string title: ""
  property string domain: ""
  property bool actionEnabled: true

  signal addToRulesRequested()

  modal: true
  focus: true
  z: 500
  parent: Overlay.overlay
  padding: Style.space(14)
  width: Style.space(310)
  height: Style.space(190)
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  function openAt(positionX, positionY) {
    var overlay = Overlay.overlay
    var margin = Style.space(8)
    var maxX = overlay ? Math.max(margin, overlay.width - width - margin) : positionX
    var maxY = overlay ? Math.max(margin, overlay.height - height - margin) : positionY
    x = Math.max(margin, Math.min(positionX, maxX))
    y = Math.max(margin, Math.min(positionY, maxY))
    open()
  }

  background: Rectangle {
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.2)
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(7)

    Text {
      Layout.fillWidth: true
      text: root.title !== ""
        ? root.title
        : (root.svc ? root.svc.t("contextMenuTitle") : "Actions")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      elide: Text.ElideMiddle
      renderType: Text.NativeRendering
    }

    Text {
      Layout.fillWidth: true
      text: root.domain !== ""
        ? root.domain
        : (root.svc ? root.svc.t("domainRuleRequired") : "This item does not contain a domain.")
      textFormat: Text.PlainText
      color: Util.alpha(root.foreground, 0.58)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      renderType: Text.NativeRendering
    }

    Button {
      Layout.fillWidth: true
      enabled: root.actionEnabled && root.domain.trim() !== ""
      text: root.svc ? root.svc.t("addDomainToRules") : "Add to custom rules"
      onClicked: {
        root.close()
        root.addToRulesRequested()
      }
    }

    Button {
      Layout.fillWidth: true
      text: root.svc ? root.svc.t("cancel") : "Cancel"
      onClicked: root.close()
    }
  }
}
