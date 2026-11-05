import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    EditingPage — GPU preview, checkerboard and startup-tool preferences.

    The page is presentation only: toggles expose their checked state as
    aliases for SettingsDialog's public contract, and user intent is reported
    through signals.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-editing"

    property string localeId: "zh_CN"
    property bool busy: false
    property string startupTool: "adjust"
    property var startupToolOptions: []
    property alias gpuPreviewEnabled: gpuPreviewToggle.checked
    property alias showCheckerboard: checkerboardToggle.checked

    signal gpuPreviewToggled(bool checked)
    signal checkerboardToggled(bool checked)
    signal startupToolSelected(string id)

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    NekoSectionHeader {
        objectName: "settings-section-editing"
        Layout.fillWidth: true
        text: qsTr("Editing")
        eyebrow: true
        showDivider: true
    }

    SettingRow {
        label: qsTr("GPU preview")
        hint: qsTr("Use hardware-accelerated live previews while adjusting; falls back to CPU when off.")

        NekoToggle {
            id: gpuPreviewToggle
            objectName: "settings-gpu-preview"
            checked: true
            enabled: !page.busy
            accessibleName: qsTr("GPU preview")
            onClicked: page.gpuPreviewToggled(checked)
        }
    }

    SettingRow {
        label: qsTr("Show transparency checkerboard")
        hint: qsTr("Show a checkerboard pattern behind transparent areas.")

        NekoToggle {
            id: checkerboardToggle
            objectName: "settings-checkerboard"
            checked: true
            enabled: !page.busy
            accessibleName: qsTr("Show transparency checkerboard")
            onClicked: page.checkerboardToggled(checked)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: qsTr("Startup tool")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontWeightMedium
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("Tool selected after an image opens; applies the next time an image is opened.")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: page.startupToolOptions

                delegate: NekoButton {
                    required property var modelData
                    objectName: "settings-startup-tool-" + modelData.id
                    text: modelData.label
                    variant: page.startupTool === modelData.id ? "primary" : "secondary"
                    enabled: !page.busy
                    Accessible.checkable: true
                    Accessible.checked: page.startupTool === modelData.id
                    onClicked: page.startupToolSelected(modelData.id)
                }
            }
        }
    }
}
