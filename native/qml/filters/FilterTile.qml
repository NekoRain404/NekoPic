pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    FilterTile — one look card with a live preview, label and favourite star.

    The whole card is a single focusable button (objectName filter-<id>); the
    star is a separate focusable control layered above it. All chrome uses
    Theme tokens and all animation uses Motion tokens.
*/
Item {
    id: root

    property string presetId: ""
    property string label: ""
    property bool selected: false
    property bool favourite: false
    property bool previewsAvailable: false
    property double previewRevision: 0
    property bool controlsEnabled: true

    signal activated()
    signal favouriteToggled()

    implicitHeight: 64
    implicitWidth: 120

    AbstractButton {
        id: tile
        anchors.fill: parent
        objectName: "filter-" + root.presetId
        text: root.label
        enabled: root.controlsEnabled
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: true
        padding: 0

        Accessible.role: Accessible.Button
        Accessible.name: root.label
        Accessible.description: root.selected ? qsTr("Selected look") : qsTr("Apply look")
        Accessible.pressed: down

        onClicked: root.activated()

        contentItem: ColumnLayout {
            spacing: Theme.spacingXs

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Theme.radiusXs
                color: Theme.surfaceRaised
                clip: true

                Image {
                    id: preview
                    objectName: "filter-preview-" + root.presetId
                    anchors.fill: parent
                    source: root.previewsAvailable
                            ? "image://filterpreview/" + root.presetId + "/" + root.previewRevision
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    visible: status === Image.Ready
                }

                // Quiet fallback so an unbounded or not-yet-ready tile still
                // reads as a look rather than an empty hole.
                Text {
                    anchors.centerIn: parent
                    visible: !preview.visible
                    text: root.presetId === "none" ? qsTr("Original") : qsTr("Preview")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.label
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Theme.fontCaption
                font.weight: root.selected ? Theme.fontWeightDemiBold : Theme.fontWeightRegular
                color: root.selected ? Theme.textPrimary : Theme.textSecondary
            }
        }

        background: Rectangle {
            radius: Theme.radiusSm
            color: root.selected ? Theme.selection
                 : tile.hovered ? Theme.hover : Theme.background
            border.width: root.selected || tile.visualFocus ? Theme.focusRingWidth : Theme.borderWidth
            border.color: root.selected ? Theme.accent
                        : tile.visualFocus ? Theme.focusRing : Theme.border
            Behavior on color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }
    }

    // Star lives above the card so it never steals the card's activation.
    AbstractButton {
        id: favouriteButton
        objectName: "filter-favorite-" + root.presetId
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 2
        width: 20
        height: 20
        enabled: root.presetId !== "none"
        visible: root.presetId !== "none"
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: root.presetId !== "none"

        readonly property bool isFavourite: root.favourite
        text: isFavourite ? "★" : "☆"

        Accessible.role: Accessible.CheckBox
        Accessible.name: isFavourite ? qsTr("Remove %1 from favourites").arg(root.label)
                                     : qsTr("Add %1 to favourites").arg(root.label)
        Accessible.checkable: true
        Accessible.checked: isFavourite

        onClicked: root.favouriteToggled()

        contentItem: Text {
            text: favouriteButton.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Theme.fontSmall
            color: favouriteButton.isFavourite ? Theme.accent
                 : favouriteButton.hovered ? Theme.textPrimary : Theme.textSecondary
        }

        background: Rectangle {
            radius: width / 2
            color: Theme.alpha(Theme.background, 0.82)
            border.width: favouriteButton.visualFocus ? Theme.focusRingWidth : 0
            border.color: Theme.focusRing
        }
    }
}
