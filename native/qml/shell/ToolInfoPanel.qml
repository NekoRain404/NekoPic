import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    ToolInfoPanel — the right-hand function area for tools that have no
    adjustable parameters of their own (Pan and Eyedropper).

    It keeps the side area present and at the same width as the other tool
    panels, so selecting a different tool never reflows the canvas.
*/
Rectangle {
    id: page

    property string title: ""
    property string hint: ""
    property string iconName: ""
    property string shortcut: ""
    property string shortcutLabel: ""

    Layout.fillHeight: true
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 23
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            NekoIcon {
                Layout.alignment: Qt.AlignVCenter
                width: 20
                height: 20
                name: page.iconName
                color: Theme.textPrimary
            }
            Label {
                Layout.fillWidth: true
                text: page.title
                color: Theme.textPrimary
                font.pixelSize: 19
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: page.hint
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle {
                implicitWidth: 26
                implicitHeight: 22
                radius: Theme.radiusSm
                color: Theme.surfaceRaised
                border.width: Theme.borderWidth
                border.color: Theme.border

                Label {
                    anchors.centerIn: parent
                    text: page.shortcut
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.fontWeightMedium
                }
            }
            Label {
                Layout.fillWidth: true
                text: page.shortcutLabel
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                elide: Text.ElideRight
            }
        }
    }
}
