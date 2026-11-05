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
  readonly property string iconAudio: "\uF001"
  readonly property string iconVideo: "\uF03D"
  readonly property string iconCode: "\uF120"
  readonly property string iconWord: "\uF15C"
  readonly property string iconExcel: "\uF1C3"
  readonly property string iconPowerpoint: "\uF1C4"

  property string fontFamily: Style.font.family

  property var files: []
  property int freshCount: 0
  property int totalCount: 0
  property int hiddenCount: 0
  property int uncountedCount: 0
  property bool showAll: true
  // What the search field holds. The field is the only thing that writes it.
  property string query: ""
  property double now: Date.now()
  // Paths of the files in the drag under way, so their rows can show it.
  property var draggingPaths: ({})
  property bool open: false
  // The panel copy that currently owns the open window. Two monitors mean
  // two copies of the bar widget sharing this one store; only the owner may
  // hide the window or hand the popout around, or the copies start closing
  // each other.
  property var owner: null

  // Selection, kept by path rather than by row: a rescan rebuilds `files`,
  // and a download landing at the top shifts every row down one. The cursor
  // is the row the keyboard is on; the anchor is where a Shift range starts.
  property var selection: ({})
  readonly property int selectionCount: Object.keys(root.selection).length
  property string anchorPath: ""
  property int cursorIndex: -1

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
    // Every opening starts from the whole list, in the list keys, rather
    // than from wherever the last search left off.
    searchField.text = ""
    searchField.focus = false
    root.rescan()
    root.open = true
    root.selectOnly(0)
  }
  function hide() { root.open = false }
  function toggle() { root.open ? root.hide() : root.show() }

  function isPartial(name) {
    return /\.(crdownload|part|partial|download|tmp|opdownload)$/i.test(String(name))
  }

  // Every word of the query has to appear somewhere in the name, in any
  // order and any case, so "inv 2026" finds "Invoice-March-2026.pdf".
  // A function rather than a binding: the scans run from onQueryChanged,
  // and a binding on `query` may not have caught up by then.
  function queryTerms() {
    return root.query.toLowerCase().split(/\s+/).filter(function(t) { return t !== "" })
  }

  function matchesTerms(name, terms) {
    var lower = String(name).toLowerCase()
    for (var i = 0; i < terms.length; i++)
      if (lower.indexOf(terms[i]) < 0) return false
    return true
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
    if (/^(doc|docx|odt|rtf)$/.test(s)) return root.iconWord
    if (/^(xls|xlsx|ods|csv)$/.test(s)) return root.iconExcel
    if (/^(ppt|pptx|odp)$/.test(s)) return root.iconPowerpoint
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
    var terms = root.queryTerms()

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
      if (!root.matchesTerms(name, terms)) continue
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

    root.setFiles(out)
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

  // The query the helper was last sent. A polled folder is searched by the
  // helper, before its row cap, so a match among older files still makes it
  // back. A read that went out before the last keystroke goes again once it
  // is done; see listProc.
  property string listQuery: ""

  function readViaHelper() {
    if (listProc.running) return
    root.listQuery = root.query
    listProc.command = [root.helper, "list", root.folderPath, root.query]
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
    // The helper has already searched, but maybe for an older query; this
    // keeps the rows true to the field until the read that follows it lands.
    var terms = root.queryTerms()

    for (var i = 0; i < data.files.length; i++) {
      var f = data.files[i]
      var name = String(f.name || "")
      if (name === "" || root.isPartial(name)) continue

      var ms = Number(f.modified) || 0
      var isFresh = ms >= cutoff

      total++
      if (isFresh) fresh++

      if (!root.showAll && !isFresh) continue
      if (!root.matchesTerms(name, terms)) continue
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

    root.setFiles(out)
    root.freshCount = fresh
    root.totalCount = total
    root.hiddenCount = skipped
    root.uncountedCount = Number(data.hidden) || 0
  }

  // Every rescan hands over a fresh `files`. Keep the cursor on the file it
  // was on and drop selected files that are gone or filtered out, so nothing
  // invisible gets opened or dragged. One exception: sitting on the newest
  // file with nothing else picked follows the top of the list, so a download
  // that lands while the window is open is still the one Enter opens.
  function setFiles(out) {
    var prev = root.files[root.cursorIndex]
    var followTop = !prev
      || (root.cursorIndex === 0 && root.selectionCount === 1 && root.isSelected(prev.path))
    root.files = out
    if (followTop) { root.selectOnly(0); return }

    var at = ({})
    for (var i = 0; i < out.length; i++) at[out[i].path] = i
    var kept = ({})
    var dropped = false
    for (var p in root.selection) {
      if (p in at) kept[p] = true
      else dropped = true
    }
    if (dropped) root.selection = kept
    root.cursorIndex = (prev.path in at) ? at[prev.path] : Math.min(root.cursorIndex, out.length - 1)
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
    var picked = root.selectedFiles()
    for (var i = 0; i < picked.length; i++) root.openFile(picked[i].path)
  }

  function isSelected(path) { return !!root.selection[path] }

  function indexOfPath(path) {
    for (var i = 0; i < root.files.length; i++)
      if (root.files[i].path === path) return i
    return -1
  }

  // In list order, not the order they were picked, so a drop or a batch
  // open sees them newest first like the window does.
  function selectedFiles() {
    var out = []
    for (var i = 0; i < root.files.length; i++)
      if (root.selection[root.files[i].path]) out.push(root.files[i])
    return out
  }

  function selectOnly(index) {
    var f = root.files[index]
    var next = ({})
    if (f) next[f.path] = true
    root.selection = next
    root.anchorPath = f ? f.path : ""
    root.cursorIndex = f ? index : -1
  }

  function toggleAt(index) {
    var f = root.files[index]
    if (!f) return
    var next = Object.assign({}, root.selection)
    if (next[f.path]) delete next[f.path]
    else next[f.path] = true
    root.selection = next
    root.anchorPath = f.path
    root.cursorIndex = index
  }

  // From the anchor to `index`, replacing the selection, or adding to it
  // when Ctrl is held too. The anchor stays put, so a second Shift+click
  // re-pivots around the same row the way file managers do.
  function selectRange(index, additive) {
    if (!root.files[index]) return
    var from = root.indexOfPath(root.anchorPath)
    if (from < 0) { from = index; root.anchorPath = root.files[index].path }
    var next = additive ? Object.assign({}, root.selection) : ({})
    for (var i = Math.min(from, index); i <= Math.max(from, index); i++)
      next[root.files[i].path] = true
    root.selection = next
    root.cursorIndex = index
  }

  function selectAll() {
    var next = ({})
    for (var i = 0; i < root.files.length; i++) next[root.files[i].path] = true
    root.selection = next
  }

  // A plain press outside the selection selects that row on the spot, so
  // dragging it drags just it. A plain press inside the selection waits for
  // the release, so the whole selection can be dragged out together.
  function pressRow(index, modifiers) {
    if (modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) return
    var f = root.files[index]
    if (f && !root.isSelected(f.path)) root.selectOnly(index)
  }

  function clickRow(index, modifiers) {
    if (modifiers & Qt.ShiftModifier) root.selectRange(index, !!(modifiers & Qt.ControlModifier))
    else if (modifiers & Qt.ControlModifier) root.toggleAt(index)
    else root.selectOnly(index)
  }

  // j/k and the arrows move the cursor and select what lands under it,
  // wrapping at the ends. With Shift they stretch the selection from the
  // anchor instead, and stop at the ends: wrapping would flip the range.
  function moveCursor(step, extend) {
    var n = root.files.length
    if (n === 0) return
    if (extend) root.selectRange(Math.max(0, Math.min(n - 1, root.cursorIndex + step)), false)
    else root.selectOnly(((root.cursorIndex + step) % n + n) % n)
  }

  onShowAllChanged: root.tick()

  // A new query starts from its best match, the newest file that fits:
  // selecting the top row first lets setFiles carry that over to the new
  // list. A watched folder is already in memory, so it is filtered on every
  // keystroke. A polled one goes back to the helper, a process per read, so
  // a burst of typing settles first.
  onQueryChanged: {
    root.selectOnly(0)
    if (root.polling) root.scheduleTick()
    else root.tick()
    list.positionViewAtBeginning()
  }

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
    onRunningChanged: {
      if (!running && root.polling && root.listQuery !== root.query) root.readViaHelper()
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
        root.selectOnly(0)
        Qt.callLater(function() {
          if (win.visible) {
            list.positionViewAtIndex(Math.max(0, root.cursorIndex), ListView.Beginning)
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "title:^Downloads$"])
          }
        })
      }
    }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      function follow() {
        if (root.cursorIndex >= 0) list.positionViewAtIndex(root.cursorIndex, ListView.Contain)
      }

      // Back from the search field to the list keys with the filter kept, so
      // j/k, Shift and Ctrl+A work on just the matches. Clearing the field's
      // focus first matters: forcing focus onto the scope alone would hand it
      // straight back to the field, the scope's last focused child.
      function leaveSearch() {
        searchField.focus = false
        keys.forceActiveFocus()
      }

      // One layer per press: a search goes first, then the window.
      Keys.onEscapePressed: {
        if (root.query !== "") searchField.text = ""
        else root.hide()
      }
      Keys.onReturnPressed: root.openSelected()
      Keys.onEnterPressed: root.openSelected()
      Keys.onPressed: function(event) {
        var shift = !!(event.modifiers & Qt.ShiftModifier)
        if (event.text === "/" || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
          searchField.forceActiveFocus()
          searchField.selectAll()
          event.accepted = true
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
          root.selectAll()
          event.accepted = true
        } else if (event.text === "j" || event.text === "J" || event.key === Qt.Key_Down) {
          root.moveCursor(1, shift)
          keys.follow()
          event.accepted = true
        } else if (event.text === "k" || event.text === "K" || event.key === Qt.Key_Up) {
          root.moveCursor(-1, shift)
          keys.follow()
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

          // Search by name. While it has focus, letters are text, so the
          // list's letter keys (j/k, H/L) are off and the arrows stand in.
          TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            placeholderText: "Search by name"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            verticalPadding: Style.space(4)
            onTextChanged: root.query = text

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                root.moveCursor(event.key === Qt.Key_Down ? 1 : -1, !!(event.modifiers & Qt.ShiftModifier))
                keys.follow()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.openSelected()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                keys.leaveSearch()
                event.accepted = true
              }
            }
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
          currentIndex: root.cursorIndex
          highlightMoveDuration: 0

          delegate: DownloadRow {
            required property var modelData
            required property int index
            width: list.width
            store: root
            file: modelData || ({})
            selected: !!modelData && root.isSelected(modelData.path)
            current: index === root.cursorIndex
            // Picking a row is done typing: the keys go back to the list,
            // so j/k after a click move rather than land in the query.
            onRowPressed: function(modifiers) {
              if (searchField.activeFocus) keys.leaveSearch()
              root.pressRow(index, modifiers)
            }
            onRowClicked: function(modifiers) { root.clickRow(index, modifiers) }
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
          text: root.query.trim() !== ""
            ? "No names match “" + root.query.trim() + "”"
              + (root.showAll ? "" : " in the last " + root.freshMinutes + " minutes")
            : root.showAll
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
          text: root.selectionCount > 1
            ? root.selectionCount + " selected · Enter open all · drag to take all"
            : searchField.activeFocus
              ? "↑/↓ move · Enter open · Esc back to the list"
              : "j/k move · Shift+j/k select · Enter open · H/L filter · / search"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }
      }
    }
  }
}
