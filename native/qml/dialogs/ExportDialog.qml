import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    ExportDialog — format-aware export options.

    The integrator supplies the chosen format and the current file name, then
    connects exportRequested(). Quality is always clamped to 0–100 and the
    background is always opaque, because the renderer flattens every export
    onto a solid colour today. ICC/EXIF embedding is not implemented yet and
    the dialog says so explicitly.

    Qt.AlignCenter is used by CanvasSizeDialog; this dialog only deals with the
    export copy and never mutates the document.
*/
NekoDialog {
    id: root

    property string formatId: "jpeg"
    property string formatLabel: ""
    property string fileName: ""
    property bool supportsQuality: true
    property int initialQuality: 90
    property color initialBackground: "#ffffff"
    property bool busy: false
    property url previewUrl
    property int previewWidth: 0
    property int previewHeight: 0

    /*! Current, normalised quality (0–100). */
    property int quality: initialQuality
    /*! Current background; alpha is forced to 1. */
    property color backgroundColor: "#ffffff"

    readonly property bool fileNameValid: fileName.trim().length > 0
    readonly property bool canAccept: !busy && fileNameValid

    /* Sample backgrounds are content values, not design tokens. */
    readonly property color whiteBackground: "#ffffff"
    readonly property color blackBackground: "#000000"
    readonly property color warmGreyBackground: "#8b8780"

    property bool _ready: false
    property bool _resolved: false

    signal exportRequested(string format, int quality, color background)

    title: qsTr("Export image")
    description: qsTr("Save a copy with a fixed set of options. The editor document is not changed.")
    focus: true

    onQualityChanged: {
        const clamped = Math.max(0, Math.min(100, Math.round(quality)))
        if (quality !== clamped) {
            quality = clamped
            return
        }
        if (_ready && qualitySlider && !qualitySlider.dragging)
            qualitySlider.value = quality
    }

    onBackgroundColorChanged: {
        if (Math.abs(backgroundColor.a - 1) > 0.0001)
            backgroundColor = Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, 1)
    }

    onFileNameChanged: {
        if (_ready && fileNameInput && !fileNameInput.activeFocus
                && fileNameInput.text !== fileName)
            fileNameInput.text = fileName
    }

    onOpened: {
        _resolved = false
        _ready = true
        quality = Math.max(0, Math.min(100, Math.round(initialQuality)))
        backgroundColor = Qt.rgba(initialBackground.r, initialBackground.g, initialBackground.b, 1)
        fileNameInput.text = fileName
        qualitySlider.value = quality
    }

    onClosed: {
        if (!_resolved)
            rejected()
        _resolved = false
    }

    Component.onCompleted: _ready = true

    function requestExport() {
        if (!canAccept)
            return
        _resolved = true
        exportRequested(formatId, quality, backgroundColor)
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

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            radius: Theme.radiusSm
            color: Theme.background
            border.width: Theme.borderWidth
            border.color: Theme.border
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                source: root.previewUrl
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: true
            }
            Text {
                visible: root.previewWidth > 0 && root.previewHeight > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingSm
                text: root.previewWidth + " × " + root.previewHeight + " px"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontCaption
                style: Text.Outline
                styleColor: Theme.scrim
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Format")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }

            Text {
                objectName: "export-format-label"
                text: root.formatLabel.length > 0 ? root.formatLabel : root.formatId.toUpperCase()
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightMedium
            }
        }

        Text {
            text: qsTr("File name")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        TextField {
            id: fileNameInput
            objectName: "export-file-name"
            Layout.fillWidth: true
            enabled: !root.busy
            text: root.fileName
            placeholderText: qsTr("File name")
            color: root.busy ? Theme.textTertiary : Theme.textPrimary
            placeholderTextColor: Theme.textTertiary
            font.pixelSize: Theme.fontSmall
            leftPadding: Theme.spacingMd
            rightPadding: Theme.spacingMd
            topPadding: 0
            bottomPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true

            Accessible.name: qsTr("File name")

            onTextEdited: root.fileName = text

            background: Rectangle {
                radius: Theme.radiusSm
                color: Theme.background
                border.width: fileNameInput.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
                border.color: fileNameInput.activeFocus ? Theme.accent
                              : root.fileNameValid ? Theme.border : Theme.danger
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.supportsQuality
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Quality")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }

            Text {
                objectName: "export-quality-value"
                text: root.quality + "%"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightMedium
            }
        }

        NekoSlider {
            id: qualitySlider
            objectName: "export-quality"
            Layout.fillWidth: true
            visible: root.supportsQuality
            from: 0
            to: 100
            stepSize: 1
            defaultValue: root.initialQuality
            enabled: root.supportsQuality && !root.busy
            accessibleName: qsTr("Export quality")
            onPreview: function(value) { root.quality = Math.round(value) }
            onFinish: function(value) { root.quality = Math.round(value) }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.supportsQuality
            text: qsTr("This format does not use a quality setting.")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
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
                objectName: "export-background-white"
                swatchColor: root.whiteBackground
                selected: Qt.colorEqual(root.backgroundColor, root.whiteBackground)
                enabled: !root.busy
                accessibleName: qsTr("White background")
                onClicked: root.backgroundColor = root.whiteBackground
            }

            NekoSwatch {
                objectName: "export-background-black"
                swatchColor: root.blackBackground
                selected: Qt.colorEqual(root.backgroundColor, root.blackBackground)
                enabled: !root.busy
                accessibleName: qsTr("Black background")
                onClicked: root.backgroundColor = root.blackBackground
            }

            NekoSwatch {
                objectName: "export-background-warm-grey"
                swatchColor: root.warmGreyBackground
                selected: Qt.colorEqual(root.backgroundColor, root.warmGreyBackground)
                enabled: !root.busy
                accessibleName: qsTr("Warm grey background")
                onClicked: root.backgroundColor = root.warmGreyBackground
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.formatId === "jpeg"
            spacing: Theme.spacingSm

            NekoSwatch {
                objectName: "export-background-transparent"
                swatchColor: "transparent"
                showChecker: true
                selected: false
                enabled: false
                accessibleName: qsTr("Transparent background")
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Transparent — JPEG cannot keep an alpha channel. The image is flattened onto the selected background.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.separator
        }

        Text {
            objectName: "export-metadata-note"
            Layout.fillWidth: true
            text: qsTr("Colour profiles (ICC) and EXIF metadata are not embedded in exports yet.")
            color: Theme.textTertiary
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
                objectName: "export-cancel"
                text: qsTr("Cancel")
                variant: "ghost"
                onClicked: root.requestReject()
            }

            NekoButton {
                objectName: "export-accept"
                text: root.busy ? qsTr("Exporting…") : qsTr("Export")
                variant: "primary"
                enabled: root.canAccept
                onClicked: root.requestExport()
            }
        }
    }
}
