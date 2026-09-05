import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Downloads: what just landed in the download folder, one click from the bar.
Panel {
  id: root

  moduleName: "jodarini.downloads"
  ipcTarget: "jodarini.downloads"

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
      // Claim the store before showing: if another monitor's copy held the
      // popout, the bar closes it when we request ours, and its close must
      // not hide the window we are opening.
      DownloadsStore.owner = root
      DownloadsStore.show()
      if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
    } else if (DownloadsStore.owner === root) {
      DownloadsStore.owner = null
      DownloadsStore.hide()
      if (bar && typeof bar.releasePopout === "function") bar.releasePopout(root)
    } else if (bar && typeof bar.releasePopout === "function") {
      // Closed because another copy took the popout. Stand down quietly.
      bar.releasePopout(root)
    }
  }

  Connections {
    target: DownloadsStore
    // Only the close direction is mirrored, and only by the copy that is
    // actually open: the store never opens without a copy opening first, but
    // it can close itself (Esc), and then the owning copy has to release the
    // popout. Reacting to opens here is what made two copies fight over one
    // popout after the shell update.
    function onOpenChanged() {
      if (!DownloadsStore.open && root.opened) root.close()
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
