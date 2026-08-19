import QtQuick
import qs.Ui
import qs.Commons

Grid {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property bool compact: false

  columns: compact ? 1 : 2
  rowSpacing: Style.space(4)
  columnSpacing: Style.space(6)

  Button {
    text: "EN"
    tooltipText: "English"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    bordered: true
    active: root.svc && root.svc.language === "en"
    enabled: root.svc !== null
    onClicked: root.svc.setLanguage("en")
  }

  Button {
    text: "中文"
    tooltipText: "中文"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    bordered: true
    active: root.svc && root.svc.language === "zh"
    enabled: root.svc !== null
    onClicked: root.svc.setLanguage("zh")
  }
}
