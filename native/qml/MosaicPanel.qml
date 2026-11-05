import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "UI"

Rectangle {
    id: root
    property var theme: ({ panel: Theme.panel, background: Theme.background,
                           raised: Theme.surfaceRaised, hover: Theme.hover,
                           border: Theme.border, text: Theme.textPrimary,
                           muted: Theme.textSecondary, accent: Theme.accent })
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
                delegate: NekoButton {
                    id: modeButton
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "mosaic-mode-brush" : "mosaic-mode-rectangle"
                    Layout.fillWidth: true; implicitHeight: 32
                    text: modelData
                    variant: root.brushMode === (index === 0) ? "primary" : "secondary"
                    onClicked: root.brushMode = index === 0
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
            NekoSlider {
                id: diameterSlider
                objectName: "mosaic-brush-diameter"
                Layout.fillWidth: true; enabled: root.brushMode
                from: 4; to: 512; stepSize: 1; defaultValue: 24
                accessibleName: qsTr("Brush diameter")
                onPreview: function(value) { root.brushDiameter = Math.round(value) }
                Component.onCompleted: value = root.brushDiameter
                Connections { target: root; function onBrushDiameterChanged() { if (!diameterSlider.dragging) diameterSlider.value = root.brushDiameter } }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 10
                Label { text: qsTr("Block size"); color: root.theme.muted; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: root.blockSize + " px"; color: root.theme.text; font.pixelSize: 10 }
            }
            NekoSlider {
                id: blockSlider
                objectName: "mosaic-block-size"
                Layout.fillWidth: true
                from: 2; to: 128; stepSize: 1; defaultValue: 12
                accessibleName: qsTr("Block size")
                onPreview: function(value) { root.blockSize = Math.round(value) }
                Component.onCompleted: value = root.blockSize
                Connections { target: root; function onBlockSizeChanged() { if (!blockSlider.dragging) blockSlider.value = root.blockSize } }
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
