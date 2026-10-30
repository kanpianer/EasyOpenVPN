import QtQuick
import QtQuick.Window
import QtQuick.Effects
import qs.Commons

// OpenVPN mark from assets/OpenvpnLogo.png, colorized with MultiEffect so the
// white artwork follows the bar/panel foreground and state colors. This is the
// same rendering path the Omarchy system tray uses for symbolic icons.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Image {
    id: iconImage
    anchors.fill: parent
    source: Qt.resolvedUrl("assets/OpenvpnLogo.png")
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels so the PNG stays crisp on HiDPI outputs.
    sourceSize.width: Math.round(Math.min(root.width, root.height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(root.width, root.height) * Screen.devicePixelRatio)
    smooth: true
    mipmap: true
    // Kept as a hidden layer so MultiEffect can sample it as a texture.
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: iconImage
    source: iconImage
    colorization: 1.0
    colorizationColor: root.color
  }
}
