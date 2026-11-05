import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme
    property real aspectRatio: 0
    property real imageAspectRatio: 1
    property real selectionWidth: 0
    property real selectionHeight: 0
    property bool canApply: false
    signal applyRequested()
    signal cancelRequested()
    signal resetRequested()
    color: theme.panel
    implicitWidth: 292
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 23; spacing: 16
        Label { text: qsTr("COMPOSITION"); font.pixelSize: 9; font.weight: Font.DemiBold; color: root.theme.muted }
        Label { text: qsTr("Crop"); font.pixelSize: 19; font.weight: Font.DemiBold; color: root.theme.text }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("Drag the edges to crop. Drag inside to move the selection.")
            color: root.theme.muted; font.pixelSize: 11
        }
        Label { text: qsTr("Aspect ratio"); color: root.theme.text; font.pixelSize: 11; font.weight: Font.DemiBold }
        GridLayout {
            Layout.fillWidth: true; columns: 2; rowSpacing: 8; columnSpacing: 8
            Repeater {
                model: [
                    { id: "free", label: qsTr("Free"), ratio: 0 },
                    { id: "original", label: qsTr("Original"), ratio: root.imageAspectRatio },
                    { id: "square", label: "1:1", ratio: 1 },
                    { id: "four-three", label: "4:3", ratio: 4/3 },
                    { id: "three-two", label: "3:2", ratio: 3/2 },
                    { id: "wide", label: "16:9", ratio: 16/9 }
                ]
                delegate: Button {
                    id: preset
                    required property var modelData
                    objectName: "crop-ratio-" + modelData.id
                    Layout.fillWidth: true; implicitHeight: 34
                    text: modelData.label
                    onClicked: root.aspectRatio = modelData.ratio
                    background: Rectangle {
                        radius: 5; color: preset.hovered ? root.theme.hover : root.theme.raised
                        border.color: Math.abs(root.aspectRatio - preset.modelData.ratio) < 0.0001 ? root.theme.accent : "transparent"
                    }
                    contentItem: Label {
                        text: preset.text; color: root.theme.text; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
        Button {
            objectName: "crop-swap"; text: qsTr("Swap orientation")
            Layout.fillWidth: true; enabled: root.aspectRatio > 0 && root.aspectRatio !== 1
            onClicked: root.aspectRatio = 1 / root.aspectRatio
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: root.theme.border }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Selection"); color: root.theme.muted; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Label {
                text: Math.ceil(root.selectionWidth) + " × " + Math.ceil(root.selectionHeight) + " px"
                color: root.theme.text; font.pixelSize: 11
            }
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: qsTr("Enter to apply · Esc to cancel"); color: root.theme.muted; font.pixelSize: 10
        }
        Item { Layout.fillHeight: true }
        Button {
            id: apply
            objectName: "crop-apply"; text: qsTr("Apply crop")
            Layout.fillWidth: true; implicitHeight: 36; enabled: root.canApply
            onClicked: root.applyRequested()
            background: Rectangle { radius: 5; color: root.theme.accent; opacity: apply.enabled ? 1 : 0.35 }
            contentItem: Label {
                text: apply.text; color: root.theme.accentInk; font.pixelSize: 11; font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Button { objectName: "crop-reset"; text: qsTr("Reset"); Layout.fillWidth: true; onClicked: root.resetRequested() }
            Button { objectName: "crop-cancel"; text: qsTr("Cancel"); Layout.fillWidth: true; onClicked: root.cancelRequested() }
        }
    }
}
