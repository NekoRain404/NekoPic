pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "."

/*!
    NekoSegmentedControl — equal-width segments with an animated pill.

    The pill slides on x/width with an emphasized decelerating curve; text
    colours cross-fade quickly. Arrow keys move selection when the control
    itself has keyboard focus; each segment remains independently clickable.
*/
Item {
    id: root

    /*! Array of strings or objects with a `text`/`label` field. */
    property var model: []
    property int currentIndex: 0
    property string accessibleName: ""

    readonly property int count: model ? model.length : 0
    readonly property int selectedIndex: count > 0 ? Math.max(0, Math.min(currentIndex, count - 1)) : 0
    readonly property real segmentWidth: count > 0 ? (width - Theme.segmentInset * 2) / count : 0

    signal activated(int index)
    signal selectionChanged(int index)

    implicitWidth: Math.max(Theme.controlMinWidth, count * Theme.segmentMinWidth)
    implicitHeight: Theme.controlHeight
    activeFocusOnTab: true
    focus: false

    Accessible.role: Accessible.PageTabList
    Accessible.name: accessibleName.length > 0 ? accessibleName : qsTr("Sections")

    function itemText(item) {
        if (item === undefined || item === null)
            return ""
        if (typeof item === "string")
            return item
        if (item.text !== undefined)
            return item.text
        if (item.label !== undefined)
            return item.label
        return ""
    }

    function activate(index) {
        if (index < 0 || index >= count)
            return
        root.currentIndex = index
        root.activated(index)
    }

    function step(delta) {
        if (count === 0)
            return
        const next = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
        if (next !== root.selectedIndex)
            root.activate(next)
    }

    onCurrentIndexChanged: root.selectionChanged(root.currentIndex)

    Keys.onLeftPressed: root.step(-1)
    Keys.onRightPressed: root.step(1)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) {
            root.step(-root.count)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            root.step(root.count)
            event.accepted = true
        }
    }

    // Container
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.background
        border.width: Theme.borderWidth
        border.color: Theme.border
    }

    // Animated selection pill, behind the segment labels.
    Rectangle {
        visible: root.count > 0
        x: Theme.segmentInset + root.selectedIndex * root.segmentWidth
        y: Theme.segmentInset
        width: root.segmentWidth
        height: root.height - Theme.segmentInset * 2
        radius: Theme.radiusXs
        color: Theme.surfaceRaised
        border.width: Theme.borderWidth
        border.color: Theme.border
        z: 1

        Behavior on x {
            NumberAnimation {
                duration: Motion.duration(Motion.standard)
                easing.type: Motion.emphasizedEasing
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Motion.duration(Motion.standard)
                easing.type: Motion.emphasizedEasing
            }
        }
    }

    Row {
        id: segments
        anchors.fill: parent
        anchors.margins: Theme.segmentInset
        z: 2

        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: segment
                required property var modelData
                required property int index

                width: root.count > 0 ? segments.width / root.count : 0
                height: segments.height
                objectName: "segment-" + index
                padding: 0
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                activeFocusOnTab: false
                text: root.itemText(modelData)

                onClicked: {
                    root.forceActiveFocus()
                    root.activate(index)
                }

                Accessible.role: Accessible.RadioButton
                Accessible.name: segment.text
                Accessible.checkable: true
                Accessible.checked: index === root.selectedIndex

                background: Rectangle {
                    radius: Theme.radiusXs
                    color: segment.down ? Theme.alpha(Theme.pressed, 0.9)
                         : segment.hovered && segment.index !== root.selectedIndex ? Theme.hover
                         : "transparent"
                }

                contentItem: Text {
                    text: segment.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Theme.fontSmall
                    font.weight: segment.index === root.selectedIndex
                                 ? Theme.fontWeightMedium : Theme.fontWeightRegular
                    color: segment.index === root.selectedIndex ? Theme.textPrimary : Theme.textSecondary
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.duration(Motion.fast)
                            easing.type: Motion.decelerateEasing
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusSm + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.enabled
        z: 3
    }
}
