import QtQuick
import "."

/*!
    NekoCard — a panel that can act as a large clickable target.

    Used for filter previews, presets and setting tiles. When interactive it
    takes keyboard focus, responds to Space/Return and compresses slightly on
    press. Content should be non-interactive; the card owns the hit target.
*/
Item {
    id: root

    signal clicked()

    property bool interactive: true
    property string accessibleName: ""
    property int elevation: NekoPanel.Low
    property real padding: Theme.spacingMd

    readonly property bool hovered: root.interactive && mouseArea.containsMouse
    readonly property bool pressed: root.interactive && mouseArea.pressed

    implicitWidth: Theme.cardMinWidth
    implicitHeight: Theme.panelMinHeight
    activeFocusOnTab: root.interactive

    Accessible.role: root.interactive ? Accessible.Button : Accessible.Pane
    Accessible.name: root.accessibleName
    Accessible.focusable: root.interactive
    Accessible.focused: root.activeFocus
    Accessible.pressed: root.pressed

    default property alias contentData: contentItem.data

    scale: root.pressed ? 0.99 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    Keys.onSpacePressed: {
        if (root.interactive)
            root.clicked()
    }
    Keys.onReturnPressed: {
        if (root.interactive)
            root.clicked()
    }

    NekoPanel {
        anchors.fill: parent
        elevation: root.hovered ? NekoPanel.Medium : root.elevation
        backgroundColor: root.hovered ? Theme.surfaceRaised : Theme.surface
        borderColor: root.activeFocus ? Theme.accent : Theme.border
        radius: Theme.radiusMd
        padding: 0
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.padding
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusMd + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.interactive
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        acceptedButtons: Qt.LeftButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.forceActiveFocus()
            root.clicked()
        }
    }
}
