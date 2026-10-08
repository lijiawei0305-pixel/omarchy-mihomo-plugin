import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Popup {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  modal: true
  focus: true
  padding: Style.space(18)
  width: Style.space(440)
  height: Style.space(350)
  anchors.centerIn: Overlay.overlay
  background: Rectangle {
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.2)
  }

  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onBindingRequiredChanged() {
      if (!root.svc || !root.svc.bindingRequired) root.close()
      else if (!root.opened) root.open()
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      Layout.fillWidth: true
      text: root.svc ? root.svc.t("bindingRequired") : "Choose a proxy group"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      renderType: Text.NativeRendering
    }

    Text {
      Layout.fillWidth: true
      text: root.svc && root.svc.bindingRequiredCandidates.length > 0
        ? (root.svc.t("chooseProxyGroup") + ":")
        : (root.svc ? root.svc.t("bindingUnavailable") : "No usable proxy group is available for Proxy")
      textFormat: Text.PlainText
      color: Util.alpha(root.foreground, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    ListView {
      id: candidateList
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      spacing: Style.space(5)
      model: root.svc ? root.svc.bindingRequiredCandidates : []

      delegate: Button {
        required property string modelData
        width: candidateList.width
        height: Style.space(34)
        text: modelData
        onClicked: {
          root.svc.setPolicyBinding(root.svc.bindingRequiredProfileId,
                                    root.svc.bindingRequiredPolicy || "proxy", modelData)
          root.close()
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      layoutDirection: Qt.RightToLeft
      Button {
        text: root.svc ? root.svc.t("cancel") : "Cancel"
        onClicked: {
          if (root.svc) root.svc.clearBindingRequired()
          root.close()
        }
      }
    }
  }
}
