import QtQuick
import QtQuick.Layouts
import "."

/*!
    NekoSectionHeader — eyebrow/title row with optional trailing metadata and
    a hairline divider. Used to open sections in the inspector and panels.
*/
Item {
    id: root

    property string text: ""
    property string meta: ""
    /*! Small, tracked, uppercase label style (section eyebrow). */
    property bool eyebrow: false
    property bool showDivider: false

    implicitWidth: Theme.controlMinWidth
    implicitHeight: column.implicitHeight

    Accessible.role: Accessible.Heading
    Accessible.name: text

    Column {
        id: column
        width: parent.width
        spacing: root.showDivider ? Theme.spacingSm : 0

        RowLayout {
            width: parent.width
            spacing: Theme.spacingSm

            Text {
                Layout.fillWidth: true
                text: root.text
                color: root.eyebrow ? Theme.textSecondary : Theme.textPrimary
                font.pixelSize: root.eyebrow ? Theme.fontCaption : Theme.fontSmall
                font.weight: root.eyebrow ? Theme.fontWeightDemiBold : Theme.fontWeightMedium
                font.letterSpacing: root.eyebrow ? Theme.trackingWide : 0
                font.capitalization: root.eyebrow ? Font.AllUppercase : Font.MixedCase
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                visible: root.meta.length > 0
                text: root.meta
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            visible: root.showDivider
            width: parent.width
            height: Theme.borderWidth
            color: Theme.separator
        }
    }
}
