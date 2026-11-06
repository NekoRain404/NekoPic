import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoMenu — the shared popup surface for menu bar menus and submenus.

    A soft rounded raised panel with a hairline border and gentle elevation,
    padded rows with consistent spacing, and NekoMenuItem as the implicit
    delegate for nested Menu/Action entries. Declared NekoMenuItem children
    keep their action, checked, enabled and triggered behaviour unchanged.
*/
Menu {
    id: root

    /*! Minimum surface width, so short menus do not look cramped. */
    property int minWidth: 200
    /*! Vertical gap between rows, including separators. */
    property int itemSpacing: 2
    /*! Optional accessible name for the popup. */
    property string accessibleName: ""

    readonly property real widestItemWidth: {
        let widest = 0
        for (let i = 0; i < root.count; ++i) {
            const entry = root.itemAt(i)
            if (entry)
                widest = Math.max(widest, entry.implicitWidth)
        }
        return widest
    }

    padding: Theme.spacingXs
    margins: 0
    overlap: 1
    delegate: NekoMenuItem {}

    implicitWidth: Math.max(root.minWidth,
                            root.widestItemWidth + leftPadding + rightPadding)
    implicitHeight: contentItem
                    ? contentItem.implicitHeight + topPadding + bottomPadding
                    : 0

    background: NekoPanel {
        objectName: "neko-menu-surface"
        elevation: NekoPanel.Medium
        radius: Theme.radiusMd
        backgroundColor: Theme.surfaceRaised
        borderColor: Theme.border
        padding: 0
    }

    contentItem: ListView {
        id: menuList

        objectName: "neko-menu-content"
        implicitHeight: contentHeight
        model: root.contentModel
        spacing: root.itemSpacing
        currentIndex: root.currentIndex
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: Window.window
                     ? contentHeight + root.topPadding + root.bottomPadding > root.height
                     : false

        Accessible.role: Accessible.PopupMenu
        Accessible.name: root.accessibleName

        ScrollBar.vertical: NekoScrollBar {
            objectName: "neko-menu-scroll"
            policy: ScrollBar.AsNeeded
            // Guard against floating-point size 0.9999 showing a bar when the
            // menu already fits exactly.
            visible: size < 0.999
        }
    }
}
