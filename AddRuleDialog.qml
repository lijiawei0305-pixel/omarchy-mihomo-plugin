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
  property string ruleId: ""
  property string initialDomain: ""
  property string initialMatch: "domain-suffix"
  property string initialPolicy: "proxy"
  property bool showAdvanced: false

  readonly property bool editing: root.ruleId !== ""

  modal: true
  focus: true
  padding: Style.space(18)
  width: Style.space(440)
  height: Style.space(370)
  anchors.centerIn: Overlay.overlay
  background: Rectangle {
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.2)
  }

  function reset() {
    root.showAdvanced = false
    domain.text = root.initialDomain
    match.value = root.initialMatch || "domain-suffix"
    policy.value = root.initialPolicy || "proxy"
    domain.forceActiveFocus()
    domain.selectAll()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      Layout.fillWidth: true
      text: root.svc ? root.svc.t(root.editing ? "editRule" : "addRule") : (root.editing ? "Edit rule" : "Add rule")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      renderType: Text.NativeRendering
    }

    ScrollView {
      id: formScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        width: formScroll.availableWidth
        spacing: Style.space(10)

        TextField {
          id: domain
          width: parent.width
          placeholderText: root.svc ? root.svc.t("domain") : "Domain"
          foreground: root.foreground
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          selectByMouse: true
        }

        PlainTextDropdown {
          id: policy
          width: parent.width
          label: root.svc ? root.svc.t("policy") : "Policy"
          options: [
            {label: root.svc ? root.svc.t("policyProxy") : "Proxy", value: "proxy"},
            {label: root.svc ? root.svc.t("policyDirect") : "Direct", value: "direct"},
            {label: root.svc ? root.svc.t("policyReject") : "Reject", value: "reject"}
          ]
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Button {
          text: root.svc
            ? root.svc.t(root.showAdvanced ? "hideAdvancedOptions" : "advancedOptions")
            : (root.showAdvanced ? "Hide advanced options" : "Advanced")
          onClicked: root.showAdvanced = !root.showAdvanced
        }

        PlainTextDropdown {
          id: match
          width: parent.width
          visible: root.showAdvanced
          height: visible ? implicitHeight : 0
          label: root.svc ? root.svc.t("match") : "Match"
          options: [
            {label: root.svc ? root.svc.t("matchDomainSuffix") : "Domain and subdomains", value: "domain-suffix"},
            {label: root.svc ? root.svc.t("matchDomain") : "Exact domain", value: "domain"}
          ]
          value: "domain-suffix"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: root.svc ? root.svc.t("ruleNormalizationHint") : "URLs and wildcard domains are normalized automatically."
          textFormat: Text.PlainText
          color: Util.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }
      }
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      spacing: Style.space(8)
      layoutDirection: Qt.RightToLeft

      Button {
        text: root.editing
          ? (root.svc ? root.svc.t("save") : "Save")
          : (root.svc ? root.svc.t("add") : "Add")
        enabled: domain.text.trim() !== "" && root.svc && !root.svc.profileMutating
        onClicked: {
          if (root.editing)
            root.svc.updateCustomRule(root.ruleId, domain.text, match.value, policy.value)
          else
            root.svc.addCustomRule(domain.text, match.value, policy.value)
          root.close()
        }
      }
      Button {
        text: root.svc ? root.svc.t("cancel") : "Cancel"
        onClicked: root.close()
      }
    }
  }

  onOpened: root.reset()
}
