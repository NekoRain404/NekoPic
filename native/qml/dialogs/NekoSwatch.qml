import QtQuick
import QtQuick.Controls
import "../UI"

/*!
    NekoSwatch — selectable colour tile used by the export/canvas dialogs.

    A checkerboard presentation marks transparency. Selection is expressed
    with a check glyph and an accent border. Keyboard focus uses the shared
    focus ring, and the control reports radio-button semantics.
*/
AbstractButton {
    id: root

    property color swatchColor: "#ffffff"
    property bool selected: false
    property bool showChecker: false
    property string accessibleName: ""

    implicitWidth: Theme.controlHeight
    implicitHeight: Theme.controlHeight
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    readonly property color checkInk: root.showChecker ? Theme.textPrimary
                                                       : Theme.contrastColor(root.swatchColor)

    Accessible.role: Accessible.RadioButton
    Accessible.name: accessibleName
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.focusable: true
    Accessible.focused: activeFocus

    background: Rectangle {
        radius: Theme.radiusSm
        color: root.showChecker ? Theme.surfaceRaised : root.swatchColor
        border.width: root.selected ? Theme.borderWidth * 2 : Theme.borderWidth
        border.color: root.selected ? Theme.accent
                                    : root.hovered ? Theme.textSecondary : Theme.border
    }

    contentItem: Item {
        Canvas {
            id: checker
            anchors.fill: parent
            anchors.margins: Theme.spacingXs
            visible: root.showChecker

            onVisibleChanged: if (visible) requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const context = getContext("2d")
                context.reset()
                const tile = 5
                for (let y = 0; y < height; y += tile) {
                    for (let x = 0; x < width; x += tile) {
                        context.fillStyle = ((x / tile + y / tile) % 2 === 0)
                                ? Theme.alpha(Theme.textTertiary, 0.35)
                                : Theme.alpha(Theme.textTertiary, 0.12)
                        context.fillRect(x, y, tile, tile)
                    }
                }
            }
        }

        NekoIcon {
            anchors.centerIn: parent
            width: Theme.iconSizeSm
            height: Theme.iconSizeSm
            name: "check"
            visible: root.selected
            color: root.checkInk
        }
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
