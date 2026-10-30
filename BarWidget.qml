import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.kanpianer.easy-openvpn"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  OpenVpnService {
    id: service
  }

  // Backstop for the 9-second connect limit. The privileged guard also aborts
  // an unfinished handshake, but an older installed guard copy may still use a
  // longer timeout; when passwordless mode is active this timer can cancel
  // without a password prompt. Cancelling never engages the kill switch.
  Timer {
    id: connectTimeout
    interval: 9000
    repeat: false
    running: service.passwordless && service.connecting && !service.connected && !service.blocked
    onTriggered: {
      if (service.connecting && !service.connected && !service.blocked) {
        service.lastAttemptFailed = true
        service.disconnectVpn()
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: Component {
      OpenVpnIcon {
        iconSize: Style.bar.iconCanvas
        color: service.blocked
          ? "#ef4444"
          : (service.connected ? "#22c55e" : (root.bar ? root.bar.foreground : Color.foreground))
      }
    }
    tooltipText: service.blocked
      ? "EasyOpenVPN: Kill switch active — network blocked"
      : service.connected
        ? "EasyOpenVPN: Connected (" + (service.ip !== "" ? service.ip : service.iface) + ")"
        : service.connecting
          ? "EasyOpenVPN: Connecting…"
          : service.pendingAction === "connect"
            ? "EasyOpenVPN: Connecting…"
            : "EasyOpenVPN: Disconnected"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        service.toggle()
      } else {
        root.toggle()
      }
    }
  }
}
