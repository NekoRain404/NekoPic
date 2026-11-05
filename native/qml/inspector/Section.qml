pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    Section — compact titled group with a hairline rule.

    Sections carry the visual rhythm of the five colour sub-tabs: a quiet
    caption header, a separator and tightly spaced controls.
*/
ColumnLayout {
    id: root

    property string title: ""
    property string caption: ""
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: Theme.spacingSm

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: root.title
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontWeightDemiBold
            font.letterSpacing: Theme.trackingWide
        }
        Item { Layout.fillWidth: true }
        Label {
            visible: root.caption.length > 0
            text: root.caption
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.borderWidth
        color: Theme.separator
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: Theme.spacingSm
    }
}
