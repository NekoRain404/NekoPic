pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AdjustTabBar — H5-style two-row five-segment sub-tab strip.

    The five Adjust destinations are arranged as three tabs on the first row
    and two on the second, mirroring the H5 inspector's two-row tab strip.
    The strip keeps the same fixed labels as before ("基础", HSL, "曲线",
    "色彩分级", "细节/效果") so the wider 320 px inspector never has to elide
    them to ambiguity.

    Selection is owned by the caller: clicking or using the keyboard emits
    activated(index) and the bound `currentIndex` refreshes the indicator.
*/
Item {
    id: root

    property var model: []
    property int currentIndex: 0

    readonly property int count: model ? model.length : 0

    signal activated(int index)

    implicitHeight: Theme.controlHeightSm * 2 + Theme.segmentInset * 2
                    + Theme.spacingXs
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
            root.activate(count - 1)
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

    GridLayout {
        anchors.fill: parent
        anchors.margins: Theme.segmentInset
        columns: 6
        rowSpacing: Theme.spacingXs
        columnSpacing: Theme.spacingXs

        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: tab
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Theme.controlHeightSm
                Layout.columnSpan: index < 3 ? 2 : 3
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

                    Rectangle {
                        visible: tab.index === root.currentIndex
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: Math.max(0, parent.width - Theme.spacingLg)
                        height: Theme.indicatorWidth
                        radius: height / 2
                        color: Theme.accent
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
