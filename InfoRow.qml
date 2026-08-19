import QtQuick
import qs.Commons

// Label on the left, value hard against the right edge. The value shrinks
// before the label does, so long node names elide instead of pushing the
// label off the card.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.popups.text
  property color valueColor: foreground
  property string fontFamily: Style.font.family
  property bool valueBold: false

  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: Util.alpha(root.foreground, 0.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  Text {
    id: valueText
    anchors.right: parent.right
    anchors.left: labelText.right
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.value
    color: root.valueColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: root.valueBold
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideMiddle
    renderType: Text.NativeRendering
  }
}
