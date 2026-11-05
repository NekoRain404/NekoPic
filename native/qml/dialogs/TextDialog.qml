import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    TextDialog — content and style for a new text object.

    The integrator supplies the image-space anchor picked by
    TextPlacementOverlay, then connects `textRequested()` to the controller:

        editor.addText(text, anchorX, anchorY, fontSize, color, alignment)

    The anchor is expected in document image pixels. Accept is disabled when
    the text is empty or only whitespace, when the anchor falls outside the
    image, or while a request is busy. `setAnchor()` clamps a point into the
    image for callers that want the dialog to normalise it.
*/
NekoDialog {
    id: root

    /*! Anchor in image pixels. */
    property real anchorX: 0
    property real anchorY: 0
    property int imageWidth: 0
    property int imageHeight: 0
    property bool busy: false

    /*! Raw text content of the editor. */
    property alias text: textInput.text
    property real fontSize: 32
    property color textColor: root.whiteColor
    /*! Nine-way Qt alignment flags (Qt.AlignLeft/HCenter/Right × top/center/bottom). */
    property int alignment: Qt.AlignCenter

    readonly property real minFontSize: 4
    readonly property real maxFontSize: 512

    readonly property bool textValid: text.trim().length > 0
    readonly property bool fontSizeValid: fontSize >= minFontSize && fontSize <= maxFontSize
    readonly property bool hasImage: imageWidth > 0 && imageHeight > 0
    readonly property bool anchorValid: hasImage
                                        && anchorX >= 0 && anchorX <= imageWidth
                                        && anchorY >= 0 && anchorY <= imageHeight
    readonly property bool canAccept: !busy && textValid && fontSizeValid && anchorValid
    readonly property int alignmentIndex: indexForAlignment(alignment)

    /*! Anchor clamped into the image, used by the preview. */
    readonly property real effectiveAnchorX: hasImage
                                            ? Math.max(0, Math.min(imageWidth, anchorX)) : 0
    readonly property real effectiveAnchorY: hasImage
                                            ? Math.max(0, Math.min(imageHeight, anchorY)) : 0

    readonly property string validationMessage: {
        if (!textValid)
            return qsTr("Enter some text.")
        if (!fontSizeValid)
            return qsTr("Font size must be between %1 and %2 px.").arg(minFontSize).arg(maxFontSize)
        if (!hasImage)
            return qsTr("Open an image before adding text.")
        if (!anchorValid)
            return qsTr("The anchor must be inside the image.")
        return ""
    }

    /* Sample colours are content values, not design tokens. */
    readonly property color whiteColor: "#ffffff"
    readonly property color blackColor: "#000000"
    readonly property color warmGreyColor: "#8b8780"
    readonly property color peachColor: Theme.accent
    readonly property color redColor: "#c0504d"
    readonly property color blueColor: "#4a6fa5"

    property bool _ready: false
    property bool _resolved: false
    property bool _attempted: false
    readonly property bool showValidation: _attempted && !canAccept

    signal textRequested(string text, real anchorX, real anchorY, real fontSize,
                         color color, int alignment)

    title: qsTr("Add text")
    description: qsTr("Type your text, choose a style, then place it on the image.")
    acceptText: ""
    rejectText: ""

    onOpened: {
        _resolved = false
        _attempted = false
        _ready = true
        if (fontSizeSlider)
            fontSizeSlider.value = fontSize
        textInput.forceActiveFocus(Qt.OtherFocusReason)
    }
    onClosed: {
        if (!_resolved)
            rejected()
        _resolved = false
        _attempted = false
    }
    Component.onCompleted: {
        _ready = true
        if (fontSizeSlider)
            fontSizeSlider.value = fontSize
    }

    onFontSizeChanged: {
        const clamped = Math.max(minFontSize, Math.min(maxFontSize, Math.round(fontSize)))
        if (fontSize !== clamped) {
            fontSize = clamped
            return
        }
        if (_ready && fontSizeSlider && !fontSizeSlider.dragging
                && fontSizeSlider.value !== clamped)
            fontSizeSlider.value = clamped
    }

    /*! Maps a 0–8 grid index (row-major) to Qt alignment flags. */
    function alignmentForIndex(index) {
        const column = index % 3
        const row = Math.floor(index / 3)
        const horizontal = column === 0 ? Qt.AlignLeft
                         : column === 1 ? Qt.AlignHCenter : Qt.AlignRight
        const vertical = row === 0 ? Qt.AlignTop
                       : row === 1 ? Qt.AlignVCenter : Qt.AlignBottom
        return horizontal | vertical
    }

    /*! Maps Qt alignment flags back to a 0–8 grid index (row-major). */
    function indexForAlignment(value) {
        const column = (value & Qt.AlignHCenter) ? 1 : (value & Qt.AlignRight) ? 2 : 0
        const row = (value & Qt.AlignVCenter) ? 1 : (value & Qt.AlignBottom) ? 2 : 0
        return row * 3 + column
    }

    function alignmentName(index) {
        const names = [qsTr("Top left"), qsTr("Top"), qsTr("Top right"),
                       qsTr("Left"), qsTr("Center"), qsTr("Right"),
                       qsTr("Bottom left"), qsTr("Bottom"), qsTr("Bottom right")]
        return names[Math.max(0, Math.min(names.length - 1, index))]
    }

    /*! Clamps an anchor into the image and writes it back. */
    function setAnchor(x, y) {
        if (!isFinite(x) || !isFinite(y))
            return
        anchorX = hasImage ? Math.max(0, Math.min(imageWidth, x)) : 0
        anchorY = hasImage ? Math.max(0, Math.min(imageHeight, y)) : 0
    }

    function requestCreate() {
        if (!canAccept) {
            _attempted = true
            return false
        }
        _resolved = true
        _attempted = false
        root.textRequested(text.trim(), effectiveAnchorX, effectiveAnchorY,
                           Math.round(fontSize), textColor, alignment)
        close()
        return true
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
            text: qsTr("Text")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 76

            TextArea {
                id: textInput
                objectName: "text-dialog-text"
                anchors.fill: parent
                enabled: !root.busy
                placeholderText: qsTr("Type your text…")
                placeholderTextColor: Theme.textTertiary
                color: root.busy ? Theme.textTertiary : Theme.textPrimary
                font.pixelSize: Theme.fontBody
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                leftPadding: Theme.spacingSm
                rightPadding: Theme.spacingSm
                topPadding: Theme.spacingSm
                bottomPadding: Theme.spacingSm

                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Text content")

                Keys.onEscapePressed: function(event) {
                    root.requestReject()
                    event.accepted = true
                }

                background: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.background
                    border.width: textInput.activeFocus ? Theme.focusRingWidth
                                                        : Theme.borderWidth
                    border.color: textInput.activeFocus ? Theme.accent
                                  : root.showValidation && !root.textValid ? Theme.danger
                                  : Theme.border
                }
            }

            Rectangle {
                anchors.fill: textInput
                anchors.margins: -Theme.focusRingOffset
                radius: Theme.radiusSm + Theme.focusRingOffset
                color: "transparent"
                border.width: Theme.focusRingWidth
                border.color: Theme.focusRing
                visible: textInput.activeFocus && !root.busy
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Font size")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }

            Text {
                objectName: "text-dialog-font-size-value"
                text: Math.round(root.fontSize) + " px"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightMedium
            }
        }

        NekoSlider {
            id: fontSizeSlider
            objectName: "text-dialog-font-size"
            Layout.fillWidth: true
            from: root.minFontSize
            to: root.maxFontSize
            stepSize: 1
            defaultValue: 32
            enabled: !root.busy
            accessibleName: qsTr("Font size")
            onPreview: function(value) { root.fontSize = Math.round(value) }
            onFinish: function(value) { root.fontSize = Math.round(value) }
        }

        Text {
            text: qsTr("Colour")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            NekoSwatch {
                objectName: "text-color-white"
                swatchColor: root.whiteColor
                selected: Qt.colorEqual(root.textColor, root.whiteColor)
                enabled: !root.busy
                accessibleName: qsTr("White text")
                onClicked: root.textColor = root.whiteColor
            }

            NekoSwatch {
                objectName: "text-color-black"
                swatchColor: root.blackColor
                selected: Qt.colorEqual(root.textColor, root.blackColor)
                enabled: !root.busy
                accessibleName: qsTr("Black text")
                onClicked: root.textColor = root.blackColor
            }

            NekoSwatch {
                objectName: "text-color-warm-grey"
                swatchColor: root.warmGreyColor
                selected: Qt.colorEqual(root.textColor, root.warmGreyColor)
                enabled: !root.busy
                accessibleName: qsTr("Warm grey text")
                onClicked: root.textColor = root.warmGreyColor
            }

            NekoSwatch {
                objectName: "text-color-peach"
                swatchColor: root.peachColor
                selected: Qt.colorEqual(root.textColor, root.peachColor)
                enabled: !root.busy
                accessibleName: qsTr("Peach text")
                onClicked: root.textColor = root.peachColor
            }

            NekoSwatch {
                objectName: "text-color-red"
                swatchColor: root.redColor
                selected: Qt.colorEqual(root.textColor, root.redColor)
                enabled: !root.busy
                accessibleName: qsTr("Red text")
                onClicked: root.textColor = root.redColor
            }

            NekoSwatch {
                objectName: "text-color-blue"
                swatchColor: root.blueColor
                selected: Qt.colorEqual(root.textColor, root.blueColor)
                enabled: !root.busy
                accessibleName: qsTr("Blue text")
                onClicked: root.textColor = root.blueColor
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg

            ColumnLayout {
                spacing: Theme.spacingXs

                Text {
                    text: qsTr("Alignment")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                }

                GridLayout {
                    objectName: "text-align-grid"
                    columns: 3
                    rowSpacing: Theme.spacingXs
                    columnSpacing: Theme.spacingXs

                    Repeater {
                        model: 9

                        delegate: AbstractButton {
                            id: cell
                            required property int index

                            readonly property int cellRow: Math.floor(index / 3)
                            readonly property int cellColumn: index % 3
                            readonly property bool selected:
                                root.alignment === root.alignmentForIndex(index)

                            objectName: "text-align-" + index
                            implicitWidth: 28
                            implicitHeight: 28
                            padding: Theme.spacingXs
                            enabled: !root.busy
                            hoverEnabled: true
                            focusPolicy: Qt.StrongFocus
                            activeFocusOnTab: true
                            opacity: enabled ? 1 : Theme.opacityDisabled

                            Accessible.role: Accessible.RadioButton
                            Accessible.name: root.alignmentName(index)
                            Accessible.checkable: true
                            Accessible.checked: selected
                            Accessible.focusable: true
                            Accessible.focused: activeFocus

                            onClicked: root.alignment = root.alignmentForIndex(index)

                            background: Rectangle {
                                radius: Theme.radiusXs
                                color: cell.selected ? Theme.selection
                                      : cell.hovered ? Theme.hover : "transparent"
                                border.width: Theme.borderWidth
                                border.color: cell.selected ? Theme.accent : Theme.border
                            }

                            contentItem: Item {
                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    x: cell.cellColumn * (parent.width - width) / 2
                                    y: cell.cellRow * (parent.height - height) / 2
                                    color: cell.selected ? Theme.accent : Theme.textSecondary
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Theme.focusRingOffset
                                radius: Theme.radiusXs + Theme.focusRingOffset
                                color: "transparent"
                                border.width: Theme.focusRingWidth
                                border.color: Theme.focusRing
                                visible: cell.visualFocus && cell.enabled
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Text {
                    text: qsTr("Anchor")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                }

                Rectangle {
                    id: anchorPreview
                    objectName: "text-anchor-preview"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: Theme.radiusSm
                    color: Theme.canvas
                    border.width: Theme.borderWidth
                    border.color: root.anchorValid ? Theme.border : Theme.danger
                    clip: true

                    Rectangle {
                        id: anchorDot
                        width: 8
                        height: 8
                        radius: width / 2
                        color: Theme.accent
                        x: {
                            const inset = Theme.spacingXs
                            const span = Math.max(0, anchorPreview.width - 2 * inset - width)
                            const ratio = root.imageWidth > 0
                                    ? Math.max(0, Math.min(1, root.effectiveAnchorX / root.imageWidth))
                                    : 0.5
                            return inset + ratio * span
                        }
                        y: {
                            const inset = Theme.spacingXs
                            const span = Math.max(0, anchorPreview.height - 2 * inset - height)
                            const ratio = root.imageHeight > 0
                                    ? Math.max(0, Math.min(1, root.effectiveAnchorY / root.imageHeight))
                                    : 0.5
                            return inset + ratio * span
                        }
                    }
                }

                Text {
                    objectName: "text-anchor-label"
                    Layout.fillWidth: true
                    text: root.hasImage
                          ? qsTr("Anchor: %1 × %2 px")
                            .arg(Math.round(root.effectiveAnchorX))
                            .arg(Math.round(root.effectiveAnchorY))
                          : qsTr("No image loaded")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            objectName: "text-dialog-error"
            Layout.fillWidth: true
            visible: root.showValidation && root.validationMessage.length > 0
            text: root.validationMessage
            color: Theme.danger
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.separator
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
                objectName: "text-dialog-cancel"
                text: qsTr("Cancel")
                variant: "ghost"
                onClicked: root.requestReject()
            }

            NekoButton {
                objectName: "text-dialog-accept"
                text: root.busy ? qsTr("Adding…") : qsTr("Add text")
                variant: "primary"
                enabled: root.canAccept
                onClicked: root.requestCreate()
            }
        }
    }
}
