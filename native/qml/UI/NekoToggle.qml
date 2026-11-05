import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoToggle — switch with an animated knob and optional trailing label.

    The whole row is the hit target. Knob travel and track colour use the
    fast duration; reduced motion collapses both to an instant state change.
*/
AbstractButton {
    id: root

    property string accessibleName: ""

    readonly property color trackColor: !enabled
                                       ? Theme.hover
                                       : checked ? (hovered ? Theme.accentHover : Theme.accent)
                                       : (hovered ? Theme.hover : Theme.border)

    checkable: true
    implicitWidth: Theme.toggleWidth + (text.length > 0 ? Theme.spacingSm + label.implicitWidth : 0)
    implicitHeight: Theme.toggleHeight
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
    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName.length > 0 ? accessibleName : (text.length > 0 ? text : qsTr("Toggle"))
    Accessible.checkable: true
    Accessible.checked: checked

    contentItem: Item {
        Rectangle {
            id: track
            width: Theme.toggleWidth
            height: Theme.toggleHeight
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.trackColor
            Behavior on color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }

            Rectangle {
                id: knob
                width: Theme.toggleKnobSize
                height: width
                radius: width / 2
                y: (parent.height - height) / 2
                x: root.checked
                   ? parent.width - width - (parent.height - height) / 2
                   : (parent.height - height) / 2
                color: Theme.controlKnob
                border.width: root.checked ? 0 : Theme.borderWidth
                border.color: Theme.border
                scale: root.enabled && root.hovered ? 1.06 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.duration(Motion.fast)
                        easing.type: Motion.decelerateEasing
                    }
                }
                Behavior on x {
                    NumberAnimation {
                        duration: Motion.duration(Motion.fast)
                        easing.type: Motion.emphasizedEasing
                    }
                }
            }
        }

        Text {
            id: label
            visible: root.text.length > 0
            x: track.width + Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.enabled ? Theme.textPrimary : Theme.textTertiary
            font.pixelSize: Theme.fontSmall
            font.weight: Theme.fontWeightMedium
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: height / 2
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.visualFocus && root.enabled
    }
}
