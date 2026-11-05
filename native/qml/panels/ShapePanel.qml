pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"
import "../dialogs"

/*!
    ShapePanel — properties for the shape tool.

    The panel owns the values bound to ShapeOverlay and to
    DocumentController::addShape:

        editor.addShape(shapePanel.shapeKind, area,
                        shapePanel.filled ? shapePanel.fillColor : "transparent",
                        shapePanel.strokeColor, shapePanel.strokeWidth,
                        shapePanel.cornerRadius)

    The shape selector, fill toggle, fill/stroke swatches and the two sliders
    are all disabled when `enabled` is false (for example while the document
    is busy or no image is open). Fill controls are only meaningful for
    rectangle/ellipse and are disabled for line/arrow; corner radius only
    applies to rectangles.

    Every control carries an objectName for tests and an accessible name.
*/
Rectangle {
    id: root

    /*! Token map supplied by Main; defaults keep the panel standalone. */
    property var theme: ({ panel: Theme.panel, background: Theme.background,
                           raised: Theme.surfaceRaised, hover: Theme.hover,
                           border: Theme.border, text: Theme.textPrimary,
                           muted: Theme.textSecondary, accent: Theme.accent })

    property string shapeKind: "rectangle"
    property bool filled: true
    property real strokeWidth: 4
    property real cornerRadius: 0

    /* Sample colours are content values, not design tokens. */
    readonly property color whiteColor: "#ffffff"
    readonly property color blackColor: "#000000"
    readonly property color warmGreyColor: "#8b8780"
    readonly property color peachColor: Theme.accent
    readonly property color redColor: "#c0504d"
    readonly property color blueColor: "#4a6fa5"

    property color fillColor: root.whiteColor
    property color strokeColor: root.blackColor

    readonly property bool supportsFill: shapeKind === "rectangle" || shapeKind === "ellipse"
    readonly property bool supportsCorner: shapeKind === "rectangle"

    readonly property real minStrokeWidth: 0
    readonly property real maxStrokeWidth: 40
    readonly property real minCornerRadius: 0
    readonly property real maxCornerRadius: 64

    implicitWidth: 292
    color: root.theme.panel

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Shape properties")
    Accessible.description: qsTr("Choose a shape and its fill, stroke, width and corner radius.")

    function shapeKinds() {
        return [
            { kind: "rectangle", label: qsTr("Rectangle") },
            { kind: "ellipse", label: qsTr("Ellipse") },
            { kind: "line", label: qsTr("Line") },
            { kind: "arrow", label: qsTr("Arrow") }
        ]
    }

    function swatchEntries() {
        return [
            { key: "white", label: qsTr("White"), color: root.whiteColor },
            { key: "black", label: qsTr("Black"), color: root.blackColor },
            { key: "warm-grey", label: qsTr("Warm grey"), color: root.warmGreyColor },
            { key: "peach", label: qsTr("Peach"), color: root.peachColor },
            { key: "red", label: qsTr("Red"), color: root.redColor },
            { key: "blue", label: qsTr("Blue"), color: root.blueColor }
        ]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing2xl
        spacing: Theme.spacingLg

        Label {
            text: qsTr("SHAPES")
            color: root.theme.muted
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontWeightDemiBold
            font.letterSpacing: Theme.trackingWide
        }
        Label {
            text: qsTr("Shape")
            color: root.theme.text
            font.pixelSize: Theme.fontHeadline
            font.weight: Theme.fontWeightDemiBold
        }

        // ── Shape type ─────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Theme.spacingXs
            columnSpacing: Theme.spacingXs

            Repeater {
                model: root.shapeKinds()

                delegate: NekoButton {
                    required property var modelData
                    objectName: "shape-type-" + modelData.kind
                    Layout.fillWidth: true
                    implicitHeight: Theme.controlHeightSm
                    text: modelData.label
                    variant: root.shapeKind === modelData.kind ? "primary" : "secondary"
                    accessibleName: qsTr("%1 shape").arg(modelData.label)
                    onClicked: root.shapeKind = modelData.kind
                }
            }
        }

        // ── Fill ───────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            opacity: root.enabled && root.supportsFill ? 1 : Theme.opacityMuted

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Fill")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }
                Item { Layout.fillWidth: true }
                NekoToggle {
                    id: fillToggle
                    objectName: "shape-filled"
                    checked: false
                    enabled: root.enabled && root.supportsFill
                    accessibleName: qsTr("Fill shape")
                    Component.onCompleted: checked = root.filled
                    onToggled: root.filled = checked
                    Connections {
                        target: root
                        function onFilledChanged() {
                            if (fillToggle.checked !== root.filled)
                                fillToggle.checked = root.filled
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 6
                columnSpacing: Theme.spacingXs
                rowSpacing: Theme.spacingXs

                Repeater {
                    model: root.swatchEntries()

                    delegate: NekoSwatch {
                        required property var modelData
                        objectName: "shape-fill-" + modelData.key
                        swatchColor: modelData.color
                        selected: Qt.colorEqual(root.fillColor, modelData.color)
                        enabled: root.enabled && root.supportsFill
                        accessibleName: qsTr("Fill colour %1").arg(modelData.label)
                        onClicked: root.fillColor = modelData.color
                    }
                }
            }
        }

        // ── Stroke ─────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                text: qsTr("Stroke")
                color: root.theme.muted
                font.pixelSize: Theme.fontSmall
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 6
                columnSpacing: Theme.spacingXs
                rowSpacing: Theme.spacingXs

                Repeater {
                    model: root.swatchEntries()

                    delegate: NekoSwatch {
                        required property var modelData
                        objectName: "shape-stroke-" + modelData.key
                        swatchColor: modelData.color
                        selected: Qt.colorEqual(root.strokeColor, modelData.color)
                        accessibleName: qsTr("Stroke colour %1").arg(modelData.label)
                        onClicked: root.strokeColor = modelData.color
                    }
                }
            }
        }

        // ── Stroke width ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Stroke width")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }
                Item { Layout.fillWidth: true }
                Label {
                    objectName: "shape-stroke-width-value"
                    text: Math.round(root.strokeWidth) + " px"
                    color: root.theme.text
                    font.pixelSize: Theme.fontCaption
                }
            }

            NekoSlider {
                id: strokeWidthSlider
                objectName: "shape-stroke-width"
                Layout.fillWidth: true
                from: root.minStrokeWidth
                to: root.maxStrokeWidth
                stepSize: 1
                defaultValue: 4
                accessibleName: qsTr("Stroke width")
                onPreview: function(value) { root.strokeWidth = Math.round(value) }
                Component.onCompleted: value = root.strokeWidth
                Connections {
                    target: root
                    function onStrokeWidthChanged() {
                        if (!strokeWidthSlider.dragging)
                            strokeWidthSlider.value = root.strokeWidth
                    }
                }
            }
        }

        // ── Corner radius ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Corner radius")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }
                Item { Layout.fillWidth: true }
                Label {
                    objectName: "shape-corner-radius-value"
                    text: Math.round(root.cornerRadius) + " px"
                    color: root.theme.text
                    font.pixelSize: Theme.fontCaption
                }
            }

            NekoSlider {
                id: cornerSlider
                objectName: "shape-corner-radius"
                Layout.fillWidth: true
                enabled: root.enabled && root.supportsCorner
                from: root.minCornerRadius
                to: root.maxCornerRadius
                stepSize: 1
                defaultValue: 0
                accessibleName: qsTr("Corner radius")
                onPreview: function(value) { root.cornerRadius = Math.round(value) }
                Component.onCompleted: value = root.cornerRadius
                Connections {
                    target: root
                    function onCornerRadiusChanged() {
                        if (!cornerSlider.dragging)
                            cornerSlider.value = root.cornerRadius
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.theme.muted
            font.pixelSize: Theme.fontCaption
            text: qsTr("Drag on the image to draw. Hold Shift to constrain proportions. "
                       + "Esc cancels the current shape.")
        }

        Item { Layout.fillHeight: true }
    }
}
