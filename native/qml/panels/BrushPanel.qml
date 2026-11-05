import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"
import "../dialogs"

/*!
    BrushPanel — brush size and ink controls for the brush tool.

    This is the panel surface beside the canvas. It exposes the tool's public
    state so the integrator can bind it directly:

        BrushPanel {
            diameter: brush.diameter
            color: brush.color
            enabled: editor.hasImage && !editor.busy
        }

    Contract:
      • diameter — brush width in image pixels, constrained to 4–512.
      • color    — brush ink; the six swatches and the hex field set it.
      • enabled  — inherited Item property; false locks every control.
      • theme    — the shell token map (panel/text/muted/raised/border/accent).

    The swatch literals are content values (paint colours), not design tokens;
    every other colour comes from Theme or the supplied theme map.

    Test hooks (objectName): brush-diameter, brush-diameter-value,
    brush-color-black, brush-color-white, brush-color-warm-grey,
    brush-color-peach, brush-color-red, brush-color-blue, brush-hex-field,
    brush-reset, brush-hint.

    The visible surface is `panelBackground`. The root stays an Item so the
    public `color` property can mean brush ink; a Rectangle root already owns
    a `color` property of its own.
*/
Item {
    id: root

    property var theme: ({ panel: Theme.panel, background: Theme.background,
                           raised: Theme.surfaceRaised, hover: Theme.hover,
                           border: Theme.border, text: Theme.textPrimary,
                           muted: Theme.textSecondary, accent: Theme.accent })
    /*! Brush diameter in image pixels. */
    property real diameter: 24
    /*! Brush ink. Defaults to black, matching the controller fallback. */
    property color color: root.blackColor

    readonly property real minDiameter: 4
    readonly property real maxDiameter: 512
    readonly property real defaultDiameter: 24

    /* Sample colours are content values, not design tokens. */
    readonly property color whiteColor: "#ffffff"
    readonly property color blackColor: "#000000"
    readonly property color warmGreyColor: "#8b8780"
    readonly property color peachColor: Theme.accent
    readonly property color redColor: "#c0504d"
    readonly property color blueColor: "#4a6fa5"

    readonly property string hexText: hexFor(color)

    implicitWidth: 292
    implicitHeight: content.implicitHeight + 2 * Theme.spacing2xl

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Brush settings")
    Accessible.description: qsTr("Choose the brush diameter and colour before painting on the image.")

    /*! "#RRGGBB" for a colour. */
    function hexFor(value) {
        const pair = function(channel) {
            const v = Math.round(Math.max(0, Math.min(1, channel)) * 255)
            return (v < 16 ? "0" : "") + v.toString(16)
        }
        return "#" + pair(value.r) + pair(value.g) + pair(value.b)
    }

    /*! Accepts #RGB / #RRGGBB (leading # optional); returns "" when invalid. */
    function normalizeHex(value) {
        let text = String(value === undefined || value === null ? "" : value)
                .trim().toLowerCase()
        if (text.length === 0)
            return ""
        if (text.charAt(0) !== "#")
            text = "#" + text
        if (/^#[0-9a-f]{6}$/.test(text))
            return text
        if (/^#[0-9a-f]{3}$/.test(text)) {
            return "#" + text.charAt(1) + text.charAt(1)
                       + text.charAt(2) + text.charAt(2)
                       + text.charAt(3) + text.charAt(3)
        }
        return ""
    }

    /*! Applies a hex colour; invalid input reverts the field. */
    function applyHex(value) {
        const normalized = normalizeHex(value)
        if (normalized.length === 0) {
            _syncHex()
            return false
        }
        color = normalized
        return true
    }

    /*! Restores the documented defaults. */
    function reset() {
        diameter = defaultDiameter
        color = blackColor
        _syncHex()
    }

    function _syncHex() {
        // Compute from the property directly: when onColorChanged fires, the
        // hexText binding may not have re-evaluated yet.
        if (typeof hexField !== "undefined" && hexField !== null)
            hexField.text = hexFor(color)
    }

    onColorChanged: _syncHex()
    Component.onCompleted: _syncHex()

    Rectangle {
        id: panelBackground
        anchors.fill: parent
        color: root.theme.panel
    }

    Flickable {
        id: scroller
        objectName: "brush-scroll"
        anchors.fill: parent
        anchors.margins: Theme.spacing2xl
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: NekoScrollBar {
            objectName: "brush-scrollbar"
            policy: ScrollBar.AsNeeded
            accessibleName: qsTr("Brush settings scroll")
        }

    ColumnLayout {
        id: content
        width: scroller.width
        spacing: Theme.spacingLg

        Text {
            text: qsTr("BRUSH")
            color: root.theme.muted
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontWeightDemiBold
            font.letterSpacing: Theme.trackingWide
        }

        Text {
            text: qsTr("Freehand brush")
            color: root.theme.text
            font.pixelSize: Theme.fontHeadline
            font.weight: Theme.fontWeightDemiBold
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: qsTr("Diameter")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }
                Item { Layout.fillWidth: true }
                Text {
                    objectName: "brush-diameter-value"
                    text: Math.round(root.diameter) + " px"
                    color: root.theme.text
                    font.pixelSize: Theme.fontCaption
                }
            }

            NekoSlider {
                id: diameterSlider
                objectName: "brush-diameter"
                Layout.fillWidth: true
                from: root.minDiameter
                to: root.maxDiameter
                stepSize: 1
                defaultValue: root.defaultDiameter
                enabled: root.enabled
                accessibleName: qsTr("Brush diameter")
                onPreview: function(value) { root.diameter = Math.round(value) }
                onFinish: function(value) { root.diameter = Math.round(value) }
                Component.onCompleted: value = root.diameter
                Connections {
                    target: root
                    function onDiameterChanged() {
                        if (!diameterSlider.dragging
                                && diameterSlider.value !== root.diameter)
                            diameterSlider.value = root.diameter
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Colour")
                color: root.theme.muted
                font.pixelSize: Theme.fontSmall
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Repeater {
                    model: [
                        { name: "black", label: qsTr("Black"), value: root.blackColor },
                        { name: "white", label: qsTr("White"), value: root.whiteColor },
                        { name: "warm-grey", label: qsTr("Warm grey"), value: root.warmGreyColor },
                        { name: "peach", label: qsTr("Peach"), value: root.peachColor },
                        { name: "red", label: qsTr("Red"), value: root.redColor },
                        { name: "blue", label: qsTr("Blue"), value: root.blueColor }
                    ]

                    delegate: NekoSwatch {
                        required property var modelData

                        objectName: "brush-color-" + modelData.name
                        swatchColor: modelData.value
                        selected: Qt.colorEqual(root.color, modelData.value)
                        enabled: root.enabled
                        opacity: enabled ? 1 : Theme.opacityDisabled
                        accessibleName: qsTr("Brush colour: %1").arg(modelData.label)
                        onClicked: root.color = modelData.value
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Text {
                    text: qsTr("Hex")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }

                TextField {
                    id: hexField
                    objectName: "brush-hex-field"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.controlHeightSm
                    enabled: root.enabled
                    opacity: enabled ? 1 : Theme.opacityDisabled
                    font.pixelSize: Theme.fontSmall
                    color: root.theme.text
                    placeholderText: qsTr("#RRGGBB")
                    placeholderTextColor: root.theme.muted
                    selectionColor: Theme.selection
                    selectedTextColor: root.theme.text
                    maximumLength: 7
                    leftPadding: Theme.spacingSm
                    rightPadding: Theme.spacingSm
                    verticalAlignment: TextInput.AlignVCenter

                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Brush colour hex value")

                    onAccepted: root.applyHex(text)
                    Keys.onReturnPressed: function(event) {
                        root.applyHex(text)
                        event.accepted = true
                    }
                    Keys.onEnterPressed: function(event) {
                        root.applyHex(text)
                        event.accepted = true
                    }

                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: root.theme.raised
                        border.width: Theme.borderWidth
                        border.color: hexField.activeFocus ? Theme.focusRing : root.theme.border
                    }
                }
            }
        }

        NekoButton {
            objectName: "brush-reset"
            Layout.fillWidth: true
            text: qsTr("Reset brush")
            iconName: "rotate"
            variant: "secondary"
            enabled: root.enabled
            onClicked: root.reset()
        }

        Text {
            objectName: "brush-hint"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.theme.muted
            font.pixelSize: Theme.fontSmall
            text: qsTr("Drag on the image to paint. Release commits one stroke. "
                       + "Press Esc to cancel the current stroke.")
        }

        Item { Layout.fillHeight: true }
    }
    }
}
