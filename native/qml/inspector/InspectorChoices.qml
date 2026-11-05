pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    InspectorChoices — compact equal-width radio group.

    Used for curve channels and colour-grading zones. The caller owns the
    current id; each button emits selected(id) and the bound `currentId`
    repaints the selected pill.
*/
Item {
    id: root

    /*! Array of { id, label } objects. */
    property var model: []
    property string currentId: ""
    property bool controlEnabled: true
    /*! Prepended to each button objectName: prefix + id. */
    property string objectNamePrefix: ""
    property string accessibleName: ""

    signal selected(string id)

    implicitHeight: Theme.controlHeightSm

    Accessible.role: Accessible.Grouping
    Accessible.name: accessibleName

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingXs

        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: choice
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                objectName: root.objectNamePrefix + modelData.id
                text: modelData.label
                enabled: root.controlEnabled
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                padding: 0
                opacity: root.controlEnabled ? 1 : Theme.opacityMuted

                Accessible.role: Accessible.RadioButton
                Accessible.name: choice.text
                Accessible.checkable: true
                Accessible.checked: root.currentId === modelData.id

                onClicked: root.selected(modelData.id)

                Keys.onLeftPressed: {
                    if (index > 0)
                        root.selected(root.model[index - 1].id)
                }
                Keys.onRightPressed: {
                    if (index < root.model.length - 1)
                        root.selected(root.model[index + 1].id)
                }

                background: Rectangle {
                    radius: Theme.radiusXs
                    color: root.currentId === choice.modelData.id
                           ? Theme.selection
                           : choice.hovered ? Theme.hover : "transparent"
                    border.width: Theme.borderWidth
                    border.color: root.currentId === choice.modelData.id
                                  ? Theme.accent : Theme.separator
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.duration(Motion.fast)
                            easing.type: Motion.decelerateEasing
                        }
                    }
                }

                contentItem: Text {
                    text: choice.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontCaption
                    font.weight: root.currentId === choice.modelData.id
                                 ? Theme.fontWeightDemiBold : Theme.fontWeightRegular
                    color: root.currentId === choice.modelData.id
                           ? Theme.textPrimary : Theme.textSecondary
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Theme.focusRingOffset
                    radius: Theme.radiusXs + Theme.focusRingOffset
                    color: "transparent"
                    border.width: Theme.focusRingWidth
                    border.color: Theme.focusRing
                    visible: choice.activeFocus
                }
            }
        }
    }
}
