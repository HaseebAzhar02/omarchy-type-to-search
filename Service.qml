import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Type to search: while the focused workspace has no windows, an invisible
// 1x1 layer surface holds keyboard focus (on-demand, so it never blocks a
// window or another panel). The first printable key opens the Omarchy menu
// (the one Super+Space opens) with that text already in its search line.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string layerNamespace: "type-to-search"

  // ---- When to listen -------------------------------------------------------

  readonly property var focusedMonitor: Hyprland.focusedMonitor
  readonly property var workspace: focusedMonitor ? focusedMonitor.activeWorkspace : null

  readonly property bool workspaceEmpty: {
    var ws = root.workspace
    if (!ws) return false
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var w = list[i].workspace
      if (w && w.id === ws.id) return false
    }
    return true
  }

  // A special workspace (scratchpad) shown over the desktop owns the focus.
  // Hyprland reports it with activespecial>>NAME,MONITOR (empty NAME = closed).
  property var specialByMonitor: ({})
  readonly property bool specialShown: {
    // A focused window on a special workspace settles it whatever else says.
    var active = Hyprland.activeToplevel
    if (active && active.workspace && active.workspace.id < 0) return true
    var mon = root.focusedMonitor
    if (!mon) return true
    if (mon.name in root.specialByMonitor) return root.specialByMonitor[mon.name] !== ""
    var ipc = mon.lastIpcObject
    // Unknown yet (monitors not read since start): stay out of the way.
    if (!ipc || !ipc.specialWorkspace) return true
    return !!ipc.specialWorkspace.name
  }

  // Nothing is armed until Hyprland's monitor state has been read once.
  property bool ready: false
  Timer { id: readyTimer; interval: 400; onTriggered: root.ready = true }

  readonly property bool armed: ready && workspaceEmpty && !specialShown

  // ---- Keeping focus --------------------------------------------------------

  // Hyprland hands an on-demand layer the keyboard when it maps. When focus is
  // lost while still armed (menu closed, workspace switched, unlocked), the
  // surface is unmapped and mapped again to take it back. Attempts are capped
  // so a compositor that refuses focus can never cause a remap loop.
  property bool parked: false
  property int attempts: 0
  readonly property int maxAttempts: 3

  onArmedChanged: { root.attempts = 0; root.typed = ""; if (armed) regrabTimer.restart() }
  onWorkspaceChanged: { root.attempts = 0; regrabTimer.restart() }

  function regrab() {
    if (!root.armed || keys.activeFocus) return
    if (root.attempts >= root.maxAttempts) return
    root.attempts += 1
    root.parked = true
    unparkTimer.restart()
  }

  Timer { id: regrabTimer; interval: 120; onTriggered: root.regrab() }
  Timer { id: unparkTimer; interval: 40; onTriggered: root.parked = false }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var data = event ? String(event.data) : ""
      if (name === "activespecial") {
        var cut = data.lastIndexOf(",")
        var next = ({})
        for (var k in root.specialByMonitor) next[k] = root.specialByMonitor[k]
        next[data.slice(cut + 1)] = data.slice(0, cut)
        root.specialByMonitor = next
      } else if (name === "closelayer" && data !== root.layerNamespace) {
        // Menu, panel or dialog went away: take the keyboard back.
        root.attempts = 0
        regrabTimer.restart()
      } else if (name === "activewindow" && (data === "," || data === "")) {
        regrabTimer.restart()
      } else if (name === "closewindow") {
        root.attempts = 0
        regrabTimer.restart()
      }
    }
  }

  // ---- Typing ---------------------------------------------------------------

  // Text typed into this surface before the menu took the keyboard.
  property string typed: ""

  function ipc(target, method, args) {
    var result = IpcRegistry.call(target, method, args)
    return result && result.ran === true
  }

  // The menu was summoned and the typed text is still waiting to go in.
  property bool summoned: false

  function summonMenu() {
    if (root.ipc("shell", "summon", ["omarchy.menu", JSON.stringify({ menu: "root" })])) return
    Quickshell.execDetached(["omarchy-menu", "summon", "root"])
  }

  function pushFilter() {
    if (root.ipc("shell", "call", ["omarchy.menu", "setFilter", root.typed])) return
    // CLI fallback: the text is an argument, never part of a command line.
    Quickshell.execDetached(["omarchy-shell", "shell", "call", "omarchy.menu", "setFilter", root.typed])
  }

  // The menu maps a fresh fullscreen window on each open, and its first search
  // keystroke pins the card's top where it sits at that moment. Sent before the
  // window has its real height, the card pins near the top of the screen. So
  // the text waits until the menu has mapped and taken the keyboard from this
  // surface, and goes in before any key the menu itself receives.
  function deliver() {
    if (!root.summoned) return
    root.summoned = false
    deliverFallback.stop()
    if (root.typed) root.pushFilter()
  }

  Timer { id: deliverFallback; interval: 700; onTriggered: root.deliver() }

  function handleKey(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return

    if (event.key === Qt.Key_Backspace) {
      if (root.typed) {
        root.typed = root.typed.slice(0, -1)
        if (!root.summoned) root.pushFilter()
      }
      event.accepted = true
      return
    }

    var text = String(event.text || "")
    if (!text || /[\x00-\x1f\x7f]/.test(text)) return
    // A leading space alone is not a search.
    if (!root.typed && !text.trim()) return

    var first = root.typed === "" && !root.summoned
    root.typed += text
    event.accepted = true
    if (first) {
      root.summoned = true
      deliverFallback.restart()
      root.summonMenu()
    } else if (!root.summoned) {
      root.pushFilter()
    }
  }

  PanelWindow {
    id: catcher
    visible: root.armed && !root.parked
    color: "transparent"
    implicitWidth: 1
    implicitHeight: 1
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Ignore
    // Never takes a click: the pointer passes straight to the desktop.
    mask: Region {}
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) { root.handleKey(event) }
      onActiveFocusChanged: {
        // Losing focus while summoned means the menu has the keyboard now:
        // hand it the text first. Either way the next search starts fresh.
        if (!activeFocus) root.deliver()
        root.summoned = false
        root.typed = ""
        if (activeFocus) root.attempts = 0
      }
    }

    onVisibleChanged: if (visible) Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // Troubleshooting: omarchy-shell type-to-search state
  ShellIpc {
    target: "type-to-search"
    function state(): string {
      return JSON.stringify({
        armed: root.armed,
        ready: root.ready,
        workspaceEmpty: root.workspaceEmpty,
        specialShown: root.specialShown,
        mapped: catcher.visible,
        focused: keys.activeFocus,
        attempts: root.attempts
      })
    }
  }

  Component.onCompleted: { Hyprland.refreshMonitors(); readyTimer.start() }
}
