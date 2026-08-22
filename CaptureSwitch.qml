import QtQuick
import qs.Ui
import qs.Commons

// System proxy / TUN / Off. Mutually exclusive: Clash Verge can toggle both,
// but running them together double-captures traffic. Writes go through the
// service so the OS proxy and PATCH /configs stay ordered.
Row {
  id: root

  property var svc: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.space(8)

  readonly property bool sysOn: svc ? svc.sysproxyEnabled : false
  readonly property bool tunOn: svc ? svc.tunEnabled : false

  Button {
    text: root.svc ? root.svc.t("captureSysproxy") : "System proxy"
    tooltipText: root.svc ? root.svc.t("captureSysproxyTip") : "Set the desktop / session proxy to the core mixed port"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.sysOn
    enabled: root.svc !== null && root.svc.connected
    onClicked: {
      if (root.sysOn && !root.tunOn) root.svc.setCaptureMode("off")
      else root.svc.setCaptureMode("sysproxy")
    }
  }

  Button {
    text: root.svc ? root.svc.t("captureTun") : "TUN"
    tooltipText: root.svc ? root.svc.t("captureTunTip") : "Capture all traffic through a virtual NIC"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: root.tunOn
    enabled: root.svc !== null && root.svc.connected
    onClicked: {
      if (root.tunOn && !root.sysOn) root.svc.setCaptureMode("off")
      else root.svc.setCaptureMode("tun")
    }
  }

  Button {
    text: root.svc ? root.svc.t("captureOff") : "Off"
    tooltipText: root.svc ? root.svc.t("captureOffTip") : "Do not capture traffic at the OS"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    active: !root.sysOn && !root.tunOn
    enabled: root.svc !== null && root.svc.connected
    onClicked: root.svc.setCaptureMode("off")
  }
}
