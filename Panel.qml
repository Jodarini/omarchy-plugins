import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Downloads: what just landed in the download folder, one click from the bar.
Panel {
  id: root

  moduleName: "jankeesvw.downloads"
  ipcTarget: "jankeesvw.downloads"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int barContentWidth: Style.bar.iconFont
  readonly property int barSlot: barContentWidth + Style.space(10)

  // Hints to the bar for the accent indicator width.
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth

  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function applySettings() {
    var folder = String(root.setting("folder", ""))
    DownloadsStore.configure(root.setting("freshMinutes", 5),
                             folder !== "" ? Util.fileUrl(folder) : undefined)
    DownloadsStore.fontFamily = root.fontFamily
  }

  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  onOpenedChanged: {
    if (root.opened) {
      DownloadsStore.show()
      if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
    } else {
      DownloadsStore.hide()
      if (bar && typeof bar.releasePopout === "function") bar.releasePopout(root)
    }
  }

  Connections {
    target: DownloadsStore
    function onOpenChanged() {
      if (DownloadsStore.open && !root.opened) {
        root.open()
        if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
      } else if (!DownloadsStore.open && root.opened) {
        root.close()
        if (bar && typeof bar.releasePopout === "function") bar.releasePopout(root)
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: root.barContentWidth

    text: DownloadsStore.iconDownload
    foreground: root.foreground
    useActiveColor: false

    onPressed: function(b) {
      if (b === Qt.RightButton) DownloadsStore.openFolder()
      else root.toggle()
    }
  }
}
