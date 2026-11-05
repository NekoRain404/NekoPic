import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme: ({ panel: "#222426", background: "#181a1b", raised: "#2b2d2f",
                           hover: "#343638", border: "#343638", text: "#e9e9e6",
                           muted: "#929794", accent: "#edbc9d" })
    property bool brushMode: true
    property real brushDiameter: 24
    property int blockSize: 12
    implicitWidth: 292
    color: theme.panel

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 23; spacing: 18
        Label { text: qsTr("PIXELATE"); font.pixelSize: 9; font.weight: Font.DemiBold; color: root.theme.muted }
        Label { text: qsTr("Mosaic"); font.pixelSize: 19; font.weight: Font.DemiBold; color: root.theme.text }
        RowLayout {
            Layout.fillWidth: true; spacing: 3
            Repeater {
                model: [qsTr("Brush"), qsTr("Rectangle")]
                delegate: Button {
                    id: modeButton
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "mosaic-mode-brush" : "mosaic-mode-rectangle"
                    Layout.fillWidth: true; implicitHeight: 32
                    text: modelData
                    checkable: true; checked: root.brushMode === (index === 0)
                    onClicked: root.brushMode = index === 0
                    background: Rectangle {
                        radius: 5
                        color: modeButton.checked ? root.theme.raised : modeButton.hovered ? root.theme.hover : "transparent"
                        border.color: modeButton.visualFocus ? root.theme.accent : "transparent"
                    }
                    contentItem: Label {
                        text: modeButton.text; color: modeButton.checked ? root.theme.text : root.theme.muted
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 11; opacity: root.enabled ? 1 : 0.5
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 8; opacity: root.enabled ? 1 : 0.5
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Brush diameter"); color: root.theme.muted; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: Math.round(root.brushDiameter) + " px"; color: root.theme.text; font.pixelSize: 10 }
            }
            Slider {
                objectName: "mosaic-brush-diameter"
                Layout.fillWidth: true; enabled: root.brushMode
                from: 4; to: 512; stepSize: 1; value: root.brushDiameter
                onMoved: root.brushDiameter = Math.round(value)
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 10
                Label { text: qsTr("Block size"); color: root.theme.muted; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: root.blockSize + " px"; color: root.theme.text; font.pixelSize: 10 }
            }
            Slider {
                objectName: "mosaic-block-size"
                Layout.fillWidth: true
                from: 2; to: 128; stepSize: 1; value: root.blockSize
                onMoved: root.blockSize = Math.round(value)
            }
        }
        Label {
            Layout.fillWidth: true
            text: root.brushMode ? qsTr("Paint over an area to pixelate it.") : qsTr("Drag a rectangle to pixelate an area.")
            wrapMode: Text.WordWrap; color: root.theme.muted; font.pixelSize: 11
        }
        Label {
            Layout.fillWidth: true
            text: qsTr("Esc cancels the current gesture.")
            wrapMode: Text.WordWrap; color: root.theme.muted; font.pixelSize: 10
        }
        Label {
            text: qsTr("Pixelation") + "  ⓘ"; color: root.theme.muted; font.pixelSize: 10
            ToolTip.visible: safetyHover.containsMouse
            ToolTip.text: qsTr("Pixelation does not guarantee privacy. Check the exported image before sharing.")
            MouseArea { id: safetyHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        }
        Item { Layout.fillHeight: true }
    }
}
