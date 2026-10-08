import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root
  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family
  property var openRules: null

  function countText(count) {
    if (!root.svc) return String(count)
    return root.svc.t(count === 1 ? "profilesCountOne" : "profilesCountMany", count)
  }

  function typeText(type) {
    if (!root.svc) return String(type || "")
    return type === "remote" ? root.svc.t("profileTypeRemote") : root.svc.t("profileTypeLocal")
  }

  function fmtUpdated(stamp) {
    var value = String(stamp || "")
    if (value === "" || value.indexOf("0001-01-01") === 0) return ""
    var parsed = new Date(value)
    if (isNaN(parsed.getTime())) return value
    return Qt.formatDateTime(parsed, "yyyy-MM-dd hh:mm")
  }

  function metaLine(meta) {
    var parts = [root.typeText(meta.type)]
    var updated = root.fmtUpdated(meta.lastSuccessAt)
    if (updated !== "") parts.push(root.svc.t("profileUpdated", updated))
    var usage = meta.subscriptionInfo || {}
    if (Number(usage.total || 0) > 0)
      parts.push(root.svc.t("profileQuota", root.svc.fmtBytes(usage.download || 0), root.svc.fmtBytes(usage.total || 0)))
    var expire = Number(usage.expire || 0)
    if (expire > 0) parts.push(root.svc.t("profileExpires", root.fmtUpdated(new Date(expire * 1000).toISOString())))
    return parts.join(" · ")
  }

  AddProfileDialog {
    id: addDialog
    svc: root.svc
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  AddProfileDialog {
    id: importDialog
    svc: root.svc
    mode: "local"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  AddProfileDialog {
    id: renameDialog
    svc: root.svc
    mode: "rename"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  AddProfileDialog {
    id: urlDialog
    svc: root.svc
    mode: "url"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  ProfileDetail {
    id: detail
    svc: root.svc
    profileId: ""
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  OverrideEditorDialog {
    id: overrideDialog
    svc: root.svc
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  property bool profileRemoving: false
  property string profileRemoveId: ""
  property string profileRemoveName: ""
  property var actionProfile: null
  ConfirmDialog {
    id: deleteConfirm
    anchors.fill: parent
    z: 100
    opened: root.profileRemoving
    message: root.svc ? root.svc.t("deleteProfileConfirm", root.profileRemoveName) : "Delete this profile?"
    cancelText: root.svc ? root.svc.t("cancel") : "Cancel"
    confirmText: root.svc ? root.svc.t("deleteProfile") : "Delete"
    foreground: root.fg
    onCanceled: root.profileRemoving = false
    onConfirmed: { root.profileRemoving = false; root.svc.deleteProfile(root.profileRemoveId) }
  }

  Popup {
    id: actionMenu
    modal: true
    focus: true
    padding: Style.space(10)
    width: Style.space(230)
    height: Math.min(actionColumn.implicitHeight + Style.space(20),
                     Math.max(Style.space(220), Overlay.overlay ? Overlay.overlay.height - Style.space(32) : Style.space(420)))
    anchors.centerIn: Overlay.overlay
    background: Rectangle {
      color: Color.popups.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: Util.alpha(root.fg, 0.2)
    }
    ScrollView {
      id: actionScroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: actionColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: actionColumn
        width: actionScroll.availableWidth
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: root.actionProfile ? String(root.actionProfile.name || "") : ""
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("updateProfile") : "Update"
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: { root.svc.updateProfile(root.actionProfile.id, false); actionMenu.close() }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("updateViaProxy") : "Update via proxy"
          visible: root.actionProfile && root.actionProfile.type === "remote"
          enabled: root.svc && root.actionProfile && root.svc.connected && !root.svc.profileMutating
          onClicked: { root.svc.updateProfileViaProxy(root.actionProfile.id); actionMenu.close() }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("renameProfile") : "Rename"
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            renameDialog.profileId = root.actionProfile.id
            renameDialog.profileName = String(root.actionProfile.name || "")
            actionMenu.close()
            renameDialog.open()
          }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("editProfileUrl") : "Edit URL"
          visible: root.actionProfile && root.actionProfile.type === "remote"
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            var id = root.actionProfile.id
            actionMenu.close()
            urlDialog.profileId = id
            urlDialog.profileUrl = ""
            root.svc.readProfileURL(id, function(value) { urlDialog.profileUrl = value; urlDialog.open() })
          }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("viewSource") : "View source"
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            detail.profileId = root.actionProfile.id
            detail.profileName = String(root.actionProfile.name || "")
            detail.showRuntime = false
            detail.showOverride = false
            detail.globalScope = false
            actionMenu.close()
            detail.open()
          }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("viewRuntime") : "View runtime"
          visible: root.actionProfile && root.svc && root.svc.activeProfile === root.actionProfile.id
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            detail.profileId = root.actionProfile.id
            detail.profileName = String(root.actionProfile.name || "")
            detail.showRuntime = true
            detail.showOverride = false
            detail.globalScope = false
            actionMenu.close()
            detail.open()
          }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("viewOverride") : "View override"
          visible: root.actionProfile !== null
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            overrideDialog.profileId = root.actionProfile.id
            overrideDialog.profileName = String(root.actionProfile.name || "")
            overrideDialog.globalScope = false
            actionMenu.close()
            overrideDialog.open()
          }
        }
        Button {
          width: parent.width
          text: root.svc ? root.svc.t("deleteProfile") : "Delete"
          enabled: root.svc && root.actionProfile && !root.svc.profileMutating
          onClicked: {
            root.profileRemoveId = root.actionProfile.id
            root.profileRemoveName = String(root.actionProfile.name || "")
            actionMenu.close()
            root.profileRemoving = true
          }
        }
      }
    }
  }

  property string setupMissingText: root.svc && root.svc.setupLoading
    ? root.svc.t("setupInProgress")
    : root.svc && root.svc.setupState === "needs-core"
      ? root.svc.t("setupNeedsCore")
      : root.svc ? root.svc.t("setupProfilesHint") : ""

  PageHeader {
    id: header
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    title: root.svc ? root.svc.t("profilesTitle") : "Profiles"
    subtitle: root.svc && root.svc.managerInstalled ? root.countText(root.svc.profiles.length) : root.svc ? root.svc.t("setupTitle") : ""
    foreground: root.fg; fontFamily: root.fontFamily
    PanelActionButton {
      iconText: "󰐕"
      tooltipText: root.svc ? root.svc.t("addProfile") : "Add profile"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc && root.svc.managerInstalled && !root.svc.profileMutating
      onClicked: { addDialog.mode = "remote"; addDialog.open() }
    }
    PanelActionButton {
      iconText: "󰆍"
      tooltipText: root.svc ? root.svc.t("importCurrentConfig") : "Import current config"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc && root.svc.managerInstalled && root.svc.connected && !root.svc.profileMutating
      onClicked: { importDialog.open() }
    }
  }
  Rectangle { id: rule; anchors.left: parent.left; anchors.right: parent.right; anchors.top: header.bottom; height: 1; color: Util.alpha(root.fg,0.12) }
  Text {
    id: errorText
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: rule.bottom
    anchors.topMargin: Style.space(8)
    visible: root.svc && (root.svc.profileError !== "" || root.svc.profileMutating)
    text: root.svc && root.svc.profileMutating
      ? root.svc.t("profileActionInProgress")
      : root.svc ? root.svc.profileError : ""
    textFormat: Text.PlainText
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  ListView {
    id: list
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: errorText.visible ? errorText.bottom : rule.bottom; anchors.bottom: globalConfiguration.top; anchors.bottomMargin: Style.space(12)
    anchors.topMargin: Style.space(14); clip: true; spacing: Style.space(8)
    model: root.svc ? root.svc.profiles : []
    delegate: Rectangle {
      required property var modelData
      width: ListView.view.width; height: modelData.lastError ? Style.space(82) : Style.space(64); radius: Style.cornerRadius
      color: mouse.containsMouse ? Util.alpha(root.fg,0.07) : Util.alpha(root.fg,0.04)
      border.width: root.svc && root.svc.activeProfile === modelData.id ? 1 : 0
      border.color: Color.accent
      MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: if(root.svc) root.svc.selectProfile(modelData.id) }
      Column {
        anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.right: actions.left; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
        Text { width: parent.width; text: (root.svc && root.svc.activeProfile === modelData.id ? "● " : "○ ") + modelData.name; color: root.svc && root.svc.activeProfile === modelData.id ? Color.accent : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; renderType: Text.NativeRendering }
        Text { width: parent.width; text: root.metaLine(modelData); color: Util.alpha(root.fg,0.5); font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; renderType: Text.NativeRendering }
        Text { width: parent.width; visible: String(modelData.lastError || "") !== ""; text: root.svc ? root.svc.t("profileLastError", modelData.lastError) : String(modelData.lastError || ""); color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; renderType: Text.NativeRendering }
      }
      Row { id: actions; anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(4)
        PanelActionButton { iconText: "󰑐"; tooltipText: root.svc ? root.svc.t("updateProfile") : "Update"; foreground: root.fg; hoverColor: Color.accent; fontFamily: root.fontFamily; enabled: root.svc && root.svc.managerInstalled && !root.svc.profileMutating; onClicked: root.svc.updateProfile(modelData.id,false) }
        PanelActionButton { iconText: "󰇙"; tooltipText: root.svc ? root.svc.t("moreProfileActions") : "More actions"; foreground: root.fg; hoverColor: Color.accent; fontFamily: root.fontFamily; enabled: root.svc && root.svc.managerInstalled && !root.svc.profileMutating; onClicked: { root.actionProfile = modelData; actionMenu.open() } }
      }
    }
  }
  Text { anchors.centerIn: list; width: list.width-Style.space(40); visible: list.count === 0; text: root.svc && !root.svc.managerInstalled ? root.setupMissingText : root.svc ? root.svc.t("noProfiles") : ""; color: Util.alpha(root.fg,0.5); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; renderType: Text.NativeRendering }
  Button { anchors.horizontalCenter: list.horizontalCenter; anchors.top: list.verticalCenter; visible: root.svc && !root.svc.managerInstalled && root.svc.setupState !== "needs-core"; text: root.svc && root.svc.setupLoading ? root.svc.t("settingUp") : root.svc ? root.svc.t("setupMihomo") : "Set up Mihomo"; enabled: root.svc && !root.svc.setupLoading; onClicked: root.svc.setup() }

  Card {
    id: globalConfiguration
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    foreground: root.fg
    visible: root.svc && root.svc.managerInstalled
    height: visible ? implicitHeight : 0

    PanelSectionHeader {
      text: root.svc ? root.svc.t("globalConfiguration") : "Global Configuration"
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Column {
        width: parent.width - globalOverrideAction.width - Style.space(8)
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: root.svc ? root.svc.t("globalOverride") : "Global Override"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          renderType: Text.NativeRendering
        }
        Text {
          width: parent.width
          text: root.svc && !root.svc.globalOverrideEmpty
            ? root.svc.t("customConfiguration")
            : (root.svc ? root.svc.t("noCustomConfiguration") : "No custom configuration")
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
      }

      Button {
        id: globalOverrideAction
        text: root.svc ? root.svc.t("edit") : "Edit"
        enabled: root.svc && !root.svc.globalOverrideLoading && !root.svc.overrideSavePending
        onClicked: {
          overrideDialog.globalScope = true
          overrideDialog.profileId = ""
          overrideDialog.profileName = ""
          overrideDialog.open()
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Column {
        width: parent.width - proxyBindingAction.width - customRulesAction.width - Style.space(16)
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: root.svc ? root.svc.t("customRules") : "Custom Rules"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          renderType: Text.NativeRendering
        }
        Text {
          width: parent.width
          text: root.svc
            ? root.svc.t(root.svc.customRules.length === 1 ? "customRulesCountOne" : "customRulesCountMany", root.svc.customRules.length)
            : "0 rules"
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }

      Button {
        id: proxyBindingAction
        text: root.svc ? root.svc.t("editProxyBinding") : "Edit proxy group"
        enabled: root.svc && root.svc.managerInstalled && root.svc.activeProfile !== ""
          && !root.svc.bindingCandidatesLoading && !root.svc.profileMutating
        onClicked: root.svc.openProxyBindingEditor()
      }

      Button {
        id: customRulesAction
        text: root.svc ? root.svc.t("viewAllRules") : "View all"
        enabled: root.svc && !root.svc.customRulesLoading && !root.svc.profileMutating
        onClicked: if (root.openRules) root.openRules()
      }
    }
  }

}
