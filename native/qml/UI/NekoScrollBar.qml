import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoScrollBar — thin, quiet scrollbar used in flickables and panels.

    Stays muted until the view is active or hovered, and draws a focus ring
    when reached by keyboard.
*/
ScrollBar {
    id: root

    property string accessibleName: ""

    orientation: Qt.Vertical
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    padding: 0

    implicitWidth: root.orientation === Qt.Vertical ? Theme.scrollBarThickness : Theme.controlMinWidth
    implicitHeight: root.orientation === Qt.Horizontal ? Theme.scrollBarThickness : Theme.controlMinWidth

    Accessible.role: Accessible.ScrollBar
    Accessible.name: accessibleName.length > 0
                     ? accessibleName
                     : (root.orientation === Qt.Vertical ? qsTr("Vertical scroll") : qsTr("Horizontal scroll"))
    Accessible.focusable: true
    Accessible.focused: root.activeFocus

    contentItem: Rectangle {
        implicitWidth: Theme.scrollBarThickness
        implicitHeight: Theme.scrollBarThickness
        radius: Math.min(width, height) / 2
        color: root.pressed ? Theme.textPrimary
             : root.hovered ? Theme.textSecondary
             : Theme.textTertiary
        opacity: root.enabled ? (root.active || root.hovered ? 1 : Theme.opacityMuted) : Theme.opacityDisabled

        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    background: Rectangle {
        implicitWidth: Theme.scrollBarThickness
        implicitHeight: Theme.scrollBarThickness
        radius: Math.min(width, height) / 2
        color: "transparent"
        border.width: root.visualFocus ? Theme.focusRingWidth : 0
        border.color: Theme.focusRing
    }
}
