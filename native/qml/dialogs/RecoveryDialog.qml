import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    RecoveryDialog — startup prompt for a crash-recovery snapshot.

    Purely presentational: Restore/Discard are emitted through NekoDialog's
    accepted()/rejected() so the integrator owns RecoveryStore calls. The
    flattened note is honest about what a PNG snapshot can preserve.
*/
NekoDialog {
    id: root

    property string sourceName: ""
    property string sourcePath: ""
    property string capturedAtText: ""
    property string imageSizeText: ""
    property bool flattened: true

    title: qsTr("Recover unsaved session?")
    description: qsTr("NekoPic closed before your work was saved. A temporary snapshot from the last session is available.")
    acceptText: qsTr("Restore")
    rejectText: qsTr("Discard")
    acceptObjectName: "recovery-restore"
    rejectObjectName: "recovery-discard"
    accessibleName: qsTr("Session recovery")

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            objectName: "recovery-source"
            Layout.fillWidth: true
            text: root.sourceName.length > 0 ? root.sourceName : qsTr("Untitled")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontTitle
            font.weight: Theme.fontWeightDemiBold
            elide: Text.ElideMiddle
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("Recovered file: %1").arg(text)
        }

        Text {
            objectName: "recovery-source-path"
            Layout.fillWidth: true
            visible: root.sourcePath.length > 0
            text: root.sourcePath
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideMiddle
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            objectName: "recovery-captured-at"
            Layout.fillWidth: true
            visible: root.capturedAtText.length > 0
            text: qsTr("Captured %1").arg(root.capturedAtText)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            objectName: "recovery-image-size"
            Layout.fillWidth: true
            visible: root.imageSizeText.length > 0
            text: root.imageSizeText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            objectName: "recovery-flattened-note"
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXs
            visible: root.flattened
            text: qsTr("The snapshot is flattened: adjustments, filters, text and shapes are baked into the pixels and cannot be edited as separate objects.")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }
    }
}
