import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoMenuSeparator — a hairline rule between menu groups.

    Uses Theme.separator and keeps a 1 px line with symmetric vertical
    breathing room. It stays non-interactive, matching MenuSeparator.
*/
MenuSeparator {
    id: root

    /*! Total row height, including vertical breathing room. */
    property int rowHeight: 9

    objectName: "neko-menu-separator"
    implicitWidth: 1
    implicitHeight: root.rowHeight
    leftPadding: Theme.spacingMd
    rightPadding: Theme.spacingMd
    topPadding: (root.rowHeight - Theme.borderWidth) / 2
    bottomPadding: topPadding

    contentItem: Item {
        objectName: "neko-menu-separator-line"
        implicitWidth: 1
        implicitHeight: Theme.borderWidth

        Rectangle {
            objectName: "neko-menu-separator-rule"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.borderWidth
            color: Theme.separator
        }
    }
}
