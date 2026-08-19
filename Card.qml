import QtQuick
import qs.Commons

// Bordered content block. Everything on a page sits in one of these so the
// panel reads as a stack of cards rather than a wall of rows.
Rectangle {
  id: root

  default property alias cardContent: inner.data

  property color foreground: Color.popups.text
  property real pad: Style.space(12)
  property real gap: Style.space(10)

  color: Util.alpha(foreground, 0.03)
  radius: Style.cornerRadius
  border.width: 1
  border.color: Util.alpha(foreground, 0.12)

  implicitHeight: inner.implicitHeight + pad * 2

  Column {
    id: inner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    anchors.topMargin: root.pad
    spacing: root.gap
  }
}
