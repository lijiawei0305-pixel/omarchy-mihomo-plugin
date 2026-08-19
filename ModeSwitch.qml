import QtQuick
import qs.Ui
import qs.Commons

// Rule / Global / Direct. Writes straight through to PATCH /configs, which is what
// every other mihomo front-end does, so switching here is visible everywhere.
Row {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.space(8)

  Button {
    text: root.svc ? root.svc.t("modeRule") : "Rule"
    tooltipText: root.svc ? root.svc.t("modeRuleTip") : "Route by rules"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "rule"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("rule")
  }

  Button {
    text: root.svc ? root.svc.t("modeGlobal") : "Global"
    tooltipText: root.svc ? root.svc.t("modeGlobalTip") : "Send everything through the GLOBAL group"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "global"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("global")
  }

  Button {
    text: root.svc ? root.svc.t("modeDirect") : "Direct"
    tooltipText: root.svc ? root.svc.t("modeDirectTip") : "Bypass the proxy"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "direct"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("direct")
  }
}
