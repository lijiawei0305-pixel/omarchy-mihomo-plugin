import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Popup {
  id: root
  property var svc: null
  property string profileId: ""
  property string profileName: ""
  property bool globalScope: false
  property bool showRuntime: false
  property bool showOverride: false
  property string runtimeText: ""
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  modal: true; focus: true; padding: Style.space(18); width: Style.space(500)
  height: Overlay.overlay
    ? Math.min(Style.space(520), Math.max(Style.space(300), Overlay.overlay.height - Style.space(32)))
    : Style.space(460)
  anchors.centerIn: Overlay.overlay
  background: Rectangle { color: Color.popups.background; radius: Style.cornerRadius; border.width: 1; border.color: Util.alpha(root.foreground,0.2) }
  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.max(titleText.implicitHeight, activeText.implicitHeight)

      Text {
        id: titleText
        Layout.fillWidth: true
        text: root.globalScope ? (root.svc ? root.svc.t("globalOverride") : "Global Override") : root.showRuntime ? (root.svc ? root.svc.t("runtimeConfig") : "Runtime") : root.showOverride ? (root.svc ? root.svc.t("profileOverride") : "Profile Override") : (root.svc ? root.svc.t("profileSource") : "Source Config")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: activeText
        text: root.svc && root.svc.activeProfile === root.profileId ? root.svc.t("activeProfile") : ""
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Button {
        visible: !root.globalScope
        text: root.showOverride ? (root.svc ? root.svc.t("viewSource") : "View Source") : (root.svc ? root.svc.t("viewOverride") : "View Override")
        onClicked: { root.showRuntime = false; root.showOverride = !root.showOverride; root.load() }
      }
      Button {
        visible: !root.globalScope && !root.showOverride
        text: root.showRuntime ? (root.svc ? root.svc.t("viewSource") : "View Source") : (root.svc ? root.svc.t("viewRuntime") : "View Runtime")
        onClicked: { root.showRuntime = !root.showRuntime; root.showOverride = false; root.load() }
      }
      Button {
        visible: root.showOverride && !root.globalScope
        text: root.svc ? root.svc.t("editOverride") : "Edit Override"
        onClicked: root.svc.openProfileOverride(root.profileId)
      }
      Button {
        visible: root.globalScope
        text: root.svc ? root.svc.t("editOverride") : "Edit Override"
        onClicked: root.svc.openGlobalOverride()
      }
    }

    ScrollView {
      id: sourceScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      ScrollBar.vertical.policy: ScrollBar.AsNeeded
      ScrollBar.horizontal.policy: ScrollBar.AsNeeded

      TextArea {
        id: source
        width: Math.max(sourceScroll.availableWidth, contentWidth)
        height: Math.max(sourceScroll.availableHeight, contentHeight)
        readOnly: true
        wrapMode: TextArea.NoWrap
        text: root.svc ? root.svc.t("loading") : "Loading…"
        color: root.foreground
        font.family: "monospace"
        selectByMouse: true
      }
    }

    Button {
      Layout.alignment: Qt.AlignRight
      text: root.svc ? root.svc.t("close") : "Close"
      onClicked: root.close()
    }
  }
  function load() {
    if (!root.svc || (!root.globalScope && root.profileId === "")) return
    if (root.globalScope) {
      source.text = root.svc.t("loading")
      root.svc.readGlobalOverride(function(text) { source.text = text })
    } else if (root.showOverride) {
      source.text = root.svc ? root.svc.t("loading") : "Loading…"
      root.svc.readProfileOverride(root.profileId, function(text) { source.text = text })
    } else if (root.showRuntime) {
      source.text = root.svc ? root.svc.t("loading") : "Loading…"
      if (root.svc && root.svc.activeProfile === root.profileId) {
        root.svc.readProfileRuntime(root.profileId, function(text) { root.runtimeText = text; source.text = text })
      } else {
        source.text = root.svc.t("runtimeUnavailable")
      }
    } else {
      source.text = root.svc ? root.svc.t("loading") : "Loading…"
      root.svc.readProfileSource(root.profileId, function(text) { source.text = text })
    }
  }
  onOpened: load()
}
