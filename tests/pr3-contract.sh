#!/usr/bin/env bash
# Regression checks for the Omarchy 4.0.3+ service bridge and null-svc bindings.
# Static checks run anywhere. QML checks need qml6, a C++ compiler, and Qt 6 dev files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> source contract"
rg -q 'singleton ServiceStore 1\.0 ServiceStore\.qml' "$ROOT/qmldir" || fail "qmldir does not register ServiceStore"
rg -q 'pragma Singleton' "$ROOT/ServiceStore.qml" || fail "ServiceStore is not a singleton"
rg -q 'ServiceStore\.instance = root' "$ROOT/Service.qml" || fail "Service does not publish itself"
rg -q 'Qt\.resolvedUrl\("\."\)' "$ROOT/Service.qml" || fail "pluginDir does not use Qt.resolvedUrl"
rg -q 'ready: runner !== ""' "$ROOT/Service.qml" || fail "ready is not gated on the runner path"
rg -q 'ServiceStore\.instance' "$ROOT/MihomoPanel.qml" || fail "panel does not read ServiceStore"
rg -q 'enabled: root\.svc \? !root\.svc\.isTesting\(card\.groupName\) : false' "$ROOT/ProxiesPage.qml" \
  || fail "group test button calls isTesting when svc is null"
rg -q 'onClicked: if \(root\.svc\) root\.svc\.testGroup\(card\.groupName\)' "$ROOT/ProxiesPage.qml" \
  || fail "group test click is not null-safe"
rg -q -U 'onClicked: function\(mouse\) \{\n[[:space:]]+if \(!root\.svc\) return\n' "$ROOT/ProxiesPage.qml" \
  || fail "node click is not null-safe"
rg -q 'root\.filter !== "" \? \(root\.svc \? root\.svc\.t\("noMatchRules"\) : ""\)' "$ROOT/RulesPage.qml" \
  || fail "rules empty-state calls t() when svc is null"
# The startup TypeError was the unguarded else branch.
rg -q ': \(root\.svc \? root\.svc\.t\("notConnected"\) : ""\)' "$ROOT/ProxiesPage.qml" \
  || fail "proxies empty-state calls t() when svc is null"
echo "    source contract ok"

if ! command -v qml6 >/dev/null || ! command -v pkg-config >/dev/null || ! command -v c++ >/dev/null; then
  echo "UNVERIFIED: qml6, c++, or pkg-config is missing; skipped runtime QML checks" >&2
  exit 0
fi
pkg-config --exists Qt6Qml Qt6Gui || { echo "UNVERIFIED: Qt6Qml/Qt6Gui dev files missing" >&2; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> null-svc bindings"
cat > "$WORK/warnprobe.cpp" << 'EOF'
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlError>
#include <QtLogging>
#include <QTimer>
int main(int argc, char **argv) {
    qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &msg) {
        fprintf(stderr, "MSG %s\n", qPrintable(msg));
    });
    QGuiApplication app(argc, argv);
    QQmlEngine engine;
    QObject::connect(&engine, &QQmlEngine::warnings, [](const QList<QQmlError> &warnings) {
        for (const QQmlError &w : warnings)
            fprintf(stderr, "WARN %s\n", qPrintable(w.toString()));
    });
    QQmlComponent component(&engine, QUrl::fromLocalFile(QString::fromUtf8(argv[1])));
    if (component.isError()) {
        fprintf(stderr, "LOAD %s\n", qPrintable(component.errorString()));
        return 2;
    }
    QObject *obj = component.create();
    if (!obj) {
        fprintf(stderr, "CREATE %s\n", qPrintable(component.errorString()));
        return 3;
    }
    QTimer::singleShot(0, &app, &QGuiApplication::quit);
    return app.exec();
}
EOF
c++ -fPIC -std=c++17 "$WORK/warnprobe.cpp" -o "$WORK/warnprobe" $(pkg-config --cflags --libs Qt6Qml Qt6Gui)

