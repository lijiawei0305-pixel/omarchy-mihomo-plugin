import QtQuick
import qs.Commons

// Small pill for node type, delay, rule kind. Tint carries the meaning; the
// fill is always a wash of it so badges never fight the card behind them.
Rectangle {
  id: root

  property string text: ""
  property color tint: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption
  property bool solid: false

  implicitWidth: label.implicitWidth + Style.space(12)
  implicitHeight: label.implicitHeight + Style.space(5)
  radius: height / 2
  color: Util.alpha(tint, solid ? 0.22 : 0.12)
  border.width: 1
  border.color: Util.alpha(tint, solid ? 0.65 : 0.3)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    // Controller names must stay literal. AutoText would treat <img src="...">
    // as a resource load.
    textFormat: Text.PlainText
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: true
    renderType: Text.NativeRendering
  }
}
