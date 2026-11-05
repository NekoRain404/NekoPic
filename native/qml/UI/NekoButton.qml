import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

/*!
    NekoButton — primary / secondary / ghost action button.

    States: hover lifts the surface, press compresses to 0.98, keyboard focus
    draws a detached ring. All timing comes from Motion and all colour from
    Theme, so these buttons theme-switch and reduce-motion cleanly.
*/
AbstractButton {
    id: root

    /*! Icon shown before the label; empty hides the icon. */
    property string iconName: ""
    /*! "primary" | "secondary" | "ghost". Unknown values fall back to secondary. */
    property string variant: "secondary"
    /*! Icon edge length in pixels. */
    property int iconSize: Theme.iconSizeSm
    /*! Overrides the accessible name when the visible label is not enough. */
    property string accessibleName: ""

    readonly property bool primary: variant === "primary"
    readonly property bool ghost: variant === "ghost"
    readonly property color ink: !enabled ? Theme.textTertiary
                              : primary ? Theme.accentInk
                              : ghost ? (hovered ? Theme.textPrimary : Theme.textSecondary)
                              : Theme.textPrimary
    readonly property color fill: primary
                                  ? (down ? Theme.accentPressed : hovered ? Theme.accentHover : Theme.accent)
                                  : ghost
                                    ? (down ? Theme.alpha(Theme.pressed, 0.9)
                                            : hovered ? Theme.hover : "transparent")
                                    : (down ? Theme.pressed : hovered ? Theme.hover : Theme.surfaceRaised)

    implicitHeight: Theme.controlHeight
    implicitWidth: Math.max(Theme.controlHeight, contentRow.implicitWidth + leftPadding + rightPadding)
    leftPadding: ghost ? Theme.spacingSm : Theme.spacingMd
    rightPadding: ghost ? Theme.spacingSm : Theme.spacingMd
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    opacity: enabled ? 1 : Theme.opacityDisabled
    scale: down && enabled ? 0.98 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName.length > 0 ? accessibleName : text
    Accessible.description: root.iconName

    background: Rectangle {
        radius: Theme.radiusSm
        color: root.fill
        border.width: root.variant === "secondary" ? Theme.borderWidth : 0
        border.color: Theme.border
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    contentItem: RowLayout {
        id: contentRow
        spacing: Theme.spacingSm

        NekoIcon {
            visible: root.iconName.length > 0
            name: root.iconName
            color: root.ink
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: root.text.length > 0
            text: root.text
            color: root.ink
            font.pixelSize: Theme.fontSmall
            font.weight: root.primary ? Theme.fontWeightDemiBold : Theme.fontWeightMedium
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Keyboard-only focus ring, drawn outside the control's bounds.
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
