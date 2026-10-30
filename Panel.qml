import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.kanpianer.easy-openvpn"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string pendingDeleteNode: ""
  property bool pendingBatchDelete: false

  function deleteNode(path) {
    if (!path) return
    if (root.pendingDeleteNode === path) {
      root.pendingDeleteNode = ""
    }
    var targets = [path]
    root.removeCustomOrderItems(targets)
    if (root.isSelected(path)) {
      root.toggleSelect(path)
    }
    service.removeProfiles(targets)
  }

  function deleteSelectedNodes() {
    if (root.selectedConfigs.length === 0) return
    root.pendingBatchDelete = false
    var targets = root.selectedConfigs.slice()
    root.removeCustomOrderItems(targets)
    root.clearSelection()
    service.removeProfiles(targets)
  }

  function cancelDelete() {
    root.pendingDeleteNode = ""
    root.pendingBatchDelete = false
  }

  // Drag-and-drop state
  property bool dragActive: false
  property int dragSourceIndex: -1
  property int dragTargetIndex: -1
  property real dragStartY: 0
  property real dragCurrentY: 0
  property bool suppressClick: false

  // Multi-selection state
  property var selectedConfigs: []
  readonly property bool isAllSelected: displayConfigs.length > 0 && selectedConfigs.length === displayConfigs.length

  // Profile ordering
  property var customOrder: (root.settings && root.settings.profileOrder) ? root.settings.profileOrder : []

  onSettingsChanged: {
    if (root.settings && root.settings.profileOrder && root.settings.profileOrder.length > 0) {
      root.customOrder = root.settings.profileOrder
    }
  }

  readonly property var displayConfigs: {
    var raw = service.configs || []
    var ord = root.customOrder || []
    if (raw.length <= 1 || ord.length === 0) return raw

    var map = Object.create(null)
    for (var i = 0; i < raw.length; i++) {
      if (raw[i]) map[raw[i]] = true
    }

    var result = []
    for (var j = 0; j < ord.length; j++) {
      var p = String(ord[j] || "")
      if (map[p]) {
        result.push(p)
        map[p] = false
      }
    }
    for (var k = 0; k < raw.length; k++) {
      if (raw[k] && map[raw[k]]) {
        result.push(raw[k])
      }
    }
    return result
  }

  onDisplayConfigsChanged: {
    if (pendingDeleteNode !== "" && displayConfigs.indexOf(pendingDeleteNode) === -1) {
      pendingDeleteNode = ""
    }
    if (selectedConfigs.length === 0) return
    var validMap = Object.create(null)
    for (var i = 0; i < displayConfigs.length; i++) {
      validMap[displayConfigs[i]] = true
    }
    var next = []
    for (var j = 0; j < selectedConfigs.length; j++) {
      if (validMap[selectedConfigs[j]]) next.push(selectedConfigs[j])
    }
    if (next.length !== selectedConfigs.length) {
      selectedConfigs = next
    }
  }

  onSelectedConfigsChanged: {
    if (selectedConfigs.length === 0) {
      pendingBatchDelete = false
    }
  }

  function isSelected(path) {
    return selectedConfigs.indexOf(path) !== -1
  }

  function toggleSelect(path) {
    root.cancelDelete()
    var idx = selectedConfigs.indexOf(path)
    var list = selectedConfigs.slice()
    if (idx === -1) {
      list.push(path)
    } else {
      list.splice(idx, 1)
    }
    selectedConfigs = list
  }

  function toggleSelectAll() {
    root.cancelDelete()
    if (isAllSelected) {
      selectedConfigs = []
    } else {
      selectedConfigs = displayConfigs.slice()
    }
  }

  function clearSelection() {
    root.pendingBatchDelete = false
    selectedConfigs = []
  }

  function calculateDropIndex(yPos) {
    var count = configsRepeater.count
    if (count <= 1) return 0
    for (var i = 0; i < count; i++) {
      var item = configsRepeater.itemAt(i)
      if (item) {
        var itemMidY = item.y + item.height / 2
        if (yPos < itemMidY) return i
      }
    }
    return count - 1
  }

  function startDrag(index, yPos) {
    if (root.displayConfigs.length <= 1) return
    root.cancelDelete()
    root.dragActive = true
    root.dragSourceIndex = index
    root.dragTargetIndex = index
    root.dragStartY = yPos
    root.dragCurrentY = yPos
    root.suppressClick = true
  }

  function updateDrag(yPos) {
    if (!root.dragActive) return
    root.dragCurrentY = yPos
    root.dragTargetIndex = calculateDropIndex(yPos)

    if (panelFlick.contentHeight > panelFlick.height) {
      var yInView = configsColumn.mapToItem(panelFlick, 0, yPos).y
      if (yInView < Style.space(30) && panelFlick.contentY > 0) {
        panelFlick.contentY = Math.max(0, panelFlick.contentY - Style.space(8))
      } else if (yInView > panelFlick.height - Style.space(30) && panelFlick.contentY < panelFlick.contentHeight - panelFlick.height) {
        panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY + Style.space(8))
      }
    }
  }

  function finishDrag() {
    if (!root.dragActive) return
    var src = root.dragSourceIndex
    var tgt = root.dragTargetIndex
    root.dragActive = false
    root.suppressClick = true

    if (src !== tgt && src >= 0 && tgt >= 0) {
      var currentList = root.displayConfigs.slice()
      var item = currentList.splice(src, 1)[0]
      currentList.splice(tgt, 0, item)

      persistConfigOrder(currentList)
    }
  }

  function cancelDrag() {
    root.dragActive = false
    root.suppressClick = true
  }

  function persistConfigOrder(newOrder) {
    root.customOrder = newOrder
    service.setOrder(newOrder)
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      var entry = { id: root.moduleName }
      for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
      entry.profileOrder = newOrder
      root.settings = entry
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function removeCustomOrderItems(deletedPaths) {
    if (!root.customOrder || root.customOrder.length === 0) return
    var deletedMap = Object.create(null)
    for (var i = 0; i < deletedPaths.length; i++) {
      deletedMap[deletedPaths[i]] = true
    }
    var updated = []
    for (var j = 0; j < root.customOrder.length; j++) {
      if (!deletedMap[root.customOrder[j]]) {
        updated.push(root.customOrder[j])
      }
    }
    root.customOrder = updated
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      var entry = { id: root.moduleName }
      for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
      entry.profileOrder = updated
      root.settings = entry
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function profileName(path) {
    var parts = String(path || "").split("/")
    return parts[parts.length - 1]
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color deleteArmedColor: "#ef4444"

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  OpenVpnService {
    id: service
  }

  onOpenedChanged: {
    if (opened) {
      service.refresh()
      if (panelFlick) panelFlick.contentY = 0
    } else {
      cancelDelete()
      dragActive = false
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(headerCol.implicitHeight + scrollCol.implicitHeight + Style.spacing.panelPadding * 2 + Style.space(16), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.pendingBatchDelete || root.pendingDeleteNode !== "") root.cancelDelete()
        else if (root.dragActive) root.cancelDrag()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Version badge in the top-right corner without affecting panel layout or other elements
      BorderSurface {
        id: versionBadge
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(6)
        anchors.rightMargin: Style.space(12)
        implicitWidth: verText.implicitWidth + Style.space(12)
        implicitHeight: verText.implicitHeight + Style.space(4)
        color: Style.controlFill(false, false, root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
        radius: Style.cornerRadius
        z: 20

        Text {
          id: verText
          anchors.centerIn: parent
          text: "0.1"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        PanelToolTip {
          visible: versionMouse.containsMouse
          text: "EasyOpenVPN 0.1"
          fontFamily: root.fontFamily
        }

        MouseArea {
          id: versionMouse
          anchors.fill: parent
          hoverEnabled: true
        }
      }

      Item {
        id: panelContent
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding

        // --------------------------------------------------- FIXED TOP HEADER
        Column {
          id: headerCol
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(8)

          WheelHandler {
            onWheel: function(event) {
              if (event.angleDelta.y === 0 || panelFlick.contentHeight <= panelFlick.height) return
              var step = Style.space(40) * (event.angleDelta.y > 0 ? -1 : 1)
              panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY + step))
            }
          }

          // ------------------------------------------------------------- HERO
          PanelHero {
            id: hero
            width: parent.width
            title: "EasyOpenVPN"
            meta: service.blocked
              ? (service.blockedEnforced ? "Kill switch • network blocked" : "Kill switch failed • network may be reachable")
              : service.connected
                ? ("Connected • " + (service.ip !== "" ? service.ip : service.iface))
                : (service.connecting || service.pendingAction === "connect")
                  ? "Connecting…"
                  : (service.configName !== "" ? service.configName : "Disconnected")
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              OpenVpnIcon {
                iconSize: Style.font.display
                color: service.blocked ? "#ef4444" : (service.connected ? "#22c55e" : root.dim)
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: connectionSwitch
                checked: service.active
                // Stay clickable while the tunnel is handshaking so the switch
                // can cancel the attempt; only a running control process blocks it.
                busy: service.busy
                foreground: hero.foreground
                onToggled: service.toggle()

                PanelToolTip {
                  visible: connectionSwitch.containsMouse
                  text: service.blocked
                    ? "Restore network and stop the kill switch"
                    : service.connected
                      ? "Disconnect EasyOpenVPN"
                      : service.connecting
                        ? "Cancel connection"
                        : "Connect EasyOpenVPN"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          Text {
            visible: service.controlError !== ""
            width: parent.width
            text: service.controlError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          Text {
            visible: service.lastAttemptFailed && !service.connected && !service.connecting && !service.blocked
            width: parent.width
            text: "Connection attempt failed or timed out (9 s)."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }
        }

        // ------------------------------------------------- SCROLLABLE CONTENT
        Flickable {
          id: panelFlick
          anchors.top: headerCol.bottom
          anchors.topMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: scrollCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height && !root.dragActive

          Column {
            id: scrollCol
            width: panelFlick.width
            spacing: Style.space(12)

        // -------------------------------------------------------- KILL SWITCH
        Column {
          visible: service.blocked
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Kill Switch"
            foreground: root.urgent
            fontFamily: root.fontFamily
          }

          BorderSurface {
            id: killSwitchCard
            width: parent.width
            height: killSwitchColumn.implicitHeight + killSwitchCard.topPadding + killSwitchCard.bottomPadding
            padding: Style.space(10)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, root.foreground, Color.urgent)

            Column {
              id: killSwitchColumn
              x: killSwitchCard.contentLeftInset
              y: killSwitchCard.contentTopInset
              width: killSwitchCard.width - killSwitchCard.contentLeftInset - killSwitchCard.contentRightInset
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: service.blockedEnforced
                  ? "The connection to the VPN server was lost. OpenVPN was stopped and all network traffic is now blocked."
                  : "The connection to the VPN server was lost and OpenVPN was stopped, but the firewall block could not be applied. Network traffic may still be possible."
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Text {
                visible: service.blockedReason !== ""
                width: parent.width
                text: service.blockedSince !== ""
                  ? (service.blockedReason + " • " + service.blockedSince)
                  : service.blockedReason
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Button {
                text: "Restore Network"
                bordered: true
                foreground: root.urgent
                onClicked: service.disconnectVpn()
              }
            }
          }
        }

        // -------------------------------------------------- LIVE TUNNEL INFO
        Column {
          visible: service.connected
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Tunnel Status"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            id: tunnelCard
            width: parent.width
            height: tunnelColumn.implicitHeight + tunnelCard.topPadding + tunnelCard.bottomPadding
            padding: Style.space(10)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, root.foreground, Color.accent)

            Column {
              id: tunnelColumn
              x: tunnelCard.contentLeftInset
              y: tunnelCard.contentTopInset
              width: tunnelCard.width - tunnelCard.contentLeftInset - tunnelCard.contentRightInset
              spacing: Style.space(4)

              RowLayout {
                width: parent.width
                Text {
                  text: "Interface:"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.preferredWidth: Style.space(90)
                }
                Text {
                  text: service.iface !== "" ? service.iface : "unknown"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  Layout.fillWidth: true
                }
              }

              RowLayout {
                width: parent.width
                Text {
                  text: "IP Address:"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.preferredWidth: Style.space(90)
                }
                Text {
                  text: service.ip !== "" ? service.ip : "assigning…"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  Layout.fillWidth: true
                }
              }

              RowLayout {
                visible: service.bytesText !== ""
                width: parent.width
                Text {
                  text: "Traffic:"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.preferredWidth: Style.space(90)
                }
                Text {
                  text: service.bytesText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: service.blocked || service.connected
          width: parent.width
          foreground: root.foreground
        }

        // ---------------------------------------------------------- PROFILES
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            id: headerActionsRow
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: addProfileBtn
              text: "Add Profile"
              iconText: "󰈔"
              bordered: true
              Layout.preferredWidth: (parent.width - parent.spacing) / 2
              Layout.fillWidth: true
              foreground: root.foreground
              onClicked: {
                root.cancelDelete()
                service.addProfile()
              }
            }

            Button {
              id: openFolderBtn
              text: "Open Folder"
              iconText: ""
              bordered: true
              Layout.preferredWidth: (parent.width - parent.spacing) / 2
              Layout.fillWidth: true
              foreground: root.foreground
              onClicked: {
                root.cancelDelete()
                service.openFolder()
              }
            }
          }

          Text {
            visible: service.configs.length === 0
            text: "No .ovpn files found in " + service.configDir
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          RowLayout {
            id: selectionToolbarRow
            visible: root.displayConfigs.length > 0
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: selectAllBtn
              text: root.isAllSelected ? "Deselect All" : "Select All"
              bordered: true
              Layout.preferredWidth: (parent.width - parent.spacing) / 2
              Layout.fillWidth: true
              Layout.preferredHeight: addProfileBtn.implicitHeight
              foreground: root.foreground
              onClicked: {
                root.cancelDelete()
                root.toggleSelectAll()
              }
            }

            Button {
              id: batchDeleteBtn
              text: root.isAllSelected ? "Delete all" : (root.selectedConfigs.length > 0 ? ("Delete (" + root.selectedConfigs.length + ")") : "Delete")
              iconText: "󰆴"
              bordered: true
              Layout.preferredWidth: (parent.width - parent.spacing) / 2
              Layout.fillWidth: true
              Layout.preferredHeight: addProfileBtn.implicitHeight
              enabled: root.selectedConfigs.length > 0
              opacity: enabled ? 1.0 : 0.4
              foreground: (enabled && root.pendingBatchDelete) ? root.deleteArmedColor : root.foreground
              accent: root.deleteArmedColor
              tooltipText: root.pendingBatchDelete ? "Click again to confirm deletion" : "Delete selected profiles"
              onClicked: {
                if (root.selectedConfigs.length === 0) return
                root.pendingDeleteNode = ""
                if (root.pendingBatchDelete) {
                  root.deleteSelectedNodes()
                } else {
                  root.pendingBatchDelete = true
                }
              }
            }
          }

          Column {
            id: configsColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              id: configsRepeater
              model: root.displayConfigs
              delegate: Item {
                id: rowContainer
                required property string modelData
                required property int index
                width: configsColumn.width
                height: rowLayout.implicitHeight

                readonly property bool isDragging: root.dragActive && root.dragSourceIndex === index
                z: isDragging ? 100 : 1
                scale: isDragging ? 1.02 : 1.0

                Behavior on scale { NumberAnimation { duration: 100 } }

                transform: Translate {
                  y: {
                    if (!root.dragActive) return 0
                    if (rowContainer.isDragging) {
                      return root.dragCurrentY - root.dragStartY
                    }
                    var src = root.dragSourceIndex
                    var tgt = root.dragTargetIndex
                    if (src === tgt) return 0

                    var draggedItem = configsRepeater.itemAt(src)
                    var moveDistance = (draggedItem ? draggedItem.height : rowContainer.height) + configsColumn.spacing

                    if (src < tgt) {
                      if (rowContainer.index > src && rowContainer.index <= tgt) return -moveDistance
                    } else if (src > tgt) {
                      if (rowContainer.index >= tgt && rowContainer.index < src) return moveDistance
                    }
                    return 0
                  }

                  Behavior on y {
                    enabled: !rowContainer.isDragging && root.dragActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                  }
                }

                RowLayout {
                  id: rowLayout
                  anchors.left: parent.left
                  anchors.right: parent.right
                  spacing: Style.space(6)

                  // Multi-select Checkbox: concentric square box matching deleteBtn
                  Button {
                    id: checkBtn
                    bordered: true
                    tooltipText: root.isSelected(modelData) ? "Deselect" : "Select"
                    foreground: root.foreground
                    Layout.preferredHeight: profileBtn.implicitHeight
                    Layout.preferredWidth: profileBtn.implicitHeight
                    Layout.alignment: Qt.AlignVCenter
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: root.toggleSelect(modelData)

                    // Inner concentric box
                    BorderSurface {
                      id: innerBox
                      anchors.centerIn: parent
                      width: Style.space(18)
                      height: Style.space(18)
                      radius: Math.max(2, Style.cornerRadius / 2)
                      color: root.isSelected(modelData)
                        ? Style.selectedFillFor(root.foreground, Color.accent)
                        : (checkBtn.hot ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                      borderSpec: root.isSelected(modelData)
                        ? Border.controlSpec("selected", root.foreground, Color.accent)
                        : (checkBtn.hot
                          ? Border.controlSpec("hover-cursor", root.foreground, Color.accent)
                          : Border.controlSpec("normal", root.foreground, Color.accent))

                      Text {
                        anchors.centerIn: parent
                        visible: root.isSelected(modelData)
                        text: "✓"
                        color: Style.selectedStateColor(root.foreground, Color.accent)
                        font.family: root.fontFamily
                        font.pixelSize: Style.space(12)
                        font.bold: true
                      }
                    }
                  }

                  // Node profile button (click to select, long-press to drag and reorder)
                  Button {
                    id: profileBtn
                    Layout.fillWidth: true
                    leftAlign: true
                    bordered: true
                    active: rowContainer.isDragging
                    selected: service.config === modelData
                    text: root.profileName(modelData) + (service.hasSavedAuthFor(modelData) ? "  [auth]" : "")
                    iconText: service.config === modelData ? "✓" : (service.hasSavedAuthFor(modelData) ? "󰌆" : "")
                    foreground: root.foreground
                    hasCursor: profileMouse.containsMouse || profileMouse.pressed

                    MouseArea {
                      id: profileMouse
                      anchors.fill: parent
                      hoverEnabled: !root.dragActive
                      preventStealing: true
                      pressAndHoldInterval: 350
                      cursorShape: (root.dragActive && root.dragSourceIndex === rowContainer.index)
                        ? Qt.ClosedHandCursor
                        : Qt.PointingHandCursor

                      property bool isLongPress: false

                      onPressed: function(mouse) {
                        isLongPress = false
                        root.suppressClick = false
                      }

                      onPressAndHold: function(mouse) {
                        if (!profileMouse.pressed) return
                        isLongPress = true
                        root.suppressClick = true
                        var mappedY = profileMouse.mapToItem(configsColumn, 0, mouse.y).y
                        root.startDrag(rowContainer.index, mappedY)
                      }

                      onPositionChanged: function(mouse) {
                        if (root.dragActive && root.dragSourceIndex === rowContainer.index) {
                          var mappedY = profileMouse.mapToItem(configsColumn, 0, mouse.y).y
                          root.updateDrag(mappedY)
                        }
                      }

                      onReleased: function(mouse) {
                        if (root.dragActive && root.dragSourceIndex === rowContainer.index) {
                          isLongPress = true
                          root.suppressClick = true
                          root.finishDrag()
                          mouse.accepted = true
                        }
                      }

                      onCanceled: {
                        if (root.dragActive && root.dragSourceIndex === rowContainer.index) {
                          isLongPress = true
                          root.suppressClick = true
                          root.cancelDrag()
                        }
                      }

                      onClicked: function(mouse) {
                        if (isLongPress || root.suppressClick) {
                          isLongPress = false
                          root.suppressClick = false
                          return
                        }
                        if (typeof passField !== "undefined" && passField) passField.text = ""
                        root.cancelDelete()
                        service.setConfig(modelData)
                      }
                    }
                  }

                  // Delete button: square box decoration, height matching profileBtn
                  Button {
                    id: deleteBtn
                    bordered: true
                    iconText: "󰆴"
                    tooltipText: (root.pendingDeleteNode === modelData) ? "Click again to confirm delete" : "Delete profile"
                    foreground: (root.pendingDeleteNode === modelData) ? root.deleteArmedColor : root.foreground
                    accent: root.deleteArmedColor
                    Layout.preferredHeight: profileBtn.implicitHeight
                    Layout.preferredWidth: profileBtn.implicitHeight
                    Layout.alignment: Qt.AlignVCenter
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: {
                      root.pendingBatchDelete = false
                      if (root.pendingDeleteNode === modelData) {
                        root.deleteNode(modelData)
                      } else {
                        root.pendingDeleteNode = modelData
                      }
                    }
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // ------------------------------------------------------- CREDENTIALS
        Column {
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            PanelSectionHeader {
              text: service.configName !== "" ? ("Credentials (" + service.configName + ")") : "Credentials"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
            }
            Text {
              text: service.hasAuth ? "✓ Saved" : "No Auth"
              color: service.hasAuth ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: service.hasAuth
            }
          }

          TextField {
            id: userField
            width: parent.width
            placeholderText: "VPN Username"
            text: service.username
            foreground: root.foreground
          }

          TextField {
            id: passField
            width: parent.width
            placeholderText: service.hasAuth ? "Password (Saved • Enter to update)" : "VPN Password"
            password: true
            foreground: root.foreground
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Save for Profile"
              bordered: true
              Layout.fillWidth: true
              foreground: root.foreground
              onClicked: {
                if (userField.text.trim().length > 0) {
                  service.setCredentials(userField.text.trim(), passField.text)
                  passField.text = ""
                }
              }
            }

            Button {
              visible: service.hasAuth
              text: "Clear Auth"
              bordered: true
              foreground: root.urgent
              onClicked: {
                passField.text = ""
                service.clearCredentials()
              }
            }
          }
        }

        // ------------------------------------------------------------- LOGS
        Column {
          visible: service.logTail !== ""
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: "Recent Log"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            id: logCard
            width: parent.width
            height: logText.implicitHeight + logCard.topPadding + logCard.bottomPadding
            padding: Style.space(8)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, root.foreground, Color.accent)

            Text {
              id: logText
              x: logCard.contentLeftInset
              y: logCard.contentTopInset
              width: logCard.width - logCard.contentLeftInset - logCard.contentRightInset
              text: service.logTail
              color: root.dim
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
            }
          }
        }
      }
    }
  }
}
}
}
