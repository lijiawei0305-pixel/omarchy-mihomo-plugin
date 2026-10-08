import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Item {
  id: root

  property var svc: null
  property color fg: Color.popups.text
  property string fontFamily: Style.font.family
  property string filter: ""
  property string editingRuleId: ""
  property string removingRuleId: ""
  property bool removingRule: false

  readonly property var effectiveRows: {
    if (!root.svc || root.filter.trim() === "") return []
    var needle = root.filter.trim().toLowerCase()
    var all = root.svc.rules || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var rule = all[i] || {}
      var payload = String(rule.payload || rule.rulePayload || "")
      var type = String(rule.type || "")
      var target = String(rule.proxy || rule.policy || "")
      if (payload.toLowerCase().indexOf(needle) >= 0
          || type.toLowerCase().indexOf(needle) >= 0
          || target.toLowerCase().indexOf(needle) >= 0) {
        out.push({index: i, payload: payload, type: type, target: target})
      }
    }
    return out
  }

  readonly property var allCustomRuleRows: {
    if (!root.svc) return []
    var all = root.svc.customRules || []
    var out = []
    for (var i = all.length - 1; i >= 0; i--) out.push(all[i])
    return out
  }

  readonly property var customRulePreviewRows: {
    var all = root.allCustomRuleRows
    if (all.length === 0) return []
    var out = [all[0]]
    if (all.length === 2) out.push(all[1])
    else if (all.length > 2) out.push({summary: true, remaining: all.length - 1})
    return out
  }

  function ruleDomain(rule) {
    var match = rule && rule.match ? rule.match : {}
    return String(match.value || "")
  }

  function ruleMatch(rule) {
    var match = rule && rule.match ? rule.match : {}
    return String(match.type || "domain-suffix")
  }

  function matchLabel(rule) {
    return root.svc
      ? root.svc.t(root.ruleMatch(rule) === "domain" ? "matchDomain" : "matchDomainSuffix")
      : (root.ruleMatch(rule) === "domain" ? "Exact domain" : "Domain and subdomains")
  }

  function policyLabel(policy) {
    if (!root.svc) return String(policy || "")
    if (policy === "direct") return root.svc.t("policyDirect")
    if (policy === "reject") return root.svc.t("policyReject")
    return root.svc.t("policyProxy")
  }

  function policyTarget(rule) {
    if (!rule) return ""
    if (rule.policy === "direct") return "DIRECT"
    if (rule.policy === "reject") return "REJECT"
    return root.svc ? root.svc.t("policyProxy") : "Proxy"
  }

  function targetColor(target) {
    if (target === "DIRECT") return Util.alpha(root.fg, 0.6)
    if (target === "REJECT" || target === "REJECT-DROP") return Color.urgent
    return Color.accent
  }

  function openAdd() {
    root.openAddForDomain("", "domain-suffix")
  }

  function openAddForDomain(domain, matchType) {
    addRuleDialog.ruleId = ""
    addRuleDialog.initialDomain = String(domain || "")
    addRuleDialog.initialMatch = String(matchType || "domain-suffix")
    addRuleDialog.initialPolicy = "proxy"
    addRuleDialog.open()
  }

  function effectiveRuleDomain(rule) {
    var type = String(rule && rule.type || "").toUpperCase()
    if (type !== "DOMAIN" && type !== "DOMAIN-SUFFIX") return ""
    return String(rule && rule.payload || "").trim()
  }

  function effectiveRuleMatch(rule) {
    return String(rule && rule.type || "").toUpperCase() === "DOMAIN"
      ? "domain" : "domain-suffix"
  }

  function openEffectiveRuleMenu(rule, area, mouse) {
    var domain = root.effectiveRuleDomain(rule)
    var point = area.mapToItem(Overlay.overlay, mouse.x, mouse.y)
    effectiveRuleContextMenu.title = String(rule && rule.payload || "")
      + " · " + String(rule && rule.type || "")
    effectiveRuleContextMenu.domain = domain
    effectiveRuleContextMenu.actionEnabled = root.svc && root.svc.managerInstalled
      && !root.svc.profileMutating
    effectiveRuleContextMenu.matchType = root.effectiveRuleMatch(rule)
    effectiveRuleContextMenu.openAt(point.x, point.y)
  }

  function openEdit(rule) {
    editRuleDialog.ruleId = String(rule.id || "")
    editRuleDialog.initialDomain = root.ruleDomain(rule)
    editRuleDialog.initialMatch = root.ruleMatch(rule)
    editRuleDialog.initialPolicy = String(rule.policy || "proxy")
    editRuleDialog.open()
  }

  function removeRule(rule) {
    root.removingRuleId = String(rule.id || "")
    removeConfirm.message = root.svc
      ? root.svc.t("deleteRuleConfirm", root.ruleDomain(rule))
      : "Delete this rule?"
    root.removingRule = true
  }

  function scrollBy(delta) {
    var flick = scrollView.contentItem
    if (!flick) return
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height),
                                          flick.contentY + delta))
  }

  function focusFilter() {
    filterField.forceActiveFocus()
    filterField.selectAll()
  }

  function openAllRules() {
    allRulesPopup.open()
  }

  AddRuleDialog {
    id: addRuleDialog
    svc: root.svc
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  RuleContextMenu {
    id: effectiveRuleContextMenu
    property string matchType: "domain-suffix"
    svc: root.svc
    foreground: root.fg
    fontFamily: root.fontFamily
    onAddToRulesRequested: {
      if (effectiveRuleContextMenu.domain !== "")
        root.openAddForDomain(effectiveRuleContextMenu.domain,
                              effectiveRuleContextMenu.matchType)
    }
  }

  AddRuleDialog {
    id: editRuleDialog
    svc: root.svc
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  ConfirmDialog {
    id: removeConfirm
    anchors.fill: parent
    z: 300
    opened: root.removingRule
    cancelText: root.svc ? root.svc.t("cancel") : "Cancel"
    confirmText: root.svc ? root.svc.t("deleteRule") : "Delete rule"
    foreground: root.fg
    onCanceled: {
      root.removingRule = false
      root.removingRuleId = ""
    }
    onConfirmed: {
      if (root.svc && root.removingRuleId !== "") root.svc.deleteCustomRule(root.removingRuleId)
      root.removingRule = false
      root.removingRuleId = ""
    }
  }

  Popup {
    id: allRulesPopup
    modal: true
    focus: true
    z: 200
    padding: Style.space(18)
    width: Math.min(Style.space(560), Math.max(Style.space(320), root.width - Style.space(24)))
    height: Math.min(Style.space(560), Math.max(Style.space(260), root.height - Style.space(24)))
    anchors.centerIn: Overlay.overlay
    background: Rectangle {
      color: Color.popups.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: Util.alpha(root.fg, 0.2)
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: titleText.implicitHeight

        Text {
          id: titleText
          Layout.fillWidth: true
          text: root.svc ? root.svc.t("allCustomRules") : "All custom rules"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          renderType: Text.NativeRendering
        }

        Button {
          text: root.svc ? root.svc.t("close") : "Close"
          onClicked: allRulesPopup.close()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Util.alpha(root.fg, 0.12)
      }

      ListView {
        id: allRulesList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        spacing: Style.space(6)
        model: root.allCustomRuleRows

        delegate: Rectangle {
          required property var modelData
          width: allRulesList.width
          height: Style.space(56)
          radius: Style.cornerRadius
          color: allRuleMouse.containsMouse ? Util.alpha(root.fg, 0.07) : Util.alpha(root.fg, 0.03)

          MouseArea {
            id: allRuleMouse
            anchors.fill: parent
            hoverEnabled: true
          }

          Column {
            anchors.left: parent.left
            anchors.right: allRuleActions.left
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.ruleDomain(modelData)
              textFormat: Text.PlainText
              color: modelData.enabled === false ? Util.alpha(root.fg, 0.45) : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              text: root.policyLabel(String(modelData.policy || "proxy"))
                + " · " + root.matchLabel(modelData)
              textFormat: Text.PlainText
              color: modelData.enabled === false ? Util.alpha(root.fg, 0.35) : Util.alpha(root.fg, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }

          Row {
            id: allRuleActions
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              iconText: "󰏫"
              tooltipText: root.svc ? root.svc.t("editRule") : "Edit rule"
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              enabled: root.svc && !root.svc.profileMutating
              onClicked: root.openEdit(modelData)
            }

            PanelActionButton {
              iconText: modelData.enabled === false ? "󰐊" : "󰏤"
              tooltipText: root.svc
                ? root.svc.t(modelData.enabled === false ? "enableRule" : "disableRule")
                : (modelData.enabled === false ? "Enable" : "Disable")
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              enabled: root.svc && !root.svc.profileMutating
              onClicked: modelData.enabled === false
                ? root.svc.enableCustomRule(String(modelData.id))
                : root.svc.disableCustomRule(String(modelData.id))
            }

            PanelActionButton {
              iconText: "󰆴"
              tooltipText: root.svc ? root.svc.t("deleteRule") : "Delete rule"
              foreground: root.fg
              hoverColor: Color.urgent
              fontFamily: root.fontFamily
              enabled: root.svc && !root.svc.profileMutating
              onClicked: root.removeRule(modelData)
            }
          }
        }

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.allCustomRuleRows.length === 0
        text: root.svc ? root.svc.t("noCustomRules") : "No custom rules yet."
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }
  }

  PageHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: root.svc ? root.svc.t("rulesTitle") : "Rules"
    subtitle: root.svc ? root.svc.t("globalRulesSubtitle") : "Rules used by every profile"
    foreground: root.fg
    fontFamily: root.fontFamily

    PanelActionButton {
      iconText: "󰐕"
      tooltipText: root.svc ? root.svc.t("addRule") : "Add rule"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc && root.svc.managerInstalled && !root.svc.profileMutating
      onClicked: root.openAdd()
    }

    PanelActionButton {
      iconText: "󰑐"
      tooltipText: root.svc ? root.svc.t("refreshRules") : "Reload rules"
      foreground: root.fg
      hoverColor: Color.accent
      fontFamily: root.fontFamily
      enabled: root.svc && root.svc.connected && !root.svc.rulesLoading
      onClicked: {
        root.svc.refreshRules()
        root.svc.refreshCustomRules()
      }
    }
  }

  Rectangle {
    id: headerRule
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    height: 1
    color: Util.alpha(root.fg, 0.12)
  }

  ScrollView {
    id: scrollView
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: headerRule.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(14)
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    Column {
      id: content
      width: scrollView.availableWidth
      spacing: Style.space(10)

      Card {
        id: myRulesCard
        width: content.width
        foreground: root.fg

        Row {
          width: parent.width
          height: Math.max(myRulesHeader.implicitHeight,
                           Math.max(proxyBindingButton.implicitHeight, viewAllButton.implicitHeight))

          PanelSectionHeader {
            id: myRulesHeader
            width: parent.width - proxyBindingButton.width - viewAllButton.width - Style.space(20)
            text: root.svc ? root.svc.t("myRules") : "My Rules"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Button {
            id: proxyBindingButton
            anchors.verticalCenter: parent.verticalCenter
            text: root.svc ? root.svc.t("editProxyBinding") : "Edit proxy group"
            enabled: root.svc && root.svc.managerInstalled && root.svc.activeProfile !== ""
              && !root.svc.bindingCandidatesLoading && !root.svc.profileMutating
            onClicked: root.svc.openProxyBindingEditor()
          }

          Button {
            id: viewAllButton
            anchors.verticalCenter: parent.verticalCenter
            text: root.svc ? root.svc.t("viewAllRules") : "View all"
            enabled: root.allCustomRuleRows.length > 0
            onClicked: root.openAllRules()
          }
        }

        Text {
          width: parent.width
          visible: root.filter.trim() === ""
          text: {
            if (!root.svc) return "0 rules"
            var count = (root.svc.rules || []).length
            return root.svc.t(count === 1 ? "rulesCountOne" : "rulesCountMany", count)
          }
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        Repeater {
          model: root.customRulePreviewRows

          delegate: Rectangle {
            required property var modelData
            width: myRulesCard.width - myRulesCard.pad * 2
            property bool summaryRow: modelData && modelData.summary === true
            height: summaryRow ? Style.space(36) : Style.space(54)
            radius: Style.cornerRadius
            color: summaryRow
              ? Util.alpha(root.fg, 0.02)
              : (ruleMouse.containsMouse ? Util.alpha(root.fg, 0.07) : Util.alpha(root.fg, 0.03))

            MouseArea {
              id: ruleMouse
              anchors.fill: parent
              hoverEnabled: true
              visible: !summaryRow
            }

            Column {
              anchors.left: parent.left
              anchors.right: ruleActions.left
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              visible: !summaryRow

              Text {
                width: parent.width
                text: root.ruleDomain(modelData)
                textFormat: Text.PlainText
                color: modelData.enabled === false ? Util.alpha(root.fg, 0.45) : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                text: root.policyLabel(String(modelData.policy || "proxy"))
                  + " · " + root.matchLabel(modelData)
                textFormat: Text.PlainText
                color: modelData.enabled === false ? Util.alpha(root.fg, 0.35) : Util.alpha(root.fg, 0.55)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              visible: summaryRow
              text: root.svc ? root.svc.t("remainingRules", modelData.remaining) : (modelData.remaining + " more rules")
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            Row {
              id: ruleActions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              visible: !summaryRow

              PanelActionButton {
                iconText: "󰏫"
                tooltipText: root.svc ? root.svc.t("editRule") : "Edit rule"
                foreground: root.fg
                hoverColor: Color.accent
                fontFamily: root.fontFamily
                enabled: root.svc && !root.svc.profileMutating
                onClicked: root.openEdit(modelData)
              }

              PanelActionButton {
                iconText: modelData.enabled === false ? "󰐊" : "󰏤"
                tooltipText: root.svc
                  ? root.svc.t(modelData.enabled === false ? "enableRule" : "disableRule")
                  : (modelData.enabled === false ? "Enable" : "Disable")
                foreground: root.fg
                hoverColor: Color.accent
                fontFamily: root.fontFamily
                enabled: root.svc && !root.svc.profileMutating
                onClicked: modelData.enabled === false
                  ? root.svc.enableCustomRule(String(modelData.id))
                  : root.svc.disableCustomRule(String(modelData.id))
              }

              PanelActionButton {
                iconText: "󰆴"
                tooltipText: root.svc ? root.svc.t("deleteRule") : "Delete rule"
                foreground: root.fg
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                enabled: root.svc && !root.svc.profileMutating
                onClicked: root.removeRule(modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.svc && root.svc.customRules.length === 0
          text: root.svc ? root.svc.t("noCustomRules") : "No custom rules yet."
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Card {
        id: effectiveRulesCard
        width: content.width
        foreground: root.fg

        PanelSectionHeader {
          width: parent.width
          text: root.svc ? root.svc.t("effectiveRules") : "Effective Rules"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        TextField {
          id: filterField
          width: parent.width
          placeholderText: root.svc ? root.svc.t("searchEffectiveRulesHint") : "Search the active configuration's rules"
          foreground: root.fg
          accent: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          onTextChanged: root.filter = text
          Keys.onEscapePressed: function(event) {
            if (text !== "") { text = ""; event.accepted = true }
            else focus = false
          }
        }

        Repeater {
          model: root.effectiveRows

          delegate: Rectangle {
            required property var modelData
            width: effectiveRulesCard.width - effectiveRulesCard.pad * 2
            height: Style.space(38)
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, 0.03)

            MouseArea {
              id: effectiveRuleMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onPressed: function(mouse) {
                if (mouse.button !== Qt.RightButton) return
                root.openEffectiveRuleMenu(modelData, effectiveRuleMouse, mouse)
                mouse.accepted = true
              }
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: target.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: String(modelData.index + 1) + "  " + modelData.payload + " · " + modelData.type
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              renderType: Text.NativeRendering
            }

            Text {
              id: target
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(110)
              text: modelData.target
              textFormat: Text.PlainText
              color: root.targetColor(modelData.target)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }
        }

        Text {
          width: parent.width
          visible: root.filter.trim() !== "" && root.effectiveRows.length === 0
          text: root.svc
            ? root.svc.t(root.filter.trim() === "" ? "noRules" : "noMatchRules")
            : (root.filter.trim() === "" ? "This config has no rules." : "No rules match.")
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Item { width: 1; height: Style.space(4) }
    }
  }
}
