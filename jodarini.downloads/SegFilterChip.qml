import QtQuick
import qs.Commons

// A non-animated filter chip. The shared Button paints its state through a
// 120ms ColorAnimation that reads as a flash in tightly-grouped filter rows,
// so this chip switches colors instantly while reusing the same visual
// tokens: the selected chip takes the shared selected-fill gray.
Item {
  id: chip

  property string label: ""
  property bool selected: false
  signal clicked()

  implicitWidth: textItem.implicitWidth + Style.space(16)
  implicitHeight: textItem.implicitHeight + Style.space(8)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(5)
    color: chip.selected ? Style.selectedFill
      : (mouseArea.containsMouse ? Style.hoverFill : "transparent")
  }

  Text {
    id: textItem
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: chip.label
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
    color: chip.selected ? Color.foreground : Color.muted
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    onClicked: chip.clicked()
  }
}