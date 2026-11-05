pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AdjustTabBar — compact five-segment sub-tab strip for the Adjust workspace.

    Selection is owned by the caller: clicking or using the keyboard emits
    activated(index) and the bound `currentIndex` refreshes the indicator. The
    control is intentionally narrow so "色彩分级" and "细节/效果" fit inside
    the 292 px inspector without eliding to ambiguity.
*/
Item {
    id: root

    property var model: []
    property int currentIndex: 0

    readonly property int count: model ? model.length : 0

    signal activated(int index)

    implicitHeight: Theme.controlHeightSm
    activeFocusOnTab: true

    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Adjustment tabs")

    function activate(index) {
        if (index < 0 || index >= count)
            return
        root.activated(index)
    }

    function step(delta) {
        if (count === 0)
            return
        const next = Math.max(0, Math.min(count - 1, root.currentIndex + delta))
        if (next !== root.currentIndex)
            root.activate(next)
    }

    Keys.onLeftPressed: root.step(-1)
    Keys.onRightPressed: root.step(1)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) {
            root.activate(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            root.activate(root.count - 1)
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.background
        border.width: Theme.borderWidth
        border.color: Theme.separator
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.segmentInset
        spacing: 0

        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: tab
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                objectName: "adjust-subtab-" + index
                enabled: true
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                activeFocusOnTab: false
                padding: 0

                Accessible.role: Accessible.RadioButton
                Accessible.name: tab.text
                Accessible.checkable: true
                Accessible.checked: index === root.currentIndex

                function itemText(item) {
                    if (typeof item === "string")
                        return item
                    if (item && item.text !== undefined)
                        return item.text
                    if (item && item.label !== undefined)
                        return item.label
                    return ""
                }

                text: itemText(modelData)

                onClicked: {
                    root.forceActiveFocus()
                    root.activate(index)
                }

                background: Rectangle {
                    radius: Theme.radiusXs
                    color: tab.index === root.currentIndex
                           ? Theme.selection
                           : tab.hovered ? Theme.hover : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.duration(Motion.fast)
                            easing.type: Motion.decelerateEasing
                        }
                    }
                }

                contentItem: Text {
                    text: tab.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontCaption
                    font.weight: tab.index === root.currentIndex
                                 ? Theme.fontWeightDemiBold : Theme.fontWeightRegular
                    color: tab.index === root.currentIndex
                           ? Theme.textPrimary : Theme.textSecondary
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

    // Selected-segment underline; a quiet native counterpart to the H5 tab bar.
    Rectangle {
        visible: root.count > 0
        width: Math.max(0, (root.width - Theme.segmentInset * 2) / Math.max(root.count, 1) - Theme.spacingSm)
        height: Theme.indicatorWidth
        radius: height / 2
        x: Theme.segmentInset + root.currentIndex * (root.width - Theme.segmentInset * 2)
           / Math.max(root.count, 1) + Theme.spacingXs
        y: root.height - height - Theme.borderWidth
        color: Theme.accent
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

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusSm + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus
    }
}
