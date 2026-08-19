import QtQuick
import qs.Ui
import qs.Commons

// 规则 / 全局 / 直连. Writes straight through to PATCH /configs, which is what
// every other mihomo front-end does, so switching here is visible everywhere.
Row {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.space(8)

  Button {
    text: "规则"
    tooltipText: "按规则分流"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "rule"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("rule")
  }

  Button {
    text: "全局"
    tooltipText: "全部流量走 GLOBAL 选中的节点"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "global"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("global")
  }

  Button {
    text: "直连"
    tooltipText: "不走代理"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.svc && root.svc.mode === "direct"
    enabled: root.svc !== null
    onClicked: root.svc.setMode("direct")
  }
}
