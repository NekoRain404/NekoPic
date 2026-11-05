import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    ResizeImageDialog — pixel dimensions with an optional aspect lock.

    Dimensions are validated live against 1–32,768 px and a 100 MP total.
    With the lock on, editing either field proportionally updates the other
    from the original image ratio (rounded, never below 1 px). The dialog only
    emits resizeRequested(); applying the operation is the integrator's job.
*/
NekoDialog {
    id: root

    property int imageWidth: 0
    property int imageHeight: 0
    property bool busy: false

    readonly property int maxDimension: 32768
    readonly property real maxPixels: 100000000

    property alias lockAspect: lockToggle.checked

    readonly property bool dimensionsValid: widthField.valid && heightField.valid
    readonly property real pixelCount: dimensionsValid
                                        ? widthField.numericValue * heightField.numericValue : 0
    readonly property bool withinPixelLimit: dimensionsValid && pixelCount <= maxPixels
    readonly property bool canAccept: !busy && withinPixelLimit

    readonly property string estimateText: {
        if (!dimensionsValid)
            return qsTr("Enter a width and height in pixels.")
        const megapixels = (pixelCount / 1000000).toFixed(1)
        const megabytes = Math.max(1, Math.ceil(pixelCount * 4 / (1024 * 1024)))
        return qsTr("%1 × %2 px · %3 MP · about %4 MB in memory")
                .arg(widthField.numericValue).arg(heightField.numericValue)
                .arg(megapixels).arg(megabytes)
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

    /*! Keeps the option body above the fixed error line and action row. */
    readonly property real _scrollMaxHeight: {
        const host = root.parent && root.parent.height > 0 ? root.parent.height : 700
        return Math.max(160, host - 250)
    }

    signal resizeRequested(int width, int height)

    title: qsTr("Resize image")
    description: qsTr("Scale the photo to new pixel dimensions. The image is resampled when applied.")

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

    function handleWidthEdited() {
        if (!lockAspect || !widthField.valid || imageWidth <= 0 || imageHeight <= 0)
            return
        const target = Math.max(1, Math.round(widthField.numericValue * imageHeight / imageWidth))
        setFieldText(heightField, target)
    }

    function handleHeightEdited() {
        if (!lockAspect || !heightField.valid || imageWidth <= 0 || imageHeight <= 0)
            return
        const target = Math.max(1, Math.round(heightField.numericValue * imageWidth / imageHeight))
        setFieldText(widthField, target)
    }

    function requestResize() {
        if (!canAccept)
            return
        _resolved = true
        resizeRequested(widthField.numericValue, heightField.numericValue)
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

        Flickable {
            id: resizeScroller
            objectName: "resize-scroll"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(resizeColumn.implicitHeight, root._scrollMaxHeight)
            contentWidth: width
            contentHeight: resizeColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: NekoScrollBar {
                objectName: "resize-scrollbar"
                policy: ScrollBar.AsNeeded
                accessibleName: qsTr("Resize options scroll")
            }

            ColumnLayout {
                id: resizeColumn
                width: resizeScroller.width
                spacing: Theme.spacingMd

        Text {
            objectName: "resize-original"
            Layout.fillWidth: true
            text: root.imageWidth > 0 && root.imageHeight > 0
                  ? qsTr("Original size: %1 × %2 px").arg(root.imageWidth).arg(root.imageHeight)
                  : qsTr("Original size is not available yet.")
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
                    objectName: "resize-width"
                    Layout.fillWidth: true
                    minimum: 1
                    maximum: root.maxDimension
                    placeholderText: qsTr("Width")
                    accessibleName: qsTr("Width in pixels")
                    enabled: !root.busy
                    onEdited: root.handleWidthEdited()
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
                    objectName: "resize-height"
                    Layout.fillWidth: true
                    minimum: 1
                    maximum: root.maxDimension
                    placeholderText: qsTr("Height")
                    accessibleName: qsTr("Height in pixels")
                    enabled: !root.busy
                    onEdited: root.handleHeightEdited()
                }
            }
        }

        NekoToggle {
            id: lockToggle
            objectName: "resize-lock"
            text: qsTr("Lock aspect ratio")
            checked: true
            enabled: !root.busy
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.separator
        }

        Text {
            objectName: "resize-estimate"
            Layout.fillWidth: true
            text: root.estimateText
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }
            }
        }

        Text {
            objectName: "resize-error"
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
                objectName: "resize-cancel"
                text: qsTr("Cancel")
                variant: "ghost"
                onClicked: root.requestReject()
            }

            NekoButton {
                objectName: "resize-accept"
                text: root.busy ? qsTr("Resizing…") : qsTr("Resize")
                variant: "primary"
                enabled: root.canAccept
                onClicked: root.requestResize()
            }
        }
    }
}