cat > "$WORK/guarded.qml" << 'EOF'
import QtQuick
Item {
    property var svc: null
    property string filter: "example.com"
    property string groupName: "PROXY"
    property bool groupEnabled: svc ? !svc.isTesting(groupName) : false
    property string rulesText: svc && svc.rulesLoading ? svc.t("loadingRules")
        : svc && !svc.connected ? svc.t("notConnected")
        : filter !== "" ? (svc ? svc.t("noMatchRules") : "")
        : (svc ? svc.t("noRules") : "")
    property string proxiesText: svc && svc.connected ? svc.t("noGroups")
        : (svc ? svc.t("notConnected") : "")
    Component.onCompleted: {
        var a = groupEnabled
        var b = rulesText
        var c = proxiesText
    }
}
EOF
cat > "$WORK/unguarded.qml" << 'EOF'
import QtQuick
Item {
    property var svc: null
    property string groupName: "PROXY"
    property bool groupEnabled: !svc.isTesting(groupName)
    Component.onCompleted: { var a = groupEnabled }
}
EOF

set +e
QT_QPA_PLATFORM=offscreen "$WORK/warnprobe" "$WORK/guarded.qml" >"$WORK/guarded.out" 2>"$WORK/guarded.err"
guarded_status=$?
QT_QPA_PLATFORM=offscreen "$WORK/warnprobe" "$WORK/unguarded.qml" >"$WORK/unguarded.out" 2>"$WORK/unguarded.err"
unguarded_status=$?
set -e
[[ $guarded_status -eq 0 ]] || fail "guarded probe exited $guarded_status"
if rg -q 'TypeError' "$WORK/guarded.err"; then
  cat "$WORK/guarded.err" >&2
  fail "guarded null svc bindings threw TypeError"
fi
rg -q 'TypeError: Cannot call method '"'"'isTesting'"'"' of null' "$WORK/unguarded.err" \
  || fail "probe did not detect the unguarded isTesting TypeError (status $unguarded_status)"
echo "    null-svc bindings ok"

echo "==> ServiceStore and pluginDir"
BASE="$WORK/My Plugins/测试"
mkdir -p "$BASE"
cp "$ROOT/qmldir" "$ROOT/ServiceStore.qml" "$BASE/"
cat > "$BASE/Sibling.qml" << 'EOF'
import QtQuick
QtObject { property string marker: "sibling-ok" }
EOF
cat > "$BASE/Probe.qml" << 'EOF'
import QtQuick
Item {
    id: root
    property string expected: ""
    property string marker: "probe"
    property string rawPath: ""
    property bool pathOk: false
    property bool siblingOk: false
    property bool storeOk: false
    Sibling { id: sib }
    Component.onCompleted: {
        var url = String(Qt.resolvedUrl("."))
        var raw = url.indexOf("file://") === 0 ? url.substring(7).replace(/\/$/, "") : ""
        rawPath = raw
        pathOk = raw === expected
        siblingOk = sib.marker === "sibling-ok"
        ServiceStore.instance = root
        storeOk = ServiceStore.instance === root
    }
}
EOF
cat > "$BASE/Watcher.qml" << 'EOF'
import QtQuick
Item {
    property var svc: ServiceStore.instance ? ServiceStore.instance : null
    property int updates: 0
    onSvcChanged: updates = updates + 1
}
EOF
cat > "$WORK/launch.qml" << EOF
import QtQuick
Item {
    Component.onCompleted: {
        var path = "$BASE"
        function fileUrl(name) {
            return "file://" + (path + "/" + name).split("/").map(encodeURIComponent).join("/")
        }
        var watcherComp = Qt.createComponent(fileUrl("Watcher.qml"))
        if (watcherComp.status !== Component.Ready) Qt.exit(2)
        var watcher = watcherComp.createObject(this)
        if (watcher.svc !== null) Qt.exit(3)
        var probeComp = Qt.createComponent(fileUrl("Probe.qml"))
        if (probeComp.status !== Component.Ready) Qt.exit(4)
        var probe = probeComp.createObject(this, { expected: path })
        if (!probe.pathOk || !probe.siblingOk || !probe.storeOk) Qt.exit(5)
        if (!watcher.svc || watcher.svc.marker !== "probe") Qt.exit(6)
        probe.destroy()
        Qt.callLater(function() {
            Qt.exit(watcher.svc === null ? 0 : 7)
        })
    }
}
EOF
set +e
QT_QPA_PLATFORM=offscreen qml6 "$WORK/launch.qml" >"$WORK/launch.out" 2>"$WORK/launch.err"
launch_status=$?
set -e
if [[ $launch_status -ne 0 ]]; then
  echo "launch exit $launch_status" >&2
  cat "$WORK/launch.out" "$WORK/launch.err" >&2 || true
  fail "ServiceStore/pluginDir probe failed"
fi
echo "    ServiceStore and pluginDir ok"
echo "PASS"
