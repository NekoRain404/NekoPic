import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    RecoveryPage — recovery snapshot status, close confirmation and reset.

    The page is presentation only. Snapshot metadata arrives through
    properties, and user intent is reported through signals.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-recovery"

    property string localeId: "zh_CN"
    property bool busy: false
    property bool recoveryAvailable: false
    property string recoverySourceName: ""
    property string recoveryCapturedAt: ""
    property string recoveryImageSize: ""
    property alias recoveryEnabled: recoveryToggle.checked
    property alias confirmOnClose: confirmOnCloseToggle.checked

    signal recoveryEnabledToggled(bool checked)
    signal confirmOnCloseToggled(bool checked)
    signal recoveryDiscardRequested()
    signal resetRequested()

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

    NekoSectionHeader {
        objectName: "settings-section-recovery"
        Layout.fillWidth: true
        text: page._tr("恢复与安全", "Recovery & Safety")
        eyebrow: true
        showDivider: true
    }

    Text {
        Layout.fillWidth: true
        text: page._tr(
                  "自动恢复会在文档有未保存更改时，将渲染结果作为 PNG 快照写入本机应用数据目录。快照不会离开本设备，正常保存或正常退出后会自动删除。恢复后的文档是扁平化图像，对象不可再编辑。",
                  "Crash recovery writes a PNG snapshot of the rendered document to local app data while there are unsaved changes. Snapshots never leave this device and are removed after a clean save or a normal exit. A recovered document is flattened, so objects cannot be edited.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSmall
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }

    SettingRow {
        label: page._tr("自动保存恢复快照", "Save recovery snapshots")
        hint: page._tr("关闭后不再写入新快照，已有快照仍可恢复。",
                       "When off, no new snapshots are written; existing snapshots can still be recovered.")

        NekoToggle {
            id: recoveryToggle
            objectName: "settings-recovery-enabled"
            checked: true
            enabled: !page.busy
            accessibleName: page._tr("自动保存恢复快照", "Save recovery snapshots")
            onClicked: page.recoveryEnabledToggled(checked)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: recoveryStatusColumn.implicitHeight + Theme.spacingLg * 2
        radius: Theme.radiusMd
        color: Theme.background
        border.width: Theme.borderWidth
        border.color: Theme.border

        ColumnLayout {
            id: recoveryStatusColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Text {
                    objectName: "settings-recovery-status"
                    Layout.fillWidth: true
                    text: page.recoveryAvailable
                          ? page._tr("发现可恢复的快照", "Recovery snapshot available")
                          : page._tr("当前没有恢复快照", "No recovery snapshot available")
                    color: page.recoveryAvailable ? Theme.textPrimary : Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Theme.fontWeightMedium
                    wrapMode: Text.WordWrap
                }

                NekoButton {
                    objectName: "settings-recovery-discard"
                    visible: page.recoveryAvailable
                    text: page._tr("清除快照", "Discard snapshot")
                    variant: "ghost"
                    enabled: !page.busy
                    onClicked: page.recoveryDiscardRequested()
                }
            }

            Text {
                objectName: "settings-recovery-details"
                Layout.fillWidth: true
                visible: page.recoveryAvailable
                text: [page.recoverySourceName, page.recoveryCapturedAt,
                       page.recoveryImageSize].filter(function(part) {
                           return part !== undefined && part !== null
                                  && String(part).length > 0
                       }).join(" · ")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: page.recoveryAvailable
                      ? page._tr("启动时会提示恢复或放弃。", "A prompt offers Restore or Discard at startup.")
                      : page._tr("编辑文档后，快照会在这里显示。", "Snapshots appear here after a document is edited.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingRow {
        label: page._tr("关闭前确认", "Confirm before closing")
        hint: page._tr("有未保存更改时提示确认。",
                       "Ask for confirmation when there are unsaved changes.")

        NekoToggle {
            id: confirmOnCloseToggle
            objectName: "settings-confirm-on-close"
            checked: true
            enabled: !page.busy
            accessibleName: page._tr("关闭前确认", "Confirm before closing")
            onClicked: page.confirmOnCloseToggled(checked)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.borderWidth
        color: Theme.separator
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingMd

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Text {
                Layout.fillWidth: true
                text: page._tr("恢复默认设置", "Reset to defaults")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontWeightMedium
            }
            Text {
                Layout.fillWidth: true
                text: page._tr("将外观、编辑、导出、语言与恢复选项恢复为默认值。",
                               "Restore appearance, editing, export, language and recovery options to their defaults.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }
        }

        NekoButton {
            objectName: "settings-reset"
            text: page._tr("恢复默认设置", "Reset to defaults")
            variant: "secondary"
            iconName: "reset"
            enabled: !page.busy
            onClicked: page.resetRequested()
        }
    }
}
