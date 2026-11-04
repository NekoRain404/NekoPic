import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme
    property int currentTab: 0
    property bool adjustmentsEnabled: false
    property var adjustmentValues: ({})
    signal adjustmentStarted(string key)
    signal adjustmentPreview(string key, real value)
    signal adjustmentFinished(string key, real value)
    signal adjustmentReset()
    color: theme.panel
    implicitWidth: 292

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        ColumnLayout {
            Layout.fillWidth: true; Layout.leftMargin: 23; Layout.rightMargin: 23
            Layout.topMargin: 20; Layout.bottomMargin: 16; spacing: 4
            Label { text: qsTr("LIGHT & COLOR"); font.pixelSize: 9; font.weight: Font.DemiBold; color: root.theme.muted }
            Label { text: root.currentTab === 0 ? qsTr("Adjust") : qsTr("Filters"); font.pixelSize: 19; font.weight: Font.DemiBold; color: root.theme.text }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 23; Layout.rightMargin: 23; spacing: 3
            Repeater {
                model: [qsTr("Adjust"), qsTr("Filters")]
                delegate: Button {
                    id: tab
                    required property string modelData; required property int index
                    Layout.fillWidth: true; implicitHeight: 32; text: modelData
                    onClicked: root.currentTab = index
                    background: Rectangle { radius: 5; color: root.currentTab === tab.index ? root.theme.raised : tab.hovered ? root.theme.hover : "transparent"; border.color: tab.visualFocus ? root.theme.accent : "transparent" }
                    contentItem: Label { text: tab.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: root.currentTab === tab.index ? root.theme.text : root.theme.muted; font.pixelSize: 11 }
                }
            }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.topMargin: 20; clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 0
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 23; Layout.rightMargin: 23; Layout.bottomMargin: 15
                    Label { text: root.currentTab === 0 ? qsTr("Basic adjustments") : qsTr("Presets"); color: root.theme.text; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Button {
                        id: resetButton
                        objectName: "adjustment-reset"
                        visible: root.currentTab === 0; enabled: root.adjustmentsEnabled
                        text: qsTr("Reset"); implicitHeight: 24; leftPadding: 7; rightPadding: 7
                        onClicked: root.adjustmentReset()
                        background: Rectangle { radius: 4; color: resetButton.hovered && resetButton.enabled ? root.theme.hover : "transparent"; border.color: resetButton.visualFocus ? root.theme.accent : "transparent" }
                        contentItem: Label { text: resetButton.text; color: root.theme.muted; opacity: resetButton.enabled ? 1 : 0.5; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                    }
                }
                Label {
                    visible: root.currentTab === 1
                    Layout.leftMargin: 23; Layout.rightMargin: 23; Layout.fillWidth: true; Layout.bottomMargin: 20
                    wrapMode: Text.WordWrap; text: qsTr("Editing tools are coming soon"); color: root.theme.muted; font.pixelSize: 11
                }
                Repeater {
                    model: root.currentTab === 0 ? [
                        { key: "exposure", label: qsTr("Exposure") },
                        { key: "brightness", label: qsTr("Brightness") },
                        { key: "contrast", label: qsTr("Contrast") },
                        { key: "saturation", label: qsTr("Saturation") }
                    ] : []
                    delegate: ColumnLayout {
                        id: adjustment
                        required property var modelData
                        Layout.fillWidth: true; Layout.leftMargin: 23; Layout.rightMargin: 23; Layout.bottomMargin: 18; spacing: 8
                        opacity: root.adjustmentsEnabled ? 1 : 0.55
                        Rectangle {
                            visible: adjustment.modelData.key === "saturation"
                            Layout.fillWidth: true; Layout.topMargin: 3; Layout.bottomMargin: 10
                            implicitHeight: 1; color: root.theme.border
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: adjustment.modelData.label; color: root.theme.muted; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: root.currentTab === 0; implicitWidth: 33; implicitHeight: 19; radius: 3; color: root.theme.background; border.color: root.theme.border
                                Label { anchors.centerIn: parent; text: (slider.value > 0 ? "+" : "") + Math.round(slider.value); color: root.theme.muted; font.pixelSize: 10 }
                            }
                        }
                        Slider {
                            id: slider
                            objectName: "adjustment-" + adjustment.modelData.key
                            visible: root.currentTab === 0; Layout.fillWidth: true; implicitHeight: 20; enabled: root.adjustmentsEnabled
                            from: -100; to: 100; value: 0; stepSize: 1
                            property bool editing: false
                            function syncValue() {
                                if (!editing && root.adjustmentValues && root.adjustmentValues[adjustment.modelData.key] !== undefined)
                                    value = root.adjustmentValues[adjustment.modelData.key]
                            }
                            Component.onCompleted: syncValue()
                            Connections { target: root; function onAdjustmentValuesChanged() { slider.syncValue() } }
                            onPressedChanged: {
                                if (pressed) {
                                    editing = true
                                    root.adjustmentStarted(adjustment.modelData.key)
                                }
                                else {
                                    root.adjustmentFinished(adjustment.modelData.key, value)
                                    editing = false
                                    syncValue()
                                }
                            }
                            onMoved: {
                                if (!pressed) {
                                    editing = true
                                    root.adjustmentStarted(adjustment.modelData.key)
                                }
                                root.adjustmentPreview(adjustment.modelData.key, value)
                                if (!pressed) {
                                    root.adjustmentFinished(adjustment.modelData.key, value)
                                    editing = false
                                    syncValue()
                                }
                            }
                            background: Rectangle {
                                x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2; width: slider.availableWidth; height: 3; radius: 2; color: root.theme.border
                                Rectangle { width: parent.width * slider.visualPosition; height: parent.height; radius: parent.radius; color: root.theme.accent }
                            }
                            handle: Rectangle { x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width); y: slider.topPadding + slider.availableHeight / 2 - height / 2; width: 12; height: 12; radius: 6; color: root.theme.text; border.width: slider.visualFocus ? 2 : 1; border.color: slider.visualFocus ? root.theme.accent : root.theme.panel }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
