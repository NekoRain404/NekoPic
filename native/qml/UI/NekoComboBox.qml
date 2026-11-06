import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

/*!
    NekoComboBox — themed single-choice field with a menu-style popup.

    The closed field uses the shared control height, surface and focus ring.
    The popup reuses NekoMenu's surface language: rounded raised panel,
    hairline border, 30 px rows with hover/highlight states and a checkmark
    for the selected entry. Native ComboBox keyboard navigation (Up/Down,
    Enter, Escape) is inherited unchanged.
*/
ComboBox {
    id: root

    /*! Accessible name; falls back to the selected text. */
    property string accessibleName: ""
    /*! Optional longer accessible description. */
    property string accessibleDescription: ""
    /*! Row height shared with NekoMenuItem. */
    property int rowHeight: 30
    /*! Maximum popup height before the list scrolls. */
    property int maxPopupHeight: 300

    implicitHeight: Theme.controlHeight
    implicitWidth: Math.max(Theme.controlMinWidth,
                            contentItem ? contentItem.implicitWidth + leftPadding + rightPadding : 0)
    leftPadding: Theme.spacingMd
    rightPadding: Theme.spacingMd + Theme.iconSizeSm + Theme.spacingSm
    spacing: Theme.spacingSm
    font.pixelSize: Theme.fontSmall
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    Accessible.role: Accessible.ComboBox
    Accessible.name: accessibleName.length > 0 ? accessibleName : displayText
    Accessible.description: accessibleDescription
    Accessible.expanded: popup.visible

    contentItem: Text {
        objectName: "neko-combo-content"
        leftPadding: 0
        rightPadding: 0
        text: root.displayText
        color: root.enabled ? Theme.textPrimary : Theme.textTertiary
        font: root.font
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
    }

    indicator: NekoIcon {
        objectName: "neko-combo-chevron"
        x: root.width - width - Theme.spacingMd
        y: (root.height - height) / 2
        width: Theme.iconSizeSm
        height: Theme.iconSizeSm
        name: "chevronDown"
        color: root.enabled ? Theme.textSecondary : Theme.textTertiary
    }

    background: Rectangle {
        objectName: "neko-combo-surface"
        radius: Theme.radiusSm
        color: !root.enabled ? Theme.background
             : root.down ? Theme.pressed
             : root.hovered ? Theme.hover
             : Theme.background
        border.width: root.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
        border.color: !root.enabled ? Theme.border
                    : root.activeFocus ? Theme.accent
                    : Theme.border

        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    delegate: ItemDelegate {
        id: option

        required property int index

        width: ListView.view ? ListView.view.width : 0
        implicitHeight: root.rowHeight
        padding: 0
        hoverEnabled: true
        highlighted: root.highlightedIndex === option.index
        text: root.textAt(option.index)

        Accessible.role: Accessible.MenuItem
        Accessible.name: option.text
        Accessible.checkable: true
        Accessible.checked: root.currentIndex === option.index

        background: Rectangle {
            radius: Theme.radiusSm
            color: option.down ? Theme.pressed
                 : option.highlighted || option.hovered ? Theme.hover
                 : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }

        contentItem: RowLayout {
            spacing: Theme.spacingSm

            Item {
                Layout.preferredWidth: Theme.iconSizeSm
                Layout.preferredHeight: Theme.iconSizeSm
                Layout.leftMargin: Theme.spacingMd
                Layout.alignment: Qt.AlignVCenter

                NekoIcon {
                    objectName: "neko-combo-check"
                    anchors.centerIn: parent
                    width: Theme.iconSizeSm
                    height: Theme.iconSizeSm
                    name: "check"
                    color: Theme.accent
                    visible: root.currentIndex === option.index
                }
            }

            Text {
                objectName: "neko-combo-option-label"
                Layout.fillWidth: true
                Layout.rightMargin: Theme.spacingMd
                Layout.alignment: Qt.AlignVCenter
                text: option.text
                color: option.enabled ? Theme.textPrimary : Theme.textTertiary
                font.pixelSize: Theme.fontSmall
                font.weight: root.currentIndex === option.index
                             ? Theme.fontWeightMedium : Theme.fontWeightRegular
                elide: Text.ElideRight
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    popup: Popup {
        id: popup

        objectName: "neko-combo-popup"
        x: 0
        y: root.height + Theme.spacingXs
        width: root.width
        topPadding: Theme.spacingXs
        bottomPadding: Theme.spacingXs
        leftPadding: Theme.spacingXs
        rightPadding: Theme.spacingXs
        height: Math.min(contentItem ? contentItem.implicitHeight + topPadding + bottomPadding
                                     : 0,
                         root.maxPopupHeight)

        background: NekoPanel {
            objectName: "neko-combo-popup-surface"
            elevation: NekoPanel.Medium
            radius: Theme.radiusMd
            backgroundColor: Theme.surfaceRaised
            borderColor: Theme.border
            padding: 0
        }

        contentItem: ListView {
            id: optionList

            objectName: "neko-combo-list"
            implicitHeight: contentHeight
            clip: true
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: NekoScrollBar {
                objectName: "neko-combo-scroll"
                policy: ScrollBar.AsNeeded
                visible: size < 0.999
            }
        }
    }
}
