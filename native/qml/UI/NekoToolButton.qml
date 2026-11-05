import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoToolButton — tool-rail entry with icon, caption and a checked marker.

    Matches the H5 rail (52 px squares, 2 px accent indicator) while using
    the design system's tinted selection surface instead of an ad-hoc alpha.
*/
AbstractButton {
    id: root

    property string iconName: ""
    property string accessibleName: ""

    readonly property color ink: !enabled ? Theme.textTertiary
                              : checked ? Theme.accent
                              : hovered ? Theme.textPrimary
                              : Theme.textSecondary
    readonly property color fill: checked
                                  ? Theme.selection
                                  : down ? Theme.pressed
                                  : hovered ? Theme.hover : "transparent"

    checkable: true
    implicitWidth: Theme.toolButtonWidth
    implicitHeight: Theme.toolButtonHeight
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    opacity: enabled ? 1 : Theme.opacityDisabled
    scale: down && enabled ? 0.98 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName.length > 0 ? accessibleName : text
    Accessible.checkable: true
    Accessible.checked: checked

    background: Rectangle {
        radius: Theme.radiusSm
        color: root.fill
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }

        Rectangle {
            visible: root.checked
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.indicatorWidth
            height: Theme.indicatorHeight
            radius: width / 2
            color: Theme.accent
        }
    }

    contentItem: Item {
        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingXs

            NekoIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.iconSize
                height: Theme.iconSize
                name: root.iconName
                color: root.ink
            }

            Text {
                visible: root.text.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.text
                color: root.ink
                font.pixelSize: Theme.fontCaption
                font.weight: root.checked ? Theme.fontWeightMedium : Theme.fontWeightRegular
            }
        }
    }

    NekoToolTip {
        visible: root.hovered && root.enabled
        text: root.accessibleName.length > 0 ? root.accessibleName : root.text
        accessibleName: root.Accessible.name
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusSm + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.visualFocus && root.enabled
    }
}
