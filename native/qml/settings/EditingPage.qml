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

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

    NekoSectionHeader {
        objectName: "settings-section-editing"
        Layout.fillWidth: true
        text: page._tr("编辑", "Editing")
        eyebrow: true
        showDivider: true
    }

    SettingRow {
        label: page._tr("GPU 预览", "GPU preview")
        hint: page._tr("调整时使用硬件加速的实时预览；关闭后回退到 CPU。",
                       "Use hardware-accelerated live previews while adjusting; falls back to CPU when off.")

        NekoToggle {
            id: gpuPreviewToggle
            objectName: "settings-gpu-preview"
            checked: true
            enabled: !page.busy
            accessibleName: page._tr("GPU 预览", "GPU preview")
            onClicked: page.gpuPreviewToggled(checked)
        }
    }

    SettingRow {
        label: page._tr("显示透明棋盘格", "Show transparency checkerboard")
        hint: page._tr("在透明区域后方显示棋盘格图案。",
                       "Show a checkerboard pattern behind transparent areas.")

        NekoToggle {
            id: checkerboardToggle
            objectName: "settings-checkerboard"
            checked: true
            enabled: !page.busy
            accessibleName: page._tr("显示透明棋盘格", "Show transparency checkerboard")
            onClicked: page.checkerboardToggled(checked)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: page._tr("启动工具", "Startup tool")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontWeightMedium
        }
        Text {
            Layout.fillWidth: true
            text: page._tr("打开图片后默认使用的工具；下次打开图片时生效。",
                           "Tool selected after an image opens; applies the next time an image is opened.")
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
