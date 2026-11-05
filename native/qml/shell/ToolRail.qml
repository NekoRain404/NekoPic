import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    ToolRail — the fixed tool strip on the left edge of the editor shell.

    The rail is presentation only. It receives the active tool and whether a
    document is loaded, and reports user intent through signals so the shell
    remains the composition root.
*/
Rectangle {
    id: rail

    property string activeTool: "adjust"
    property bool hasImage: false
    property bool busy: false
    property color foregroundColor: "#eeb99a"

    signal toolSelected(string tool)
    signal foregroundColorRequested()

    Layout.fillHeight: true
    Layout.preferredWidth: 74
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: toolScroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: tools.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: NekoScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: tools
                width: parent.width
                y: 10
                spacing: 3

                Repeater {
                    model: [
                        { icon: "select", label: qsTr("Select") }, { icon: "pan", label: qsTr("Pan") },
                        { icon: "adjust", label: qsTr("Adjust") }, { icon: "filters", label: qsTr("Filters") },
                        { icon: "brush", label: qsTr("Brush") }, { icon: "text", label: qsTr("Text") },
                        { icon: "shapes", label: qsTr("Shapes") }, { icon: "mosaic", label: qsTr("Mosaic") },
                        { icon: "eye", label: qsTr("Eyedropper") }, { icon: "crop", label: qsTr("Crop") }
                    ]

                    delegate: NekoToolButton {
                        id: toolButton
                        required property var modelData
                        required property int index
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: index === 2 || index === 4 ? 10 : 0
                        objectName: "tool-" + modelData.icon
                        text: modelData.label
                        iconName: modelData.icon
                        accessibleName: modelData.label
                        readonly property bool available: modelData.icon === "pan" || modelData.icon === "select" || modelData.icon === "adjust" || modelData.icon === "filters" || modelData.icon === "brush" || modelData.icon === "mosaic" || modelData.icon === "text" || modelData.icon === "shapes" || modelData.icon === "eye" || modelData.icon === "crop"
                        enabled: available && !rail.busy && (modelData.icon !== "crop" || rail.hasImage)
                        checked: available && rail.activeTool === modelData.icon
                        onClicked: rail.toolSelected(modelData.icon)
                        ToolTip.visible: hovered
                        ToolTip.text: available ? modelData.label : modelData.label + " · " + qsTr("Coming soon")
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingSm
            Layout.bottomMargin: Theme.spacingMd
            spacing: Theme.spacingXs

            AbstractButton {
                id: foregroundSwatch
                objectName: "foreground-swatch"
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 34
                implicitHeight: 34
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                scale: down ? 0.94 : hovered ? 1.05 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.duration(Motion.fast)
                        easing.type: Motion.decelerateEasing
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Foreground colour")
                Accessible.description: qsTr("Sets the shared ink for the brush, text and shape tools.")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Foreground colour")
                onClicked: rail.foregroundColorRequested()
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: rail.foregroundColor
                    border.width: 3
                    border.color: Theme.panel
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: Theme.radiusSm + 4
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: foregroundSwatch.hovered ? Theme.textSecondary : Theme.border
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Theme.focusRingOffset
                    radius: Theme.radiusSm + Theme.focusRingOffset
                    color: "transparent"
                    border.width: Theme.focusRingWidth
                    border.color: Theme.focusRing
                    visible: foregroundSwatch.visualFocus
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Colour")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontCaption
            }
        }
    }
}
