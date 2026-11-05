import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoToolTip — quiet, theme-aware tooltip for icon-only controls.

    Popup based, so it never participates in layout. The caller owns when it
    is visible; hover-delay defaults suit desktop chrome (about half a second).
*/
ToolTip {
    id: root

    property string accessibleName: ""

    delay: 500
    timeout: 3200
    padding: Theme.spacingXs + 2

    contentItem: Text {
        text: root.text
        color: Theme.textPrimary
        font.pixelSize: Theme.fontCaption
        font.weight: Theme.fontWeightMedium
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: Theme.radiusXs
        color: Theme.surfaceRaised
        border.width: Theme.borderWidth
        border.color: Theme.border
    }

}
