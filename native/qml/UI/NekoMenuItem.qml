import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

/*!
    NekoMenuItem — a themed menu row for NekoMenu and menu bar popups.

    Extends MenuItem, so action bindings, text, checkable/checked state,
    enabled logic, shortcuts, triggered() and objectName all keep working.
    The row is 30 px tall, with a check gutter, primary label, right-aligned
    shortcut hint and a submenu chevron. Hover and keyboard highlight share
    the same soft surface, and every colour comes from Theme.
*/
MenuItem {
    id: root

    /*! Explicit shortcut label; overrides the bound Action's shortcut. */
    property string shortcut: ""
    /*! Optional accessible name when the visible label is not enough. */
    property string accessibleName: ""
    /*! Row height; 30 px keeps menus compact but comfortable. */
    property int rowHeight: 30
    /*! Minimum row width before the menu grows to fit the widest label. */
    property int minWidth: 196

    readonly property bool hasSubMenu: subMenu !== null
    readonly property string effectiveShortcut: {
        if (root.shortcut.length > 0)
            return root.shortcut
        if (!root.action)
            return ""
        const sequence = root.action.shortcut
        return sequence !== undefined && sequence !== null ? sequence.toString() : ""
    }
    readonly property color labelColor: !root.enabled ? Theme.textTertiary
                                      : Theme.textPrimary
    readonly property color hintColor: !root.enabled ? Theme.textTertiary
                                     : Theme.textSecondary

    objectName: "neko-menu-item"
    implicitWidth: Math.max(root.minWidth,
                            contentRow.implicitWidth + leftPadding + rightPadding)
    implicitHeight: root.rowHeight
    leftPadding: Theme.spacingMd
    rightPadding: Theme.spacingMd
    topPadding: 0
    bottomPadding: 0
    spacing: Theme.spacingSm
    hoverEnabled: true
    // The custom contentItem owns the checkmark and chevron; clear the style
    // defaults so the native glyphs never appear beside ours.
    indicator: Item {}
    arrow: Item {}

    opacity: enabled ? 1.0 : Theme.opacityMuted
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    Accessible.role: Accessible.MenuItem
    Accessible.name: accessibleName.length > 0 ? accessibleName : text
    Accessible.checkable: checkable
    Accessible.checked: checked

    background: Rectangle {
        radius: Theme.radiusSm
        color: !root.enabled ? "transparent"
             : root.down ? Theme.pressed
             : root.highlighted || root.hovered ? Theme.hover
             : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    contentItem: RowLayout {
        id: contentRow
        objectName: "neko-menu-item-content"
        spacing: Theme.spacingSm

        // Fixed check gutter: labels stay aligned whether or not any sibling
        // is checkable.
        Item {
            Layout.preferredWidth: Theme.iconSizeSm
            Layout.preferredHeight: Theme.iconSizeSm
            Layout.alignment: Qt.AlignVCenter

            NekoIcon {
                objectName: "neko-menu-item-check"
                anchors.centerIn: parent
                width: Theme.iconSizeSm
                height: Theme.iconSizeSm
                name: "check"
                color: root.enabled ? Theme.accent : Theme.textTertiary
                visible: root.checkable && root.checked
            }
        }

        Text {
            objectName: "neko-menu-item-label"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.text
            color: root.labelColor
            font.pixelSize: Theme.fontSmall
            font.weight: Theme.fontWeightRegular
            elide: Text.ElideRight
            maximumLineCount: 1
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            objectName: "neko-menu-item-shortcut"
            Layout.alignment: Qt.AlignVCenter
            visible: root.effectiveShortcut.length > 0
            text: root.effectiveShortcut
            color: root.hintColor
            font.pixelSize: Theme.fontCaption
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }

        // Fixed arrow gutter keeps shortcut labels flush across all rows.
        Item {
            Layout.preferredWidth: Theme.iconSizeSm
            Layout.preferredHeight: Theme.iconSizeSm
            Layout.alignment: Qt.AlignVCenter

            NekoIcon {
                objectName: "neko-menu-item-arrow"
                anchors.centerIn: parent
                width: Theme.iconSizeSm - 2
                height: Theme.iconSizeSm - 2
                name: "chevronRight"
                color: root.hintColor
                visible: root.hasSubMenu
            }
        }
    }
}
