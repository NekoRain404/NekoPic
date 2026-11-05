import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    CanvasSizeDialog — change the working canvas without scaling pixels.

    Anchors use Qt's alignment flags (Qt.AlignLeft/HCenter/Right combined with
    Qt.AlignTop/VCenter/Bottom). Existing pixels keep their size; exposed
    space is filled with the chosen background, which may be transparent.
    Dimensions are validated against 1–32,768 px and a 100 MP total.
*/
NekoDialog {
    id: root

    property int imageWidth: 0
    property int imageHeight: 0
    property bool busy: false

    /*! Qt alignment flags describing where the current image sits. */
    property int anchor: Qt.AlignHCenter | Qt.AlignVCenter
    /*! Fill colour for newly exposed canvas; transparent is allowed. */
    property color backgroundColor: "transparent"

    readonly property int maxDimension: 32768
    readonly property real maxPixels: 100000000
    readonly property bool transparentBackground: Math.abs(backgroundColor.a) < 0.001

    readonly property bool dimensionsValid: widthField.valid && heightField.valid
    readonly property real pixelCount: dimensionsValid
                                        ? widthField.numericValue * heightField.numericValue : 0
    readonly property bool withinPixelLimit: dimensionsValid && pixelCount <= maxPixels
    readonly property bool canAccept: !busy && withinPixelLimit

    readonly property var anchorChoices: [
        { id: "top-left",      label: qsTr("Top left"),      anchor: Qt.AlignLeft | Qt.AlignTop },
        { id: "top",           label: qsTr("Top"),           anchor: Qt.AlignHCenter | Qt.AlignTop },
        { id: "top-right",     label: qsTr("Top right"),     anchor: Qt.AlignRight | Qt.AlignTop },
        { id: "left",          label: qsTr("Left"),          anchor: Qt.AlignLeft | Qt.AlignVCenter },
        { id: "center",        label: qsTr("Center"),        anchor: Qt.AlignHCenter | Qt.AlignVCenter },
        { id: "right",         label: qsTr("Right"),         anchor: Qt.AlignRight | Qt.AlignVCenter },
        { id: "bottom-left",   label: qsTr("Bottom left"),   anchor: Qt.AlignLeft | Qt.AlignBottom },
        { id: "bottom",        label: qsTr("Bottom"),        anchor: Qt.AlignHCenter | Qt.AlignBottom },
        { id: "bottom-right",  label: qsTr("Bottom right"),  anchor: Qt.AlignRight | Qt.AlignBottom }
    ]

    /* Sample backgrounds are content values, not design tokens. */
    readonly property color whiteBackground: "#ffffff"
    readonly property color blackBackground: "#000000"

    readonly property string estimateText: {
        if (!dimensionsValid)
            return qsTr("Enter a width and height in pixels.")
        const megapixels = (pixelCount / 1000000).toFixed(1)
        return qsTr("%1 × %2 px · %3 MP").arg(widthField.numericValue)
                .arg(heightField.numericValue).arg(megapixels)
    }

    readonly property string validationMessage: {
        if (dimensionsValid && !withinPixelLimit) {
            return qsTr("The result is %1 MP; the limit is 100 MP. Reduce the width or height.")
                    .arg((pixelCount / 1000000).toFixed(1))
        }
        if (!dimensionsValid && (widthField.trimmedText.length > 0 || heightField.trimmedText.length > 0))
            return qsTr("Width and height must be whole numbers between 1 and 32,768 px.")
        return ""
    }

    property bool _ready: false
    property bool _resolved: false

    signal canvasResizeRequested(int width, int height, int anchor, color background)

    title: qsTr("Canvas size")
    description: qsTr("Change the working area without scaling the photo.")

    onImageWidthChanged: if (_ready && !opened) resetDimensions()
    onImageHeightChanged: if (_ready && !opened) resetDimensions()
    onOpened: {
        _resolved = false
        resetDimensions()
    }
    onClosed: {
        if (!_resolved)
            rejected()
        _resolved = false
    }
    Component.onCompleted: {
        _ready = true
        resetDimensions()
    }

    function setFieldText(field, value) {
        if (!field)
            return
        field.suppressEdit = true
        field.text = String(value)
        field.suppressEdit = false
    }

    function resetDimensions() {
        if (!_ready)
            return
        setFieldText(widthField, imageWidth > 0 ? imageWidth : "")
        setFieldText(heightField, imageHeight > 0 ? imageHeight : "")
    }

    function requestCanvasResize() {
        if (!canAccept)
            return
        _resolved = true
        canvasResizeRequested(widthField.numericValue, heightField.numericValue,
                              anchor, transparentBackground ? Qt.rgba(0, 0, 0, 0) : backgroundColor)
        close()
    }

    function requestReject() {
        _resolved = true
        rejected()
        close()
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingMd

        Text {
            objectName: "canvas-original"
            Layout.fillWidth: true
            text: root.imageWidth > 0 && root.imageHeight > 0
                  ? qsTr("Current image: %1 × %2 px").arg(root.imageWidth).arg(root.imageHeight)
                  : qsTr("Current image size is not available yet.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Text {
                    text: qsTr("Width")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontCaption
                }

                NekoNumberField {
                    id: widthField
                    objectName: "canvas-width"
                    Layout.fillWidth: true
                    minimum: 1
                    maximum: root.maxDimension
                    placeholderText: qsTr("Width")
                    accessibleName: qsTr("Canvas width in pixels")
                    enabled: !root.busy
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Text {
                    text: qsTr("Height")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontCaption
                }

                NekoNumberField {
                    id: heightField
                    objectName: "canvas-height"
                    Layout.fillWidth: true
                    minimum: 1
                    maximum: root.maxDimension
                    placeholderText: qsTr("Height")
                    accessibleName: qsTr("Canvas height in pixels")
                    enabled: !root.busy
                }
            }
        }

        Text {
            text: qsTr("Anchor point")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 3
            rowSpacing: Theme.spacingXs
            columnSpacing: Theme.spacingXs

            Repeater {
                model: root.anchorChoices

                delegate: NekoButton {
                    required property var modelData
                    objectName: "canvas-anchor-" + modelData.id
                    text: ""
                    iconName: root.anchor === modelData.anchor ? "check" : ""
                    variant: root.anchor === modelData.anchor ? "primary" : "secondary"
                    leftPadding: Theme.spacingSm
                    rightPadding: Theme.spacingSm
                    enabled: !root.busy
                    accessibleName: modelData.label
                    onClicked: root.anchor = modelData.anchor
                }
            }
        }

        Text {
            text: qsTr("Background")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            NekoSwatch {
                objectName: "canvas-background-transparent"
                swatchColor: "transparent"
                showChecker: true
                selected: root.transparentBackground
                enabled: !root.busy
                accessibleName: qsTr("Transparent background")
                onClicked: root.backgroundColor = Qt.rgba(0, 0, 0, 0)
            }

            NekoSwatch {
                objectName: "canvas-background-white"
                swatchColor: root.whiteBackground
                selected: !root.transparentBackground
                        && Qt.colorEqual(root.backgroundColor, root.whiteBackground)
                enabled: !root.busy
                accessibleName: qsTr("White background")
                onClicked: root.backgroundColor = root.whiteBackground
            }

            NekoSwatch {
                objectName: "canvas-background-black"
                swatchColor: root.blackBackground
                selected: !root.transparentBackground
                        && Qt.colorEqual(root.backgroundColor, root.blackBackground)
                enabled: !root.busy
                accessibleName: qsTr("Black background")
                onClicked: root.backgroundColor = root.blackBackground
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Canvas size does not scale the photo. Existing pixels keep their size; newly exposed space is filled with the chosen background.")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.separator
        }

        Text {
            objectName: "canvas-estimate"
            Layout.fillWidth: true
            text: root.estimateText
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        Text {
            objectName: "canvas-error"
            Layout.fillWidth: true
            visible: root.validationMessage.length > 0
            text: root.validationMessage
            color: Theme.danger
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            BusyIndicator {
                visible: root.busy
                running: root.busy
                Layout.preferredWidth: Theme.iconSizeLg
                Layout.preferredHeight: Theme.iconSizeLg
            }

            Item { Layout.fillWidth: true }

            NekoButton {
                objectName: "canvas-cancel"
                text: qsTr("Cancel")
                variant: "ghost"
                onClicked: root.requestReject()
            }

            NekoButton {
                objectName: "canvas-accept"
                text: root.busy ? qsTr("Applying…") : qsTr("Apply")
                variant: "primary"
                enabled: root.canAccept
                onClicked: root.requestCanvasResize()
            }
        }
    }
}
