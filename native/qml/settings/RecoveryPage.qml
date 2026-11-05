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

    NekoSectionHeader {
        objectName: "settings-section-recovery"
        Layout.fillWidth: true
        text: qsTr("Recovery & Safety")
        eyebrow: true
        showDivider: true
    }

    Text {
        Layout.fillWidth: true
        text: qsTr("Crash recovery writes a PNG snapshot of the rendered document to local app data while there are unsaved changes. Snapshots never leave this device and are removed after a clean save or a normal exit. A recovered document is flattened, so objects cannot be edited.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSmall
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }

    SettingRow {
        label: qsTr("Save recovery snapshots")
        hint: qsTr("When off, no new snapshots are written; existing snapshots can still be recovered.")

        NekoToggle {
            id: recoveryToggle
            objectName: "settings-recovery-enabled"
            checked: true
            enabled: !page.busy
            accessibleName: qsTr("Save recovery snapshots")
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
                          ? qsTr("Recovery snapshot available")
                          : qsTr("No recovery snapshot available")
                    color: page.recoveryAvailable ? Theme.textPrimary : Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Theme.fontWeightMedium
                    wrapMode: Text.WordWrap
                }

                NekoButton {
                    objectName: "settings-recovery-discard"
                    visible: page.recoveryAvailable
                    text: qsTr("Discard snapshot")
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
                      ? qsTr("A prompt offers Restore or Discard at startup.")
                      : qsTr("Snapshots appear here after a document is edited.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingRow {
        label: qsTr("Confirm before closing")
        hint: qsTr("Ask for confirmation when there are unsaved changes.")

        NekoToggle {
            id: confirmOnCloseToggle
            objectName: "settings-confirm-on-close"
            checked: true
            enabled: !page.busy
            accessibleName: qsTr("Confirm before closing")
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
                text: qsTr("Reset to defaults")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontWeightMedium
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("Restore appearance, editing, export, language and recovery options to their defaults.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }
        }

        NekoButton {
            objectName: "settings-reset"
            text: qsTr("Reset to defaults")
            variant: "secondary"
            iconName: "reset"
            enabled: !page.busy
            onClicked: page.resetRequested()
        }
    }
}
