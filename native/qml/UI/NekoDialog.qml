import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

/*!
    NekoDialog — consistent modal surface with title, description, body and
    a two-button footer.

    Declared children go into the body column. Escape and outside-click close
    by default; the footer buttons emit accepted()/rejected() before closing.
    Sizing adapts to narrow windows while keeping a comfortable max width.
*/
Popup {
    id: root

    property string title: ""
    property string description: ""
    property string acceptText: ""
    property string rejectText: ""
    property string accessibleName: ""
    property bool showCloseButton: true

    signal accepted()
    signal rejected()

    default property alias bodyData: bodyColumn.data

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Theme.spacing2xl

    width: Math.min(Theme.dialogWidth,
                    parent ? Math.max(Theme.controlMinWidth, parent.width - Theme.spacing3xl * 2)
                           : Theme.dialogWidth)
    height: parent && parent.height > 0
            ? Math.min(implicitHeight, parent.height - Theme.spacing2xl)
            : implicitHeight
    implicitHeight: contentColumn.implicitHeight + topPadding + bottomPadding
    transformOrigin: Item.Center

    /*! Decelerating fade + tiny scale keeps the modal from popping in. */
    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: Motion.duration(Motion.standard)
            easing.type: Motion.decelerateEasing
        }
        NumberAnimation {
            property: "scale"
            from: 0.98
            to: 1.0
            duration: Motion.duration(Motion.standard)
            easing.type: Motion.decelerateEasing
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.accelerateEasing
        }
    }

    background: NekoPanel {
        elevation: NekoPanel.High
        radius: Theme.radiusLg
        backgroundColor: Theme.surface
        padding: 0
    }

    // Use the design system's scrim instead of the style's default dim.
    Overlay.modal: Rectangle {
        color: Theme.scrim
    }

    contentItem: ColumnLayout {
        id: contentColumn
        spacing: Theme.spacingLg

        // Popup is not an Item, so accessibility metadata lives on the
        // dialog's content surface.
        Accessible.role: Accessible.Dialog
        Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : root.title
        Accessible.description: root.description

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: root.title.length > 0 || root.showCloseButton

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: Theme.fontTitle
                font.weight: Theme.fontWeightDemiBold
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            NekoIconButton {
                visible: root.showCloseButton
                iconName: "close"
                accessibleName: qsTr("Close dialog")
                onClicked: root.close()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            id: bodyColumn
            Layout.fillWidth: true
            spacing: Theme.spacingMd
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: root.acceptText.length > 0 || root.rejectText.length > 0

            Item { Layout.fillWidth: true }

            NekoButton {
                visible: root.rejectText.length > 0
                text: root.rejectText
                variant: "ghost"
                onClicked: {
                    root.rejected()
                    root.close()
                }
            }

            NekoButton {
                visible: root.acceptText.length > 0
                text: root.acceptText
                variant: "primary"
                onClicked: {
                    root.accepted()
                    root.close()
                }
            }
        }
    }
}
