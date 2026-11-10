import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property alias cfg_showBattery: showBattery.checked
    property alias cfg_showCpu: showCpu.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_trackOpacity: trackOpacity.value
    property alias cfg_widgetWidth: widgetWidth.value

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.CheckBox {
            id: showBattery
            Kirigami.FormData.label: "显示："
            text: "电池温度条"
        }

        QQC2.CheckBox {
            id: showCpu
            text: "CPU 温度条（核心最大值）"
        }

        QQC2.CheckBox {
            id: showLabels
            text: "显示温度数值"
        }

        QQC2.SpinBox {
            id: trackOpacity
            Kirigami.FormData.label: "阴影不透明度："
            from: 0
            to: 40
            stepSize: 1
            editable: true
            textFromValue: function(value) { return value + " %" }
            valueFromText: function(text) { return parseInt(text) || 0 }
        }

        QQC2.SpinBox {
            id: widgetWidth
            Kirigami.FormData.label: "长度："
            from: 100
            to: 240
            stepSize: 4
            editable: true
            textFromValue: function(value) { return value + " px" }
            valueFromText: function(text) { return parseInt(text) || 120 }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: "电池 38/39/40°C：黄/红/紫\nCPU 80/90/95°C：黄/红/紫（范围 40–95）"
        }
    }
}
