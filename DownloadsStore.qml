pragma Singleton

import QtCore
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Singleton {
  id: root

  property int freshMinutes: 5
  property url folderUrl: StandardPaths.writableLocation(StandardPaths.DownloadLocation)

  readonly property string folderPath: String(root.folderUrl).replace(/^file:\/\//, "")

  readonly property string homePath:
    String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
  function plain(s) { return String(s || "").replace(/[<>]/g, "") }

  readonly property string displayPath: {
    var home = root.homePath
    var path = root.folderPath
    if (home !== "" && path.indexOf(home) === 0) return "~" + path.slice(home.length)
    return path
  }

  readonly property string iconDownload: "\uF019"
  readonly property string iconFolder: "\uF07C"
  readonly property string iconFile: "\uF15B"
  readonly property string iconImage: "\uF1C5"
  readonly property string iconPdf: "\uF1C1"
  readonly property string iconArchive: "\uF1C6"
  readonly property string iconAudio: "\uF1C7"
  readonly property string iconVideo: "\uF1C8"
  readonly property string iconCode: "\uF1C9"
  readonly property string iconText: "\uF0F6"

  property string fontFamily: Style.font.family

  property var files: []
  property int freshCount: 0
  property int totalCount: 0
  property int hiddenCount: 0
  property int uncountedCount: 0
  property bool showAll: true
  property double now: Date.now()
  property string draggingUrl: ""
  property bool open: false
  // The panel copy that currently owns the open window. Two monitors mean
  // two copies of the bar widget sharing this one store; only the owner may
  // hide the window or hand the popout around, or the copies start closing
  // each other.
  property var owner: null
  property int selectedIndex: -1

  readonly property int maxRows: 200
  readonly property int maxScan: 2000

  property bool polling: false
  property url scanFolder: ""

  function configure(minutes, folder) {
    var n = Number(minutes)
    if (isFinite(n) && n >= 1 && n <= 1440) root.freshMinutes = Math.round(n)
    if (folder) root.folderUrl = folder
  }

  function show() {
    root.rescan()
    root.open = true
    root.selectedIndex = 0
  }
  function hide() { root.open = false }
  function toggle() { root.open ? root.hide() : root.show() }

  function isPartial(name) {
    return /\.(crdownload|part|partial|download|tmp|opdownload)$/i.test(String(name))
  }

  function suffixOf(name) {
    var m = /\.([A-Za-z0-9]+)$/.exec(String(name))
    return m ? m[1].toLowerCase() : ""
  }

  function iconFor(name) {
    var s = root.suffixOf(name)
    if (/^(png|jpg|jpeg|gif|webp|bmp|svg|avif|heic|ico|tiff?)$/.test(s)) return root.iconImage
    if (s === "pdf") return root.iconPdf
    if (/^(zip|tar|gz|tgz|bz2|xz|7z|rar|zst|deb|rpm|pkg|iso|img|dmg|appimage)$/.test(s)) return root.iconArchive
    if (/^(mp3|wav|flac|ogg|m4a|aac|opus|wma)$/.test(s)) return root.iconAudio
    if (/^(mp4|mkv|mov|avi|webm|m4v|mpg|mpeg|wmv)$/.test(s)) return root.iconVideo
    if (/^(js|ts|json|py|rb|sh|c|h|cpp|rs|go|java|qml|html|css|xml|yml|yaml|toml)$/.test(s)) return root.iconCode
    if (/^(txt|md|csv|log|rtf|doc|docx|odt|xls|xlsx|ods|ppt|pptx|odp|epub)$/.test(s)) return root.iconText
    return root.iconFile
  }

  function formatSize(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1024) return n + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function formatAge(ms) {
    var secs = Math.max(0, Math.round((root.now - ms) / 1000))
    if (secs < 45) return "just now"
    var mins = Math.round(secs / 60)
    if (mins < 60) return mins + " min"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + " h"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + " d"
    var weeks = Math.floor(days / 7)
    if (weeks < 5) return weeks + " w"
    return Math.floor(days / 30) + " mo"
  }

  function rebuild() {
    var out = []
    var fresh = 0
    var total = 0
    var skipped = 0
    var cutoff = root.now - root.freshMinutes * 60000

    var count = folderModel.count
    var scan = Math.min(count, root.maxScan)

    for (var i = 0; i < scan; i++) {
      var name = String(folderModel.get(i, "fileName") || "")
      if (name === "" || root.isPartial(name)) continue

      var mod = folderModel.get(i, "fileModified")
      var ms = mod ? mod.getTime() : 0
      var isFresh = ms >= cutoff

      total++
      if (isFresh) fresh++

      if (!root.showAll && !isFresh) continue
      if (out.length >= root.maxRows) { skipped++; continue }

      out.push({
        name: name,
        url: String(folderModel.get(i, "fileUrl") || ""),
        path: String(folderModel.get(i, "filePath") || ""),
        size: Number(folderModel.get(i, "fileSize")) || 0,
        modified: ms,
        fresh: isFresh
      })
    }

    root.files = out
    root.freshCount = fresh
    root.totalCount = total
    root.hiddenCount = skipped
    root.uncountedCount = count - scan
  }

  function tick() {
    root.now = Date.now()
    if (root.polling) { root.readViaHelper(); return }
    if (String(root.scanFolder) === "" || folderModel.status !== FolderListModel.Ready) return

    root.rebuild()

    if (folderModel.count > root.maxScan) {
      root.polling = true
      root.scanFolder = ""
      root.readViaHelper()
    }
  }

  function rescan() {
    if (probeProc.running) return
    if (!root.folderPath) { Qt.callLater(root.rescan); return }
    probeProc.command = [root.helper, "probe", root.folderPath]
    probeProc.running = true
  }

  property var folderProbe: null

  function applyProbe(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || data.ok !== true) return
    root.folderProbe = data

    if (data.over === true) {
      root.polling = true
      if (String(root.scanFolder) !== "") root.scanFolder = ""
      root.readViaHelper()
      return
    }

    root.polling = false
    if (String(root.scanFolder) === "") root.scanFolder = root.folderUrl
    else root.tick()
  }

  function readViaHelper() {
    if (listProc.running) return
    listProc.command = [root.helper, "list", root.folderPath]
    listProc.running = true
  }

  function fileUrl(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  function applyPayload(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || data.ok !== true || !Array.isArray(data.files)) return

    var out = []
    var fresh = 0
    var total = 0
    var skipped = 0
    var cutoff = root.now - root.freshMinutes * 60000

    for (var i = 0; i < data.files.length; i++) {
      var f = data.files[i]
      var name = String(f.name || "")
      if (name === "" || root.isPartial(name)) continue

      var ms = Number(f.modified) || 0
      var isFresh = ms >= cutoff

      total++
      if (isFresh) fresh++

      if (!root.showAll && !isFresh) continue
      if (out.length >= root.maxRows) { skipped++; continue }

      out.push({
        name: name,
        url: root.fileUrl(f.path),
        path: String(f.path || ""),
        size: Number(f.size) || 0,
        modified: ms,
        fresh: isFresh
      })
    }

    root.files = out
    root.freshCount = fresh
    root.totalCount = total
    root.hiddenCount = skipped
    root.uncountedCount = Number(data.hidden) || 0
  }

  function scheduleTick() { coalesce.restart() }

  function openFolder() {
    var target = root.folderPath
    if (target.length > 1 && target.charAt(0) === "/")
      Quickshell.execDetached(["xdg-open", target])
  }

  function openFile(path) {
    var target = String(path || "")
    if (target.length > 1 && target.charAt(0) === "/")
      Quickshell.execDetached(["xdg-open", target])
  }

  function openSelected() {
    if (root.selectedIndex >= 0 && root.selectedIndex < root.files.length)
      root.openFile(root.files[root.selectedIndex].path)
  }

  onShowAllChanged: root.tick()

  onFolderUrlChanged: {
    root.polling = false
    root.folderProbe = null
    root.scanFolder = ""
    root.rescan()
  }

  Timer {
    id: coalesce
    interval: 250
    repeat: false
    onTriggered: root.tick()
  }

  readonly property string helper:
    Qt.resolvedUrl("bin/downloads").toString().replace(/^file:\/\//, "")

  Component.onCompleted: Qt.callLater(root.rescan)

  Process {
    id: probeProc
    stdout: StdioCollector {
      onStreamFinished: root.applyProbe(text)
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(text)
    }
  }

  FolderListModel {
    id: folderModel
    folder: root.scanFolder
    showDirs: false
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Time
    sortReversed: false
    onCountChanged: root.scheduleTick()
    onStatusChanged: if (status === FolderListModel.Ready) root.scheduleTick()
  }

  Timer {
    interval: root.open ? 20000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
  }

  FloatingWindow {
    id: win

    visible: root.open
    title: "Downloads"
    color: Color.popups.background
    implicitWidth: Style.space(520)

    readonly property int rowStride: Style.space(36) + Style.space(2)
    readonly property int chromeHeight: Style.space(104) + Style.space(10) + Style.spacing.hairline
    readonly property int listHeight: Math.min(Style.space(620),
      Math.max(Style.space(160), Math.max(1, root.files.length) * rowStride))
    implicitHeight: chromeHeight + listHeight

    minimumSize: Qt.size(Style.space(360), Style.space(180))

    onVisibleChanged: {
      if (!visible && root.open) {
        root.open = false
      } else if (visible) {
        root.selectedIndex = 0
        Qt.callLater(function() {
          if (win.visible) {
            list.positionViewAtIndex(Math.max(0, root.selectedIndex), ListView.Beginning)
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "title:^Downloads$"])
          }
        })
      }
    }

    FocusScope {
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      Keys.onEscapePressed: root.hide()
      Keys.onReturnPressed: root.openSelected()
      Keys.onEnterPressed: root.openSelected()
      Keys.onPressed: function(event) {
        if (event.text === "j") {
          root.selectedIndex = (root.selectedIndex + 1) % Math.max(1, root.files.length)
          list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          event.accepted = true
        } else if (event.text === "k") {
          root.selectedIndex = root.files.length === 0 ? 0
            : (root.selectedIndex - 1 + root.files.length) % root.files.length
          list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          event.accepted = true
        } else if (event.text === "H") {
          root.showAll = false
          event.accepted = true
        } else if (event.text === "L") {
          root.showAll = true
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.openSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectedIndex = (root.selectedIndex + 1) % Math.max(1, root.files.length)
          list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectedIndex = root.files.length === 0 ? 0
            : (root.selectedIndex - 1 + root.files.length) % root.files.length
          list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: root.iconDownload
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            renderType: Text.NativeRendering
            color: Color.foreground
          }

          Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: false
            text: root.displayPath
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
            color: Color.foreground
          }

          // A plain segmented filter in place of the animated ButtonGroup.
          // The shared Button paints its state through a 120ms ColorAnimation
          // that reads as a flash here, so this control switches colors
          // instantly. Same visual tokens otherwise: selected chip uses the
          // shared selected-fill gray.
          Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: seg0.implicitWidth + seg1.implicitWidth
            implicitHeight: Math.max(seg0.implicitHeight, seg1.implicitHeight)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              color: Util.alpha(Color.foreground, 0.06)
            }

            Row {
              anchors.fill: parent
              spacing: Style.space(0)

              SegFilterChip {
                id: seg0
                label: "Last " + root.freshMinutes + " min"
                selected: !root.showAll
                onClicked: root.showAll = false
              }
              SegFilterChip {
                id: seg1
                label: "All"
                selected: root.showAll
                onClicked: root.showAll = true
              }
            }
          }

          Button {
            Layout.alignment: Qt.AlignVCenter
            iconText: root.iconFolder
            tooltipText: root.plain("Open " + root.displayPath)
            foreground: Color.muted
            accent: Color.accent
            fontFamily: root.fontFamily
            iconSize: Style.font.iconSmall
            onClicked: root.openFolder()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          color: Util.alpha(Color.foreground, 0.10)
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          visible: root.files.length > 0
          clip: true
          spacing: Style.space(2)
          model: root.files
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationWraps: true
          currentIndex: root.selectedIndex
          highlightMoveDuration: 0

          delegate: DownloadRow {
            required property var modelData
            width: list.width
            store: root
            file: modelData || ({})
            selected: !!modelData
              && root.selectedIndex >= 0 && root.selectedIndex < root.files.length
              && !!(root.files[root.selectedIndex])
              && modelData.path === root.files[root.selectedIndex].path
            onActivated: {
              var p = modelData ? String(modelData.path || "") : ""
              var files = root.files
              for (var i = 0; i < files.length; i++)
                if (files[i] && String(files[i].path || "") === p) { root.selectedIndex = i; break }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.files.length === 0
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.showAll
            ? "Nothing in " + root.displayPath
            : "Nothing in the last " + root.freshMinutes + " minutes.\n"
              + (root.uncountedCount > 0 ? "More than " : "")
              + root.totalCount + " files in the folder."
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.hiddenCount > 0 || root.uncountedCount > 0
          textFormat: Text.PlainText
          text: root.uncountedCount > 0
            ? "Newest " + root.files.length + " of more than " + root.maxScan + " files"
            : "+ " + root.hiddenCount + " more not shown"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          visible: root.files.length > 0
          color: Util.alpha(Color.foreground, 0.10)
        }

        Text {
          Layout.fillWidth: true
          visible: root.files.length > 0
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "j/k navigate · Enter open · H/L filter"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }
      }
    }
  }
}
