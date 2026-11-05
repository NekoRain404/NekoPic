pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../UI"

/*!
    FilterCategoryChip — compact toggle chip for the Filters workspace.

    Selection is owned by the caller through `selected`; activation emits
    `activated()`. Colour, radius and motion all come from Theme/Motion.
*/
AbstractButton {
    id: root

    property bool selected: false
    property string chipId: ""

    implicitHeight: Theme.controlHeightSm
    implicitWidth: label.implicitWidth + Theme.spacingMd * 2
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    padding: 0

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.checkable: true
    Accessible.checked: root.selected

    opacity: enabled ? 1 : Theme.opacityDisabled
    scale: down ? 0.96 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    background: Rectangle {
        radius: Theme.radiusPill
        color: root.selected ? Theme.selection
             : root.hovered ? Theme.hover
             : "transparent"
        border.width: root.selected ? Theme.borderWidth : 0
        border.color: root.selected ? Theme.accent : "transparent"
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

    contentItem: Text {
        id: label
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pixelSize: Theme.fontCaption
        font.weight: root.selected ? Theme.fontWeightDemiBold : Theme.fontWeightRegular
        color: root.selected ? Theme.textPrimary : Theme.textSecondary
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusPill
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.visualFocus && root.enabled
    }
}
