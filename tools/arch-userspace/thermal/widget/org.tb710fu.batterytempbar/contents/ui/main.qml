import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property real tempC: 0
    property real t1: 38000
    property real t2: 39000
    property real t3: 40000
    property int battTier: -1
    property string battStatus: "unknown"
    property int battCapacity: 0
    property string guardState: "absent"
    property int cap0: 0
    property int cap1: 0
    property int cap3: 0
    property int cap5: 0
    property real cpuMaxC: 0
    property int cpuMaxRaw: 0
    property string cpuZone: ""
    property bool hasData: false
    property bool dataError: false

    // ---- user configuration ----
    readonly property int barWidthPx: {
        const v = Number(Plasmoid.configuration.widgetWidth)
        return isNaN(v) ? 120 : Math.max(100, Math.min(240, v))
    }
    readonly property real trackAlpha: {
        const v = Number(Plasmoid.configuration.trackOpacity)
        return (isNaN(v) ? 10 : Math.max(0, Math.min(40, v))) / 100
    }
    readonly property bool cfgShowBattery: Plasmoid.configuration.showBattery !== false
    readonly property bool cfgShowCpu: Plasmoid.configuration.showCpu !== false
    // Never let both rows disappear (otherwise the applet cannot be configured).
    readonly property bool showBatteryRow: cfgShowBattery || !cfgShowCpu
    readonly property bool showCpuRow: cfgShowCpu
    readonly property bool showValues: Plasmoid.configuration.showLabels !== false
    readonly property int rowHeight: 15
    readonly property int compactHeight: (showBatteryRow ? rowHeight : 0)
        + (showCpuRow ? rowHeight : 0)

    // ---- battery bar ----
    readonly property real batteryProgress: Math.min(1, Math.max(0.10, (root.tempC - 30) / 10))
    readonly property bool batteryPulse: root.battTier >= 3 || (root.battTier < 0 && root.tempC >= root.t3 / 1000)
    readonly property color batteryColor: {
        const tier = root.battTier
        if (tier >= 3) return "#A31FFA"
        if (tier === 2) return "#FF453A"
        if (tier === 1) return "#FFD60A"
        if (tier === 0) return root.tempC < 30 ? "#34D399" : "#34C759"
        if (root.tempC >= root.t3 / 1000) return "#A31FFA"
        if (root.tempC >= root.t2 / 1000) return "#FF453A"
        if (root.tempC >= root.t1 / 1000) return "#FFD60A"
        return root.tempC < 30 ? "#34D399" : "#34C759"
    }

    // ---- CPU max bar (all cpuN-* core sensors, excluding cpuss) ----
    readonly property real cpuProgress: Math.min(1, Math.max(0.02, (root.cpuMaxC - 40) / 55))
    readonly property bool cpuPulse: root.cpuMaxC >= 95
    readonly property color cpuColor: {
        if (root.cpuMaxC >= 95) return "#A31FFA"
        if (root.cpuMaxC >= 90) return "#FF453A"
        if (root.cpuMaxC >= 80) return "#FFD60A"
        return "#34C759"
    }

    readonly property string statusText: {
        switch (root.battStatus) {
        case "Charging": return "充电中"
        case "Discharging": return "放电中"
        case "Full": return "已充满"
        case "Not charging": return "未充电"
        default: return root.battStatus
        }
    }
    readonly property string tierText: {
        switch (root.battTier) {
        case 4: return "4 · 应急，最低频 + 停充"
        case 3: return "3 · 紫，大幅限频"
        case 2: return "2 · 红，中幅限频"
        case 1: return "1 · 黄，轻度限频"
        case 0: return "0 · 正常"
        default: return "未知"
        }
    }
    readonly property string capText: {
        if (root.cap5 <= 0 || root.cap1 <= 0 || root.cap0 <= 0)
            return "—"
        const g = (v) => (v / 1000000).toFixed(2)
        return "X4 " + g(root.cap5) + " / A720 " + g(root.cap1)
            + " / A520 " + g(root.cap0) + " GHz"
    }
    readonly property string guardText: {
        if (root.guardState === "active") return "运行中"
        if (root.guardState === "stale") return "状态过期"
        return "未运行"
    }

    Plasmoid.icon: "battery-good-symbolic"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    switchWidth: Kirigami.Units.gridUnit * 19
    switchHeight: Kirigami.Units.gridUnit * 19

    toolTipMainText: {
        if (!root.hasData) return "电池 / CPU 温度"
        let s = "电池 " + root.tempC.toFixed(1) + " °C"
        if (root.cpuMaxRaw > 0) s += " · CPU " + root.cpuMaxC.toFixed(1) + " °C"
        return s
    }
    toolTipSubText: {
        if (!root.hasData) return "读取中…"
        let s = root.statusText + " · " + root.battCapacity + "%"
        if (root.battTier >= 0) s += " · 电池档 " + root.battTier
        if (root.cpuZone.length > 0) s += " · CPU 热点 " + root.cpuZone
        if (root.guardState !== "active") s += " · 温控" + (root.guardState === "stale" ? "状态过期" : "未运行")
        return s
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "打开温控日志"
            icon.name: "document-open"
            onTriggered: Qt.openUrlExternally("file:///var/log/tb-thermal-guard.csv")
        },
        PlasmaCore.Action {
            text: "打开温控状态"
            icon.name: "document-open"
            onTriggered: Qt.openUrlExternally("file:///run/tb-thermal-guard.state")
        }
    ]

    P5Support.DataSource {
        id: batterySource
        engine: "executable"
        connectedSources: ["/home/archlinux/.local/bin/tb-batt-read"]
        interval: 2000
        onNewData: (sourceName, data) => {
            const raw = data && data.stdout !== undefined ? String(data.stdout).trim() : ""
            if (raw === "") {
                if (!root.dataError) {
                    console.warn("tb-batterytempbar: no output from tb-batt-read", data && data.stderr)
                    root.dataError = true
                }
                return
            }
            try {
                const d = JSON.parse(raw)
                root.tempC = isNaN(Number(d.temp_c)) ? 0 : Number(d.temp_c)
                root.t1 = isNaN(Number(d.t1)) ? 38000 : Number(d.t1)
                root.t2 = isNaN(Number(d.t2)) ? 39000 : Number(d.t2)
                root.t3 = isNaN(Number(d.t3)) ? 40000 : Number(d.t3)
                root.battTier = isNaN(Number(d.tier)) ? -1 : Number(d.tier)
                root.battStatus = d.status !== undefined ? String(d.status) : "unknown"
                root.battCapacity = isNaN(Number(d.capacity)) ? 0 : Number(d.capacity)
                root.guardState = d.guard !== undefined ? String(d.guard) : "absent"
                root.cap0 = isNaN(Number(d.cap0)) ? 0 : Number(d.cap0)
                root.cap1 = isNaN(Number(d.cap1)) ? 0 : Number(d.cap1)
                root.cap3 = isNaN(Number(d.cap3)) ? 0 : Number(d.cap3)
                root.cap5 = isNaN(Number(d.cap5)) ? 0 : Number(d.cap5)
                root.cpuMaxRaw = isNaN(Number(d.cpu_max)) ? 0 : Number(d.cpu_max)
                root.cpuMaxC = isNaN(Number(d.cpu_max_c)) ? 0 : Number(d.cpu_max_c)
                root.cpuZone = d.cpu_zone !== undefined ? String(d.cpu_zone) : ""
                root.hasData = true
                if (root.dataError) {
                    console.info("tb-batterytempbar: data recovered")
                    root.dataError = false
                }
            } catch (e) {
                if (!root.dataError) {
                    console.warn("tb-batterytempbar: JSON parse failed:", e, raw)
                    root.dataError = true
                }
            }
        }
    }

    compactRepresentation: Item {
        id: compact
        Layout.preferredWidth: root.barWidthPx
        Layout.minimumWidth: root.barWidthPx
        Layout.maximumWidth: root.barWidthPx
        Layout.preferredHeight: 30
        Layout.minimumHeight: 30
        Layout.maximumHeight: 30
        implicitWidth: root.barWidthPx
        implicitHeight: 30

        // One continuous track behind both rows (the "shadow").
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: root.barWidthPx
            height: root.compactHeight
            radius: Math.min(5, height / 2)
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b,
                           root.trackAlpha)
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: root.barWidthPx
            spacing: 0

            TempBar {
                width: parent.width
                height: root.rowHeight
                visible: root.showBatteryRow
                showTrack: false
                valueText: root.hasData ? root.tempC.toFixed(1) + "°" : "—"
                showValue: root.showValues
                progress: root.batteryProgress
                fillColor: root.batteryColor
                pulsing: root.batteryPulse
                trackOpacity: root.trackAlpha
            }

            TempBar {
                width: parent.width
                height: root.rowHeight
                visible: root.showCpuRow
                showTrack: false
                valueText: (root.hasData && root.cpuMaxRaw > 0) ? root.cpuMaxC.toFixed(1) + "°" : "—"
                showValue: root.showValues
                progress: root.cpuProgress
                fillColor: root.cpuColor
                pulsing: root.cpuPulse
                trackOpacity: root.trackAlpha
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 19
        Layout.preferredHeight: Kirigami.Units.gridUnit * 19
        collapseMarginsHint: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: "温度"
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: root.hasData ? root.tempC.toFixed(1) + " / "
                        + (root.cpuMaxRaw > 0 ? root.cpuMaxC.toFixed(1) : "—") + " °C" : "—"
                    font.bold: true
                }
            }

            TempBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                valueText: root.hasData ? root.tempC.toFixed(1) + "°" : "—"
                showValue: root.showValues
                progress: root.batteryProgress
                fillColor: root.batteryColor
                pulsing: root.batteryPulse
                trackOpacity: root.trackAlpha
            }

            TempBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                valueText: (root.hasData && root.cpuMaxRaw > 0) ? root.cpuMaxC.toFixed(1) + "°" : "—"
                showValue: root.showValues
                progress: root.cpuProgress
                fillColor: root.cpuColor
                pulsing: root.cpuPulse
                trackOpacity: root.trackAlpha
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                rowSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label { text: "电池状态" }
                PlasmaComponents3.Label {
                    text: root.statusText + " · " + root.battCapacity + "%"
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label { text: "电池温控档" }
                PlasmaComponents3.Label { text: root.tierText; Layout.fillWidth: true }

                PlasmaComponents3.Label { text: "CPU 最高" }
                PlasmaComponents3.Label {
                    text: root.cpuMaxRaw > 0
                        ? root.cpuMaxC.toFixed(1) + " °C · " + root.cpuZone
                        : "—"
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label { text: "频率上限" }
                PlasmaComponents3.Label {
                    text: root.capText
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label { text: "温控服务" }
                PlasmaComponents3.Label { text: root.guardText; Layout.fillWidth: true }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.8
                text: "电池 " + (root.t1 / 1000).toFixed(1) + "/" + (root.t2 / 1000).toFixed(1) + "/"
                    + (root.t3 / 1000).toFixed(1) + " °C：黄/红/紫，限 X4 2.6/2.3/2.0 GHz\n"
                    + "CPU 80/90/95 °C：黄/红/紫（范围 40–95）"
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Button {
                    text: "温控日志"
                    onClicked: Qt.openUrlExternally("file:///var/log/tb-thermal-guard.csv")
                }
                PlasmaComponents3.Button {
                    text: "温控状态"
                    onClicked: Qt.openUrlExternally("file:///run/tb-thermal-guard.state")
                }
                Item { Layout.fillWidth: true }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
