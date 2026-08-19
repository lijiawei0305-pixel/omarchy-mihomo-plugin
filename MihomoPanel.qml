import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget + control panel for the mihomo core.
//
// Layout mirrors the desktop clients people already know: a fixed nav rail on
// the left, one page on the right. The panel keeps a constant size across
// pages so switching tabs never resizes the window under the cursor.
Panel {
  id: root

  moduleName: "io.github.leeyiwei0305.mihomo"
  ipcTarget: "io.github.leeyiwei0305.mihomo"
  manageIpc: false

  readonly property var svc: bar?.shell?.serviceFor(root.moduleName)

  readonly property color fg: bar ? bar.foreground : Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string page: "home"

  readonly property bool connected: svc ? svc.connected : false
  readonly property string modeLabel: svc ? svc.modeLabel : "--"

  readonly property var currentPage: page === "proxies" ? proxiesPage
    : page === "config" ? configPage
    : page === "connections" ? connectionsPage
    : page === "rules" ? rulesPage
    : homePage

  function goto(target) {
    if (page !== target) page = target
  }

  function scrollCurrent(amount) {
    if (currentPage && typeof currentPage.scrollBy === "function") currentPage.scrollBy(amount)
  }

  function cyclePage(direction) {
    var order = ["home", "proxies", "config", "connections", "rules"]
    var index = order.indexOf(page)
    if (index < 0) index = 0
    page = order[(index + direction + order.length) % order.length]
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The service polls hard only while the panel is visible, and only for the
  // page on screen.
  Binding {
    target: root.svc
    property: "active"
    value: root.opened
    when: root.svc !== null && root.svc !== undefined
  }

  Binding {
    target: root.svc
    property: "page"
    value: root.page
    when: root.svc !== null && root.svc !== undefined
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function page(name: string): void { root.goto(name) }

    function state(): string {
      if (!root.svc) return "{}"
      return JSON.stringify({
        connected: root.svc.connected,
        mode: root.svc.mode,
        version: root.svc.version,
        endpoint: root.svc.endpointTarget,
        page: root.page
      })
    }
  }

  // --- bar button ----------------------------------------------------------

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 5
    tooltipText: root.svc && root.svc.connected
      ? ("mihomo " + root.svc.version + " · " + root.svc.modeLabel
         + "\n↑ " + root.svc.fmtSpeed(root.svc.upSpeed) + "  ↓ " + root.svc.fmtSpeed(root.svc.downSpeed))
      : (root.svc ? root.svc.t("barDisconnected") : "mihomo · disconnected")
    fixedWidth: vertical ? -1 : barContent.implicitWidth + Style.spaceReal(10)
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    onPressed: function(mouseButton) { root.toggle() }

    Row {
      id: barContent
      visible: !button.vertical
      anchors.centerIn: parent
      spacing: Style.spaceReal(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰖂"
        color: root.connected ? button.foreground : Color.urgent
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.connected ? root.modeLabel : "--"
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    Text {
      visible: button.vertical
      anchors.centerIn: parent
      text: "󰖂"
      color: root.connected ? button.foreground : Color.urgent
      font.family: button.fontFamily
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }
  }

  // --- panel ---------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(660))
    // Passing the same value as height and cap pins the panel: pages differ
    // wildly in length, and a popup that resizes per tab is unusable.
    contentHeight: panel.fittedContentHeight(Style.space(600), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // A focused filter field owns every key, including j/k/1-5.
      blocked: root.currentPage !== null && root.currentPage.editing === true

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.scrollCurrent(dy * Style.space(64))
        else if (dx !== 0) root.cyclePage(dx)
      }
      onTextKey: function(text) {
        if (text === "1") root.goto("home")
        else if (text === "2") root.goto("proxies")
        else if (text === "3") root.goto("config")
        else if (text === "4") root.goto("connections")
        else if (text === "5") root.goto("rules")
        else if (text === "r" && root.svc) root.svc.refreshPage()
        else if (text === "/" && root.currentPage
                 && typeof root.currentPage.focusFilter === "function")
          root.currentPage.focusFilter()
      }

      // --- nav rail --------------------------------------------------------

      Item {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(116)

        Column {
          id: navColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(4)

          Item {
            width: parent.width
            implicitHeight: Math.max(brandIcon.implicitHeight, brandLabels.implicitHeight)
              + Style.space(10)

            Text {
              id: brandIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰖂"
              color: root.connected ? Color.accent : Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              renderType: Text.NativeRendering
            }

            Column {
              id: brandLabels
              anchors.left: brandIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: "MIHOMO"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                text: root.svc && root.svc.version !== "" ? root.svc.version
                  : (root.svc ? root.svc.t("offline") : "Offline")
                color: Util.alpha(root.fg, 0.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }
            }
          }

          NavButton { width: parent.width; pageId: "home";        glyph: "󰋜"; title: root.svc ? root.svc.t("navHome") : "Home" }
          NavButton { width: parent.width; pageId: "proxies";     glyph: "󰖟"; title: root.svc ? root.svc.t("navProxies") : "Proxies" }
          NavButton { width: parent.width; pageId: "config";      glyph: "󰈙"; title: root.svc ? root.svc.t("navConfig") : "Config" }
          NavButton { width: parent.width; pageId: "connections"; glyph: "󰇧"; title: root.svc ? root.svc.t("navConnections") : "Connections" }
          NavButton { width: parent.width; pageId: "rules";       glyph: "󰘬"; title: root.svc ? root.svc.t("navRules") : "Rules" }
        }

        Column {
          id: sideFooter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(5)

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.fg, 0.12)
          }

          Item { width: 1; height: Style.space(3) }

          LanguageSwitch {
            width: parent.width
            compact: true
            svc: root.svc
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          MiniStat { width: parent.width; glyph: "󰁝"; value: root.svc ? root.svc.fmtSpeed(root.svc.upSpeed) : "--" }
          MiniStat { width: parent.width; glyph: "󰁅"; value: root.svc ? root.svc.fmtSpeed(root.svc.downSpeed) : "--" }
          MiniStat { width: parent.width; glyph: "󰍛"; value: root.svc ? root.svc.fmtBytes(root.svc.memInuse) : "--" }

          Item { width: 1; height: Style.space(4) }
        }
      }

      Rectangle {
        id: railRule
        anchors.left: sidebar.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Util.alpha(root.fg, 0.12)
      }

      // --- page host -------------------------------------------------------

      Item {
        id: pageHost
        anchors.left: railRule.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        HomePage {
          id: homePage
          anchors.fill: parent
          visible: root.page === "home"
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }

        ProxiesPage {
          id: proxiesPage
          anchors.fill: parent
          visible: root.page === "proxies"
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }

        ConfigPage {
          id: configPage
          anchors.fill: parent
          visible: root.page === "config"
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }

        ConnectionsPage {
          id: connectionsPage
          anchors.fill: parent
          visible: root.page === "connections"
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }

        RulesPage {
          id: rulesPage
          anchors.fill: parent
          visible: root.page === "rules"
          svc: root.svc
          fg: root.fg
          fontFamily: root.fontFamily
        }

        // Transient confirmation for writes, so a node switch or a reload
        // is visibly acknowledged without a modal.
        Rectangle {
          id: toast
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(10)
          width: Math.min(toastText.implicitWidth + Style.space(24), pageHost.width)
          height: toastText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.5)
          opacity: root.svc && root.svc.notice !== "" ? 1.0 : 0
          visible: opacity > 0

          Behavior on opacity { NumberAnimation { duration: 140 } }

          Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, pageHost.width - Style.space(24))
            text: root.svc ? root.svc.notice : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }

  Timer {
    id: noticeTimer
    interval: 2600
    onTriggered: if (root.svc) root.svc.notice = ""
  }

  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onNoticeChanged() {
      if (root.svc && root.svc.notice !== "") noticeTimer.restart()
    }
  }

  onOpenedChanged: {
    if (opened && svc) svc.refreshPage()
  }

  // --- inline components ---------------------------------------------------

  component NavButton: Rectangle {
    id: nav
    required property string pageId
    required property string glyph
    required property string title

    readonly property bool selected: root.page === pageId

    height: Style.space(34)
    radius: Style.cornerRadius
    color: selected ? Util.alpha(Color.accent, 0.16)
      : navMouse.containsMouse ? Util.alpha(root.fg, 0.07)
      : "transparent"

    Behavior on color { ColorAnimation { duration: 100 } }

    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.goto(nav.pageId)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(2)
      height: parent.height * 0.55
      radius: width
      color: Color.accent
      visible: nav.selected
    }

    Text {
      id: navGlyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: nav.glyph
      color: nav.selected ? Color.accent : Util.alpha(root.fg, 0.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      renderType: Text.NativeRendering
    }

    Text {
      anchors.left: navGlyph.right
      anchors.leftMargin: Style.space(9)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: nav.title
      color: nav.selected ? Color.accent : Util.alpha(root.fg, 0.85)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: nav.selected
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }
  }

  component MiniStat: Item {
    id: stat
    required property string glyph
    required property string value

    implicitHeight: statValue.implicitHeight

    Text {
      id: statGlyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: stat.glyph
      color: Util.alpha(root.fg, 0.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: statValue
      anchors.left: statGlyph.right
      anchors.leftMargin: Style.space(5)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: stat.value
      color: Util.alpha(root.fg, 0.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }
  }
}
