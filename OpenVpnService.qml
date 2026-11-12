import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property string scriptPath: {
    var resolved = Qt.resolvedUrl("scripts/openvpn-ctl").toString().replace(/^file:\/\//, "")
    return resolved || (Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.kanpianer.easy-openvpn/scripts/openvpn-ctl")
  }

  // connected is only true once OpenVPN reports "Initialization Sequence
  // Completed" and the tunnel device holds an IPv4 address. A running OpenVPN
  // that is still handshaking is reported as connecting instead.
  property bool connected: false
  property bool running: false
  property bool connecting: false
  property bool blocked: false
  property bool blockedEnforced: false
  property bool passwordless: false
  property bool passwordlessPrompted: false
  readonly property bool settingUpPasswordless: setupProc.running
  property string blockedReason: ""
  property string blockedSince: ""

  property string iface: ""
  property string ip: ""
  property string config: ""
  property string configName: ""
  property string configDir: ""
  property var configs: []
  property var authConfigs: []
  property bool hasAuth: false
  property string username: ""
  property string bytesText: ""
  property string statusSummary: ""
  property string logTail: ""
  property string lastError: ""
  property string controlError: ""

  // Immediate UI feedback while a privileged connect/disconnect is running.
  // The real state still comes from the script on the next poll.
  property string pendingAction: ""
  property double pendingSince: 0
  property bool pendingSawRunning: false
  property bool lastAttemptFailed: false

  readonly property bool busy: controlProc.running || pickerProc.running || setupProc.running
  readonly property bool active: connected || connecting || pendingAction === "connect"

  function hasSavedAuthFor(path) {
    if (!authConfigs || authConfigs.length === 0) return false
    return authConfigs.indexOf(path) !== -1
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = [scriptPath, "status"]
    statusProc.running = true
  }

  function toggle() {
    if (blocked) {
      disconnectVpn()
    } else if (connected || connecting || pendingAction === "connect") {
      disconnectVpn()
    } else {
      connectVpn()
    }
  }

  function connectVpn() {
    if (controlProc.running) return
    pendingAction = "connect"
    pendingSince = Date.now()
    pendingSawRunning = false
    lastAttemptFailed = false
    runControl("connect")
  }

  function disconnectVpn() {
    if (controlProc.running) return
    pendingAction = "disconnect"
    pendingSince = Date.now()
    runControl("disconnect")
  }

  function setConfig(path) {
    if (!path) return
    root.config = path
    var parts = path.split("/")
    root.configName = parts[parts.length - 1]
    runControl("set_config", [path])
  }

  // Remove a profile from the node list. The helper refuses anything that is
  // not one of the profiles it lists, and trashes the file instead of deleting
  // it outright when gio is available.
  function removeProfile(path) {
    if (!path) return
    removeProfiles([path])
  }

  function removeProfiles(paths) {
    if (!paths || paths.length === 0) return
    var deletedMap = Object.create(null)
    for (var i = 0; i < paths.length; i++) {
      if (paths[i]) deletedMap[paths[i]] = true
    }
    var nextConfigs = []
    for (var j = 0; j < root.configs.length; j++) {
      if (!deletedMap[root.configs[j]]) nextConfigs.push(root.configs[j])
    }
    root.configs = nextConfigs
    runControl("remove_profile", paths)
  }

  function setOrder(orderList) {
    if (!orderList || orderList.length === 0) return
    runControl("set_order", orderList)
  }

  function pickConfigFile() {
    if (pickerProc.running) return
    pickerProc.command = [scriptPath, "pick_file"]
    pickerProc.running = true
  }

  function addProfile() {
    if (pickerProc.running) return
    pickerProc.command = [scriptPath, "add_profile"]
    pickerProc.running = true
  }

  function openFolder() {
    if (pickerProc.running) return
    pickerProc.command = [scriptPath, "open_folder"]
    pickerProc.running = true
  }

  function setCredentials(user, pass) {
    runControl("set_credentials", [], user + "\n" + pass + "\n" + root.config + "\n")
  }

  function clearCredentials() {
    runControl("clear_credentials", [root.config])
  }

  function setupPasswordless() {
    if (setupProc.running) return
    setupProc.command = [scriptPath, "setup_passwordless"]
    setupProc.running = true
  }

  function dismissPasswordless() {
    runControl("dismiss_passwordless")
  }

  function removePasswordless() {
    if (setupProc.running) return
    setupProc.command = [scriptPath, "remove_passwordless"]
    setupProc.running = true
  }

  property var _controlQueue: []

  function runControl(action, extraArgs, stdinData) {
    if (controlProc.running) {
      var q = (root._controlQueue || []).slice()
      q.push({ action: action, extraArgs: extraArgs || [], stdinData: stdinData || "" })
      root._controlQueue = q
      return
    }
    _runControlDirect(action, extraArgs, stdinData)
  }

  function _runControlDirect(action, extraArgs, stdinData) {
    controlError = ""
    var cmd = [scriptPath, action]
    if (extraArgs && extraArgs.length > 0) {
      for (var i = 0; i < extraArgs.length; i++) {
        cmd.push(extraArgs[i])
      }
    }
    controlProc.stdinData = stdinData || ""
    controlProc.command = cmd
    controlProc.running = true
  }

  function settlePending() {
    if (pendingAction === "") return
    var elapsed = Date.now() - pendingSince
    if (elapsed > 120000) {
      pendingAction = ""
      return
    }
    if (pendingAction === "connect") {
      // A running process that disappears again has finished its attempt: the
      // 9-second handshake timeout aborts it, or OpenVPN failed and exited.
      if (connected || blocked) {
        pendingAction = ""
        return
      }
      if (pendingSawRunning && !running && !connecting) {
        pendingAction = ""
        lastAttemptFailed = true
        return
      }
      // Before OpenVPN has appeared, allow for a slow pkexec prompt. After
      // 15 seconds with nothing running, treat the action as failed.
      if (elapsed > 15000 && !running && !connecting) pendingAction = ""
    } else if (pendingAction === "disconnect") {
      if (!running && !connecting && !blocked) pendingAction = ""
    }
  }

  function parseStatus(raw) {
    try {
      var data = JSON.parse(raw)
      root.connected = data.connected === true
      root.running = data.running === true
      root.connecting = data.connecting === true
      if (root.pendingAction === "connect" && root.running) root.pendingSawRunning = true
      root.blocked = data.blocked === true
      root.blockedEnforced = data.blocked_enforced === true
      root.passwordless = data.passwordless === true
      root.passwordlessPrompted = data.passwordless_prompted === true
      root.blockedReason = String(data.blocked_reason || "")
      root.blockedSince = String(data.blocked_since || "")
      root.iface = String(data.iface || "")
      root.ip = String(data.ip || "")
      root.config = String(data.config || "")
      root.configName = String(data.config_name || "")
      root.configDir = String(data.config_dir || "")
      root.configs = data.configs || []
      root.authConfigs = data.auth_configs || []
      root.hasAuth = data.has_auth === true
      root.username = String(data.username || "")
      root.bytesText = String(data.bytes_text || "")
      root.statusSummary = String(data.status_summary || "")
      root.logTail = String(data.log_tail || "")

      root.settlePending()
      root.lastError = ""
    } catch (e) {
      console.warn("EasyOpenVPN parseStatus error: " + e)
    }
  }

  Timer {
    id: pollTimer
    // Poll faster than the old 2.5 s so the UI reflects the real tunnel state
    // (and an engaged kill switch) promptly.
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  property string _statusBuf: ""

  Process {
    id: statusProc
    command: [root.scriptPath, "status"]
    stdout: SplitParser {
      onRead: function(line) {
        root._statusBuf += line + "\n"
      }
    }
    onRunningChanged: {
      if (running) {
        root._statusBuf = ""
      } else {
        if (root._statusBuf.trim().length > 0) {
          root.parseStatus(root._statusBuf.trim())
        }
      }
    }
  }

  Process {
    id: controlProc
    property string stdinData: ""
    stdinEnabled: true
    stderr: SplitParser {
      onRead: function(line) {
        var text = line.trim()
        if (text !== "") root.controlError = text
      }
    }
    onStarted: {
      if (stdinData !== "") {
        write(stdinData)
        stdinData = ""
      }
    }
    onRunningChanged: {
      if (!running) {
        if (root._controlQueue && root._controlQueue.length > 0) {
          var q = root._controlQueue.slice()
          var next = q.shift()
          root._controlQueue = q
          Qt.callLater(function() {
            root._runControlDirect(next.action, next.extraArgs, next.stdinData)
          })
        } else {
          Qt.callLater(function() { root.refresh() })
        }
      }
    }
  }

  Process {
    id: pickerProc
    onRunningChanged: {
      if (!running) {
        Qt.callLater(function() { root.refresh() })
      }
    }
  }

  Process {
    id: setupProc
    stderr: SplitParser {
      onRead: function(line) {
        var text = line.trim()
        if (text !== "") console.log("EasyOpenVPN setup-passwordless: " + text)
      }
    }
    onRunningChanged: {
      if (!running) {
        Qt.callLater(function() { root.refresh() })
      }
    }
  }

  Component.onCompleted: {
    refresh()
  }
}
