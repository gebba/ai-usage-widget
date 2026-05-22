import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QtControls
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/state.js" as State

PlasmoidItem {
    id: root

    property string stateDir: StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
    property string stateUrl: (stateDir.indexOf("file://") === 0 ? stateDir : "file://" + stateDir) + "/ai-usage-widget/state-cache.qml"
    property var usageState: cacheLoader.item && cacheLoader.item.state ? cacheLoader.item.state : ({"status": "loading", "limits": [], "lowestRemainingPercent": null})
    property string loadError: cacheLoader.status === Loader.Error ? "Could not load usage cache: " + stateUrl : ""
    property string helperCommand: State.localPath(StandardPaths.writableLocation(StandardPaths.HomeLocation)) + "/.local/lib/ai-usage-widget/codex_usage.py"
    property bool autoFetchEnabled: Plasmoid.configuration.autoRefreshEnabled !== false
    property bool hideCodexSparkUsage: Plasmoid.configuration.hideCodexSparkUsage === true
    property int autoFetchIntervalMs: 10 * 60 * 1000
    property bool fetchInProgress: false
    property string fetchStatus: ""

    Plasmoid.icon: "view-statistics"
    Plasmoid.title: "AI Usage"
    toolTipSubText: usageState.status === "ok"
        ? compactUsageLabel() + ": " + State.formatPercent(compactUsagePercent())
        : (usageState.error || loadError || "Waiting for usage cache")

    function reloadState() {
        // QML Loader can load a local file URL reliably inside Plasma. The helper
        // writes sanitized data as a tiny QtObject in state-cache.qml.
        cacheLoader.active = false
        cacheLoader.source = ""
        cacheLoader.source = stateUrl + "?t=" + Date.now()
        cacheLoader.active = true
    }

    function isSparkLimit(limit) {
        return limit && ((limit.name && limit.name.indexOf("Codex Spark") !== -1) || (limit.model && limit.model.indexOf("Codex-Spark") !== -1))
    }

    function visibleLimits() {
        var limits = usageState.limits || []
        if (!hideCodexSparkUsage) {
            return limits
        }
        return limits.filter(function(limit) { return !isSparkLimit(limit) })
    }

    function compactUsageLimit() {
        var limits = visibleLimits()
        for (var i = 0; i < limits.length; i++) {
            if (limits[i].scope === "shared" && Number(limits[i].windowSeconds) === 18000) {
                return limits[i]
            }
        }
        for (var j = 0; j < limits.length; j++) {
            if (limits[j].scope === "shared") {
                return limits[j]
            }
        }
        for (var k = 0; k < limits.length; k++) {
            if (!isSparkLimit(limits[k]) && Number(limits[k].windowSeconds) === 18000) {
                return limits[k]
            }
        }
        return limits.length > 0 ? limits[0] : null
    }

    function compactUsagePercent() {
        var limit = compactUsageLimit()
        if (limit && limit.remainingPercent !== undefined && limit.remainingPercent !== null) {
            return limit.remainingPercent
        }
        return usageState.lowestRemainingPercent
    }

    function compactUsageLabel() {
        var limit = compactUsageLimit()
        if (!limit) {
            return "Codex session remaining"
        }
        return limit.name || "Codex session remaining"
    }

    function fetchUsage() {
        if (fetchInProgress) {
            return
        }
        fetchInProgress = true
        fetchStatus = "Refreshing…"
        usageFetcher.connectSource(helperCommand)
    }

    Component.onCompleted: {
        reloadState()
        if (autoFetchEnabled) {
            fetchUsage()
        }
    }

    Plasma5Support.DataSource {
        id: usageFetcher
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.fetchInProgress = false
            var exitCode = data["exit code"]
            if (exitCode !== undefined && Number(exitCode) !== 0) {
                root.fetchStatus = "Refresh failed (exit " + exitCode + ")"
            } else {
                root.fetchStatus = ""
            }
            root.reloadState()
        }
    }

    Loader {
        id: cacheLoader
        active: false
        asynchronous: false
        visible: false
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.reloadState()
    }

    Timer {
        interval: root.autoFetchIntervalMs
        running: root.autoFetchEnabled
        repeat: true
        onTriggered: root.fetchUsage()
    }

    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit * 4
        implicitHeight: Kirigami.Units.gridUnit * 2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Codex"
                font.pointSize: 8
                opacity: 0.75
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: State.formatPercent(root.compactUsagePercent())
                color: State.severityColor(root.compactUsagePercent(), Kirigami.Theme)
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: PlasmaComponents3.ScrollView {
        id: fullScroll
        implicitWidth: Kirigami.Units.gridUnit * 15
        implicitHeight: contentLayout.implicitHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: contentLayout.implicitHeight
        contentWidth: availableWidth
        contentHeight: contentLayout.implicitHeight
        QtControls.ScrollBar.horizontal.policy: QtControls.ScrollBar.AlwaysOff
        QtControls.ScrollBar.vertical.policy: QtControls.ScrollBar.AlwaysOff

        ColumnLayout {
            id: contentLayout
            width: fullScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.usageState.status !== "ok" || root.loadError.length > 0 || root.fetchStatus.length > 0
                text: root.usageState.error || root.loadError || root.fetchStatus || ("Loading usage cache from " + root.stateUrl)
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 1
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.visibleLimits()

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 6.5
                        radius: Kirigami.Units.largeSpacing
                        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.82)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing * 1.5
                            spacing: 1

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.windowLabel || "Usage limit"
                                opacity: 0.88
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: State.formatPercent(modelData.remainingPercent)
                                color: State.severityColor(modelData.remainingPercent, Kirigami.Theme)
                                font.bold: true
                                font.pointSize: 19
                            }

                            QtControls.ProgressBar {
                                id: usageBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.smallSpacing * 2.5
                                from: 0
                                to: 100
                                value: modelData.remainingPercent || 0
                                background: Rectangle {
                                    implicitHeight: Kirigami.Units.smallSpacing * 2.5
                                    radius: height / 2
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                }
                                contentItem: Item {
                                    implicitHeight: Kirigami.Units.smallSpacing * 2.5
                                    Rectangle {
                                        width: usageBar.visualPosition * parent.width
                                        height: parent.height
                                        radius: height / 2
                                        color: State.limitColor(modelData.remainingPercent)
                                    }
                                }
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: State.resetText(modelData.resetAt, modelData.windowSeconds)
                                visible: text.length > 0
                                opacity: 0.65
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: State.freshnessText(root.usageState.updatedAt)
                opacity: 0.6
                wrapMode: Text.WordWrap
            }
        }
    }
}
