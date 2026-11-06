import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    EyedropperPanel — the right-hand colour inspector for the eyedropper.

    Shows the live sample under the pointer (the overlay emits `sampled` while
    hovering or dragging) and the last committed pick. Values are computed from
    the QML colour object, so the panel works with any image format the
    controller can sample.
*/
Rectangle {
    id: root

    objectName: "eyedropperPanel"
    property color colorValue: "#000000"
    property bool hasSample: false
    property point samplePosition: Qt.point(0, 0)
    property string positionText: ""
    property int sampleRadius: 0
    property string emptyHint: qsTr("Move the pointer over the image to sample a colour.")

    Layout.fillHeight: true
    color: Theme.panel

    signal copyRequested(string text)

    function _component(value) {
        const v = Math.max(0, Math.min(255, Math.round(value * 255)))
        return (v < 16 ? "0" : "") + v.toString(16).toUpperCase()
    }

    function hexText() {
        return "#" + _component(colorValue.r) + _component(colorValue.g)
                + _component(colorValue.b)
    }

    function rgbText() {
        return Math.round(colorValue.r * 255) + ", "
                + Math.round(colorValue.g * 255) + ", "
                + Math.round(colorValue.b * 255)
    }

    function hslText() {
        const r = colorValue.r, g = colorValue.g, b = colorValue.b
        const max = Math.max(r, g, b), min = Math.min(r, g, b)
        const l = (max + min) / 2
        let h = 0, s = 0
        if (max !== min) {
            const d = max - min
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
            if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
            else if (max === g) h = (b - r) / d + 2
            else h = (r - g) / d + 4
            h /= 6
        }
        return Math.round(h * 360) + "°, " + Math.round(s * 100) + "%, "
                + Math.round(l * 100) + "%"
    }

    function copyHex() {
        if (!hasSample)
            return
        clipboardHelper.text = hexText()
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
        copyRequested(hexText())
    }

    // Hidden helper: QML has no public clipboard API, TextEdit does.
    TextEdit {
        id: clipboardHelper
        visible: false
        width: 1
        height: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            NekoIcon {
                width: 20
                height: 20
                name: "eye"
                color: Theme.textPrimary
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Colour information")
                color: Theme.textPrimary
                font.pixelSize: 19
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 116
            radius: Theme.radiusMd
            color: root.hasSample ? root.colorValue : Theme.surface
            border.width: Theme.borderWidth
            border.color: root.hasSample ? Theme.border : Theme.separator

            Text {
                anchors.centerIn: parent
                visible: root.hasSample
                text: root.hexText()
                color: Theme.contrastColor(root.colorValue)
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
            Text {
                anchors.centerIn: parent
                visible: !root.hasSample
                text: qsTr("No sample yet")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSmall
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Repeater {
                model: [
                    { label: qsTr("HEX"), value: root.hasSample ? root.hexText() : "—" },
                    { label: qsTr("RGB"), value: root.hasSample ? root.rgbText() : "—" },
                    { label: qsTr("HSL"), value: root.hasSample ? root.hslText() : "—" },
                    { label: qsTr("Position"), value: root.hasSample
                              ? (root.positionText.length > 0 ? root.positionText
                                 : Math.round(root.samplePosition.x) + ", "
                                   + Math.round(root.samplePosition.y))
                              : "—" }
                ]

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Text {
                        Layout.preferredWidth: 66
                        text: modelData.label
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.fontWeightMedium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.value
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.family: "monospace"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        NekoButton {
            Layout.fillWidth: true
            text: qsTr("Copy HEX")
            iconName: "copy"
            variant: "secondary"
            enabled: root.hasSample
            onClicked: root.copyHex()
        }

        Item { Layout.fillHeight: true }

        Text {
            Layout.fillWidth: true
            text: root.hasSample
                  ? qsTr("Hover or drag to update · click to set the shared foreground colour")
                  : root.emptyHint
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }
    }
}
