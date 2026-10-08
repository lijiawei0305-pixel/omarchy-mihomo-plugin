import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

// Small YAML editor for the two local override scopes. Runtime/source
// inspection remains in ProfileDetail; this dialog owns only save-and-apply.
Popup {
  id: root

  property var svc: null
  property bool globalScope: true
  property string profileId: ""
  property string profileName: ""
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property bool loading: false
  property bool saving: false
  property string errorText: ""

  modal: true
  focus: true
  padding: Style.space(18)
  width: Style.space(540)
  height: Style.space(500)
  anchors.centerIn: Overlay.overlay
  background: Rectangle {
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.2)
  }

  function load() {
    if (!root.svc || (!root.globalScope && root.profileId === "")) return
    root.loading = true
    root.errorText = ""
    editor.text = root.svc.t("loading")
    if (root.globalScope) {
      root.svc.readGlobalOverride(function(text) {
        editor.text = text
        root.loading = false
      })
    } else {
      root.svc.readProfileOverride(root.profileId, function(text) {
        editor.text = text
        root.loading = false
      })
    }
  }

  function save() {
    if (!root.svc || root.loading || root.saving) return
    root.saving = true
    root.errorText = ""
    root.svc.saveOverride(root.globalScope, root.profileId, editor.text,
      function(ok, message) {
        root.saving = false
        if (ok) root.close()
        else root.errorText = message || root.svc.t("actionFailed")
      })
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      Layout.fillWidth: true
      text: root.globalScope
        ? (root.svc ? root.svc.t("globalOverride") : "Global Override")
        : (root.svc ? root.svc.t("profileOverride") : "Profile Override")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      renderType: Text.NativeRendering
    }

    Text {
      Layout.fillWidth: true
      visible: !root.globalScope && root.profileName !== ""
      text: root.profileName
      textFormat: Text.PlainText
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    ScrollView {
      id: editorScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      ScrollBar.vertical.policy: ScrollBar.AsNeeded
      ScrollBar.horizontal.policy: ScrollBar.AsNeeded

      TextArea {
        id: editor
        width: Math.max(editorScroll.availableWidth, contentWidth)
        height: Math.max(editorScroll.availableHeight, contentHeight)
        color: root.foreground
        selectionColor: Util.alpha(Color.accent, 0.35)
        selectedTextColor: root.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.caption
        wrapMode: TextArea.NoWrap
        selectByMouse: true
        placeholderText: "# YAML override"
        enabled: !root.loading && !root.saving
      }
    }

    Button {
      Layout.alignment: Qt.AlignLeft
      text: root.svc ? root.svc.t("openEditor") : "Open in editor"
      enabled: root.svc && !root.loading && !root.saving
      onClicked: {
        if (root.globalScope) root.svc.openGlobalOverride()
        else root.svc.openProfileOverride(root.profileId)
      }
    }

    Text {
      Layout.fillWidth: true
      visible: root.errorText !== ""
      text: root.errorText
      textFormat: Text.PlainText
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      spacing: Style.space(8)
      layoutDirection: Qt.RightToLeft

      Button {
        text: root.saving
          ? (root.svc ? root.svc.t("saving") : "Saving…")
          : (root.svc ? root.svc.t("saveApply") : "Save & Apply")
        enabled: root.svc && !root.loading && !root.saving
        onClicked: root.save()
      }
      Button {
        text: root.svc ? root.svc.t("cancel") : "Cancel"
        enabled: !root.saving
        onClicked: root.close()
      }
    }
  }

  onOpened: {
    root.loading = false
    root.saving = false
    root.load()
  }
}
