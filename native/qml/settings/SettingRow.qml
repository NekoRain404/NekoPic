import QtQuick
import QtQuick.Layouts
import "../UI"

/*!
    SettingRow — label and explanatory hint on the left, a single control on
    the right.

    The control is the default property so settings pages stay declarative.
*/
RowLayout {
    id: row
    property string label: ""
    property string hint: ""
    default property alias controlData: controlHost.data

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Text {
            Layout.fillWidth: true
            text: row.label
            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontWeightMedium
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            text: row.hint
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: controlHost
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
