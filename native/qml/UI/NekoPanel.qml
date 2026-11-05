import QtQuick
import "."

/*!
    NekoPanel — the standard raised surface.

    A border-radius, hairline border and optional soft elevation. Children
    declared inside the panel are placed in a padded content area, so panels
    read as containers rather than raw rectangles.
*/
Item {
    id: root

    enum Elevation { Flat, Low, Medium, High }

    property color backgroundColor: Theme.surface
    property color borderColor: Theme.border
    property real radius: Theme.radiusMd
    property int borderWidth: Theme.borderWidth
    property int elevation: NekoPanel.Low
    /*! Inset around declared children. */
    property real padding: Theme.spacingLg
    property bool padded: true
    property string accessibleName: ""

    readonly property var elevationToken: elevation === NekoPanel.High ? Theme.elevationHigh
                                         : elevation === NekoPanel.Medium ? Theme.elevationMedium
                                         : elevation === NekoPanel.Low ? Theme.elevationLow
                                         : Theme.elevationNone

    implicitWidth: Theme.panelMinWidth
    implicitHeight: Theme.panelMinHeight

    Accessible.role: Accessible.Pane
    Accessible.name: accessibleName

    default property alias contentData: contentItem.data

    // Soft, offset shadow drawn beneath the surface. Rectangle layers keep
    // this visually stable under the software renderer as well.
    Rectangle {
        id: shadow
        anchors.fill: background
        anchors.margins: -root.elevationToken.spread
        anchors.topMargin: -root.elevationToken.spread + root.elevationToken.offsetY
        radius: root.radius + root.elevationToken.spread
        color: Theme.shadowColor
        opacity: root.elevationToken.opacity
        visible: root.elevation !== NekoPanel.Flat
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: root.radius
        color: root.backgroundColor
        border.width: root.borderWidth
        border.color: root.borderColor
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

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.padded ? root.padding : 0
    }
}
