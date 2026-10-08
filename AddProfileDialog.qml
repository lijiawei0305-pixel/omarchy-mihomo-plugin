import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Popup {
  id: root
  property var svc: null
  property color foreground: Color.popups.text
  property string mode: "remote"
  property string profileId: ""
  property string profileName: ""
  property var operationTitle: root.mode === "local" ? (root.svc ? root.svc.t("importCurrentConfig") : "Import current config") : root.mode === "rename" ? (root.svc ? root.svc.t("renameProfile") : "Rename profile") : root.mode === "url" ? (root.svc ? root.svc.t("editProfileUrl") : "Edit profile URL") : (root.svc ? root.svc.t("addProfile") : "Add profile")
  property var operationText: root.mode === "local" ? (root.svc ? root.svc.t("import") : "Import") : root.mode === "rename" || root.mode === "url" ? (root.svc ? root.svc.t("save") : "Save") : (root.svc ? root.svc.t("add") : "Add")
  property bool isLocalImport: root.mode === "local"
  property bool isRename: root.mode === "rename"
  property bool isUrlEdit: root.mode === "url"
  property string profileUrl: ""
  property int intervalSec: 21600
  property string fontFamily: Style.font.family
  modal: true
  focus: true
  padding: Style.space(18)
  width: Style.space(420)
  anchors.centerIn: Overlay.overlay

  background: Rectangle { color: Color.popups.background; radius: Style.cornerRadius; border.width: 1; border.color: Util.alpha(root.foreground,0.2) }
  Column {
    width: parent.width; spacing: Style.space(10)
    Text { text: root.operationTitle; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
    TextField { id: name; width: parent.width; visible: !root.isUrlEdit; placeholderText: root.svc ? root.svc.t(root.isLocalImport ? "profileNameLocal" : root.isRename ? "profileName" : "profileNameRemote") : "Name"; color: root.foreground; font.family: root.fontFamily }
    TextField { id: url; width: parent.width; visible: !root.isLocalImport && !root.isRename; placeholderText: root.svc ? root.svc.t("subscriptionUrl") : "Subscription URL"; color: root.foreground; font.family: root.fontFamily; inputMethodHints: Qt.ImhUrlCharactersOnly }
    PlainTextDropdown {
      width: parent.width
      visible: !root.isLocalImport && !root.isRename && !root.isUrlEdit
      label: root.svc ? root.svc.t("updateInterval") : "Update interval"
      options: [
        {label: root.svc ? root.svc.t("intervalDisabled") : "Disabled", value: "0"},
        {label: root.svc ? root.svc.t("interval1h") : "1 hour", value: "3600"},
        {label: root.svc ? root.svc.t("interval6h") : "6 hours", value: "21600"},
        {label: root.svc ? root.svc.t("interval12h") : "12 hours", value: "43200"},
        {label: root.svc ? root.svc.t("interval24h") : "24 hours", value: "86400"}
      ]
      value: String(root.intervalSec)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: root.intervalSec = Number(value)
    }
    Row { spacing: Style.space(8); anchors.right: parent.right
      Button { text: root.svc ? root.svc.t("cancel") : "Cancel"; onClicked: root.close() }
      Button { text: root.operationText; enabled: (root.isUrlEdit && url.text.trim() !== "") || (name.text.trim() !== "" && (root.isLocalImport || root.isRename || url.text.trim() !== "")); onClicked: {
        if (root.isLocalImport) root.svc.importCurrent(name.text.trim())
        else if (root.isRename) root.svc.renameProfile(root.profileId, name.text.trim())
        else if (root.isUrlEdit) root.svc.setProfileURL(root.profileId, url.text.trim())
        else root.svc.addProfile(url.text.trim(), name.text.trim(), root.intervalSec)
        root.close()
      } }
    }
  }
  onOpened: {
    name.text = root.mode === "rename" ? root.profileName : ""
    root.intervalSec = 21600
    url.text = root.isUrlEdit ? root.profileUrl : ""
    if (root.isUrlEdit) url.forceActiveFocus()
    else name.forceActiveFocus()
    if (root.isUrlEdit) url.selectAll()
    else name.selectAll()
  }
}
