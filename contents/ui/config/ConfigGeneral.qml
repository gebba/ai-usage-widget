import QtQuick
import QtQuick.Controls as QtControls
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../../code/state.js" as State

KCM.SimpleKCM {
    id: root

    property alias cfg_autoRefreshEnabled: autoRefresh.checked
    property alias cfg_hideCodexSparkUsage: hideSpark.checked

    property string stateDir: StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
    property string stateUrl: (stateDir.indexOf("file://") === 0 ? stateDir : "file://" + stateDir) + "/ai-usage-widget/state-cache.qml"
    property string helperCommand: State.localPath(StandardPaths.writableLocation(StandardPaths.HomeLocation)) + "/.local/lib/ai-usage-widget/codex_usage.py"
    property var usageState: cacheLoader.item && cacheLoader.item.state ? cacheLoader.item.state : ({"status": "loading"})
    property bool fetchInProgress: false
    property string refreshStatus: ""

    function reloadState() {
        cacheLoader.active = false
        cacheLoader.source = ""
        cacheLoader.source = stateUrl + "?t=" + Date.now()
        cacheLoader.active = true
    }

    function fetchUsage() {
        if (fetchInProgress) {
            return
        }
        fetchInProgress = true
        refreshStatus = "Refreshing…"
        usageFetcher.connectSource(helperCommand)
    }

    Component.onCompleted: reloadState()

    Loader {
        id: cacheLoader
        active: false
        asynchronous: false
        visible: false
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
                root.refreshStatus = "Refresh failed (exit " + exitCode + ")"
            } else {
                root.refreshStatus = "Refresh complete"
            }
            root.reloadState()
        }
    }

    Kirigami.FormLayout {
        QtControls.CheckBox {
            id: autoRefresh
            Kirigami.FormData.label: "Updates:"
            text: "Auto-refresh every 10 minutes"
        }

        QtControls.CheckBox {
            id: hideSpark
            text: "Hide Codex Spark usage"
        }

        QtControls.Button {
            text: root.fetchInProgress ? "Refreshing…" : "Refresh now"
            icon.name: "view-refresh"
            enabled: !root.fetchInProgress
            onClicked: root.fetchUsage()
        }

        QtControls.Label {
            Layout.fillWidth: true
            text: root.refreshStatus
            visible: text.length > 0
            wrapMode: Text.WordWrap
        }

        QtControls.Label {
            Kirigami.FormData.label: "Last updated:"
            Layout.fillWidth: true
            text: State.freshnessText(root.usageState.updatedAt)
            wrapMode: Text.WordWrap
        }

        QtControls.Label {
            Kirigami.FormData.label: "Source:"
            Layout.fillWidth: true
            text: root.usageState.source || "No source yet"
            wrapMode: Text.WordWrap
            opacity: 0.8
        }

        QtControls.Label {
            Kirigami.FormData.label: "Helper:"
            Layout.fillWidth: true
            text: root.helperCommand
            wrapMode: Text.WrapAnywhere
            opacity: 0.65
        }
    }
}
