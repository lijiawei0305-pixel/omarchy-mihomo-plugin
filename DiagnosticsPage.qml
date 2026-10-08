import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family

  function labelFor(id) {
    if (!root.svc) return String(id || "")
    return root.svc.t("diagnostic_" + String(id || ""))
  }

  function statusText(status) {
    if (!root.svc) return String(status || "")
    if (status === "ok") return root.svc.t("diagnosticStatusOk")
    if (status === "info") return root.svc.t("diagnosticStatusInfo")
    if (status === "error") return root.svc.t("diagnosticStatusError")
    return root.svc.t("diagnosticStatusWarning")
  }

  function statusColor(status) {
    if (status === "ok") return Color.accent
    if (status === "error") return Color.urgent
    return Color.muted
  }

  function messageFor(check) {
    var fallback = String(check.message || "")
    if (!root.svc || !check.messageKey) return fallback
    var args = Array.isArray(check.messageArgs) ? check.messageArgs : []
    return root.svc.t.apply(root.svc, [String(check.messageKey)].concat(args))
  }

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: root.svc ? root.svc.t("diagnosticsTitle") : "Diagnostics"
    subtitle: root.svc && root.svc.managerInstalled
      ? root.svc.t("diagnosticsSubtitle", root.svc.diagnostics.length)
      : ""
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: root.svc ? root.svc.t("refreshDiagnostics") : "Run diagnostics again"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc && root.svc.managerInstalled && !root.svc.diagnosticsLoading
      onClicked: root.svc.refreshDiagnostics()
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    height: 1
    color: Util.alpha(root.fg, 0.12)
  }

  ListView {
    id: checks
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(12)
    clip: true
    spacing: Style.space(6)
    model: root.svc ? root.svc.diagnostics : []

    delegate: Rectangle {
      required property var modelData
      width: checks.width
      implicitHeight: Math.max(Style.space(48), details.implicitHeight + Style.space(20))
      radius: Style.cornerRadius
      color: Util.alpha(root.fg, 0.04)
      border.width: 1
      border.color: Util.alpha(root.statusColor(String(modelData.status || "warning")), 0.35)

      Badge {
        id: status
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.statusText(String(modelData.status || "warning"))
        tint: root.statusColor(String(modelData.status || "warning"))
        fontFamily: root.fontFamily
      }

      Column {
        id: details
        anchors.left: status.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.labelFor(modelData.id)
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          id: message
          width: parent.width
          text: root.messageFor(modelData)
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.58)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }

        Button {
          visible: root.svc && modelData.id === "tunCapability"
            && modelData.messageKey === "diagnosticCapabilityMissing"
          text: root.svc && root.svc.tunFixLoading
            ? root.svc.t("fixingTunPermission")
            : root.svc ? root.svc.t("fixTunPermission") : "Fix & Enable"
          enabled: root.svc && !root.svc.tunFixLoading
          onClicked: root.svc.fixTunPermission()
        }
      }
    }
  }

  Text {
    anchors.centerIn: checks
    width: checks.width - Style.space(36)
    visible: !root.svc || !root.svc.managerInstalled || checks.count === 0
    text: !root.svc || !root.svc.managerInstalled
      ? (root.svc ? root.svc.t("diagnosticsUnavailable") : "Complete one-time setup to run diagnostics.")
      : (root.svc.diagnosticsLoading ? root.svc.t("loading") : "")
    textFormat: Text.PlainText
    color: Util.alpha(root.fg, 0.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    renderType: Text.NativeRendering
  }
}
