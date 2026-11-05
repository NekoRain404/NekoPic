import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoIconButton — square, icon-only button for toolbars and chrome.

    Follows the same focus/press/disabled language as NekoButton. It can be
    checkable for persistent toggles (e.g. a visibility switch).
*/
AbstractButton {
    id: root

    property string iconName: ""
    property int iconSize: Theme.iconSize
    property int buttonSize: Theme.controlHeight
    property string accessibleName: ""

    readonly property color ink: !enabled ? Theme.textTertiary
                              : checked ? Theme.accent
                              : hovered ? Theme.textPrimary
                              : Theme.textSecondary
    readonly property color fill: checked
                                  ? Theme.selection
                                  : down ? Theme.pressed
                                  : hovered ? Theme.hover : "transparent"

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    opacity: enabled ? 1 : Theme.opacityDisabled
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }
    scale: down && enabled ? 0.96 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName.length > 0 ? accessibleName : (iconName.length > 0 ? iconName : qsTr("Action"))
    Accessible.checkable: checkable
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
    }

    contentItem: Item {
        NekoIcon {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            name: root.iconName
            color: root.ink
        }
    }

    NekoToolTip {
        visible: root.hovered && root.enabled && root.text.length === 0
        text: root.accessibleName.length > 0 ? root.accessibleName : root.iconName
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
