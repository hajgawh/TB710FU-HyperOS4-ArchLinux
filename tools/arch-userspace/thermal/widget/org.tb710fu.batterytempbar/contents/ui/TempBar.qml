import QtQuick
import org.kde.kirigami as Kirigami

/*
 * One temperature row: optional numeric value + capsule fill.
 * The compact panel layout draws one shared track behind both rows;
 * the full representation uses showTrack: true for each row.
 */
Item {
    id: bar
    property string valueText: ""
    property bool showValue: true
    property real progress: 0
    property color fillColor: "#34C759"
    property bool pulsing: false
    property real trackOpacity: 0.10
    property bool showTrack: true

    implicitHeight: 15

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Math.min(5, height / 2)
        visible: bar.showTrack
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b,
                       Math.max(0, Math.min(0.4, bar.trackOpacity)))
    }

    Text {
        id: value
        x: 6
        width: bar.showValue ? 40 : 0
        visible: bar.showValue
        anchors.verticalCenter: parent.verticalCenter
        text: bar.valueText
        color: Kirigami.Theme.textColor
        font.family: "monospace"
        font.pixelSize: Math.max(8, Math.min(12, Math.round(bar.height * 0.60)))
        font.bold: true
        horizontalAlignment: Text.AlignLeft
    }

    Rectangle {
        id: fill
        x: 6 + (bar.showValue ? 40 + 4 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(5, (bar.width - x - 6) * Math.max(0, Math.min(1, bar.progress)))
        height: Math.min(8, Math.max(5, Math.round(bar.height * 0.40)))
        radius: Math.min(2, height / 2)
        color: bar.fillColor
        opacity: 1

        SequentialAnimation {
            id: pulseAnim
            running: bar.pulsing
            loops: Animation.Infinite
            NumberAnimation {
                target: fill
                property: "opacity"
                from: 1.0
                to: 0.55
                duration: 800
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: fill
                property: "opacity"
                from: 0.55
                to: 1.0
                duration: 800
                easing.type: Easing.InOutSine
            }
            onRunningChanged: if (!running) fill.opacity = 1
        }
    }
}
