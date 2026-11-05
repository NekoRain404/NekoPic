pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"
import "../dialogs"
import "FontCatalog.js" as FontCatalog

/*!
    TextPanel — the H5 text workspace, ported to the right-side panel.

    Pure view: it renders the current text style and reports every user edit
    through a signal. The owner (Main / DocumentController) decides whether a
    change edits the selected text object or seeds the next one:

        TextPanel {
            enabled: editor.hasImage && !editor.busy
            busy: editor.busy
            editId: selectedTextId
            text: selectedInfo.text || ""
            fontFamily: selectedInfo.fontFamily || ""
            fontSize: selectedInfo.fontSize || 48
            alignment: selectedInfo.alignment || Qt.AlignLeft
            outline: (selectedInfo.outlineWidth || 0) > 0
            color: editor.foregroundColor
            onTextEdited: function(text) { ... }
            onStyleEdited: function(key, value) { ... }
            onResetRequested: { ... }
        }

    Properties:
      • text        — multiline content.
      • fontFamily  — "" selects the system default; the list is CJK-first.
      • fontSize    — 12–160 px (default 48).
      • alignment   — horizontal Qt alignment flags (Left / HCenter / Right).
      • outline     — dark outline toggle.
      • color       — foreground colour.
      • editId      — 0 in create mode; the edited object id otherwise.
      • busy        — locks every control while a document command runs.
      • showReset   — hide the optional reset button.

    Signals:
      • textEdited(text)       — user typed in the text area.
      • styleEdited(key, value)— key is one of "font", "size", "align",
                                 "outline", "color". Values are the property
                                 types above (alignment is Qt flags).
      • resetRequested()       — the reset button was pressed after the panel
                                 restored its documented defaults locally.

    Placement stays with TextPlacementOverlay; this panel never edits the
    anchor. Test hooks use objectNames prefixed "text-panel-".
*/
Item {
    id: root

    /*! Token map supplied by Main; defaults keep the panel standalone. */
    property var theme: ({ panel: Theme.panel, background: Theme.background,
                           raised: Theme.surfaceRaised, hover: Theme.hover,
                           border: Theme.border, text: Theme.textPrimary,
                           muted: Theme.textSecondary, accent: Theme.accent })

    property string text: ""
    property string fontFamily: root.defaultFontFamily
    property real fontSize: root.defaultFontSize
    /*! Horizontal Qt alignment flags: Left, HCenter or Right. */
    property int alignment: Qt.AlignLeft
    property bool outline: true
    property color color: root.peachColor
    property bool busy: false
    property var editId: 0
    property bool showReset: true

    signal textEdited(string text)
    signal styleEdited(string key, var value)
    signal resetRequested()

    readonly property string defaultFontFamily: "Noto Sans CJK SC"
    readonly property real defaultFontSize: 48
    readonly property real minFontSize: 12
    readonly property real maxFontSize: 160
    readonly property bool editMode: Number(editId) > 0

    /* Sample colours are content values, not design tokens. */
    readonly property color peachColor: "#eeb99a"
    readonly property color whiteColor: "#f7f4ed"
    readonly property color inkColor: "#1b1d1e"
    readonly property color redColor: "#e46a5d"
    readonly property color goldColor: "#e1b74e"
    readonly property color greenColor: "#6da788"
    readonly property color blueColor: "#61a3c7"
    readonly property color purpleColor: "#9275b9"

    /*! CJK-first ordering and the curated fallback live in FontCatalog.js. */
    readonly property var preferredFontFamilies: FontCatalog.preferredFamilies
    readonly property var curatedFontFamilies: FontCatalog.curatedFamilies

    readonly property bool hasSystemFontCatalog: {
        try {
            return typeof Qt.fontFamilies === "function"
        } catch (error) {
            return false
        }
    }

    /*! Live system family list; empty when enumeration is unavailable. */
    readonly property var systemFontFamilies: {
        if (!hasSystemFontCatalog)
            return []
        try {
            const families = Qt.fontFamilies()
            return families ? families : []
        } catch (error) {
            return []
        }
    }

    readonly property bool usesSystemFonts: systemFontFamilies.length > 0
    readonly property int fontCount: Math.max(0, fontChoices.length - 1)

    /*! The empty value always means "system default". */
    readonly property var fontChoices: FontCatalog.build(
        usesSystemFonts ? systemFontFamilies : curatedFontFamilies,
        qsTr("System default"))

    /*! Adds an externally supplied family so edit mode can show it. */
    readonly property var fontModel: {
        const items = fontChoices.slice()
        if (fontFamily.length > 0) {
            let found = false
            for (let i = 0; i < items.length; ++i) {
                if (items[i].value === fontFamily) {
                    found = true
                    break
                }
            }
            if (!found)
                items.push({ label: fontFamily, value: fontFamily })
        }
        return items
    }

    readonly property string fontNote: usesSystemFonts
        ? qsTr("%1 font families available on this system. Common CJK families are listed first.")
              .arg(fontCount)
        : qsTr("System font catalog unavailable. Showing the curated family list.")

    readonly property var swatches: [
        { key: "ivory", label: qsTr("Ivory"), value: whiteColor },
        { key: "ink", label: qsTr("Ink"), value: inkColor },
        { key: "peach", label: qsTr("Peach"), value: peachColor },
        { key: "red", label: qsTr("Red"), value: redColor },
        { key: "gold", label: qsTr("Gold"), value: goldColor },
        { key: "green", label: qsTr("Green"), value: greenColor },
        { key: "blue", label: qsTr("Blue"), value: blueColor },
        { key: "purple", label: qsTr("Purple"), value: purpleColor }
    ]

    readonly property bool controlsEnabled: root.enabled && !root.busy

    implicitWidth: 292
    implicitHeight: content.implicitHeight + 2 * Theme.spacing2xl
    property bool _ready: false
    property bool _syncing: false

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Text properties")
    Accessible.description: qsTr("Edit the text content, font, size, alignment, outline and colour.")

    // ── Helpers ─────────────────────────────────────────────────────────────
    function alignmentForIndex(index) {
        return index === 0 ? Qt.AlignLeft : index === 1 ? Qt.AlignHCenter : Qt.AlignRight
    }

    function indexForAlignment(value) {
        if ((value & Qt.AlignHCenter) || !(value & (Qt.AlignLeft | Qt.AlignRight)))
            return 1
        return (value & Qt.AlignRight) ? 2 : 0
    }

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

    function applyHex(value) {
        const normalized = normalizeHex(value)
        if (normalized.length === 0) {
            _syncHex()
            return false
        }
        root.color = normalized
        root.styleEdited("color", root.color)
        return true
    }

    function _syncHex() {
        if (typeof hexField !== "undefined" && hexField !== null)
            hexField.text = hexFor(root.color)
    }

    function _syncText() {
        if (typeof editor === "undefined" || editor === null)
            return
        if (editor.text !== root.text) {
            root._syncing = true
            editor.text = root.text
            root._syncing = false
        }
    }

    /*! Restores the documented defaults (H5: 48 px, left, outline on). */
    function reset() {
        text = ""
        fontFamily = defaultFontFamily
        fontSize = defaultFontSize
        alignment = Qt.AlignLeft
        outline = true
        color = peachColor
        _syncText()
        _syncHex()
    }

    onTextChanged: {
        if (!_ready || _syncing)
            return
        _syncText()
    }
    onFontSizeChanged: {
        const clamped = Math.max(minFontSize, Math.min(maxFontSize, Math.round(fontSize)))
        if (fontSize !== clamped) {
            fontSize = clamped
            return
        }
        if (_ready && sizeSlider && !sizeSlider.dragging)
            sizeSlider.value = clamped
    }
    onAlignmentChanged: {
        if (_ready && alignControl)
            alignControl.currentIndex = indexForAlignment(alignment)
    }
    onOutlineChanged: {
        if (_ready && outlineToggle && outlineToggle.checked !== outline)
            outlineToggle.checked = outline
    }
    onColorChanged: {
        if (typeof hexField !== "undefined" && hexField !== null && !hexField.activeFocus)
            _syncHex()
    }
    Component.onCompleted: {
        _ready = true
        _syncText()
        _syncHex()
        if (sizeSlider)
            sizeSlider.value = fontSize
        if (alignControl)
            alignControl.currentIndex = indexForAlignment(alignment)
        if (outlineToggle)
            outlineToggle.checked = outline
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.panel
    }

    Flickable {
        id: scroller
        objectName: "text-panel-scroll"
        anchors.fill: parent
        anchors.margins: Theme.spacing2xl
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: NekoScrollBar {
            policy: ScrollBar.AlwaysOff
            accessibleName: qsTr("Text settings scroll")
        }

        ColumnLayout {
            id: content
            width: scroller.width
            spacing: Theme.spacingLg

            Text {
                text: qsTr("TEXT")
                color: root.theme.muted
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.fontWeightDemiBold
                font.letterSpacing: Theme.trackingWide
            }

            Text {
                text: root.editMode ? qsTr("Edit text") : qsTr("Text")
                color: root.theme.text
                font.pixelSize: Theme.fontHeadline
                font.weight: Theme.fontWeightDemiBold
            }

            // ── Content ───────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Text {
                    text: qsTr("Content")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }

                TextArea {
                    id: editor
                    objectName: "text-panel-text"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    enabled: root.controlsEnabled
                    placeholderText: qsTr("Type your text…")
                    placeholderTextColor: Theme.textTertiary
                    color: root.controlsEnabled ? root.theme.text : Theme.textTertiary
                    font.pixelSize: Theme.fontBody
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    leftPadding: Theme.spacingSm
                    rightPadding: Theme.spacingSm
                    topPadding: Theme.spacingSm
                    bottomPadding: Theme.spacingSm

                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Text content")

                    onTextChanged: {
                        if (root._syncing)
                            return
                        root._syncing = true
                        root.text = text
                        root._syncing = false
                        if (root._ready)
                            root.textEdited(text)
                    }

                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: Theme.background
                        border.width: editor.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
                        border.color: editor.activeFocus ? Theme.accent : root.theme.border
                    }
                }
            }

            // ── Font ──────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Text {
                    text: qsTr("Font")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }

                FontPicker {
                    id: fontPicker
                    objectName: "text-panel-font"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.controlHeight
                    model: root.fontModel
                    currentValue: root.fontFamily
                    enabled: root.controlsEnabled
                    accessibleName: qsTr("Font family")
                    accessibleDescription: qsTr("Typeface used to render the text")

                    onFamilyChosen: function(value) {
                        root.fontFamily = value
                        root.styleEdited("font", value)
                    }
                }

                Text {
                    objectName: "text-panel-font-note"
                    Layout.fillWidth: true
                    text: root.fontNote
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                    lineHeight: Theme.lineHeightNormal
                    wrapMode: Text.WordWrap
                }
            }

            // ── Size ──────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: qsTr("Size")
                        color: root.theme.muted
                        font.pixelSize: Theme.fontSmall
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        objectName: "text-panel-size-value"
                        text: Math.round(root.fontSize) + " px"
                        color: root.theme.text
                        font.pixelSize: Theme.fontCaption
                    }
                }

                NekoSlider {
                    id: sizeSlider
                    objectName: "text-panel-size"
                    Layout.fillWidth: true
                    from: root.minFontSize
                    to: root.maxFontSize
                    stepSize: 1
                    defaultValue: root.defaultFontSize
                    enabled: root.controlsEnabled
                    accessibleName: qsTr("Font size")
                    onPreview: function(value) {
                        const next = Math.round(value)
                        if (root.fontSize !== next) {
                            root.fontSize = next
                            root.styleEdited("size", next)
                        }
                    }
                    onFinish: function(value) { root.fontSize = Math.round(value) }
                }
            }

            // ── Alignment ─────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Text {
                    text: qsTr("Alignment")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }

                NekoSegmentedControl {
                    id: alignControl
                    objectName: "text-panel-alignment"
                    Layout.fillWidth: true
                    model: [qsTr("Left"), qsTr("Center"), qsTr("Right")]
                    enabled: root.controlsEnabled
                    accessibleName: qsTr("Text alignment")
                    onActivated: function(index) {
                        root.alignment = root.alignmentForIndex(index)
                        root.styleEdited("align", root.alignment)
                    }
                }
            }

            // ── Outline ───────────────────────────────────────────────────
            NekoToggle {
                id: outlineToggle
                objectName: "text-panel-outline"
                text: qsTr("Dark outline")
                accessibleName: qsTr("Dark text outline")
                enabled: root.controlsEnabled
                onToggled: {
                    root.outline = checked
                    root.styleEdited("outline", checked)
                }
            }

            // ── Colour ────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Text {
                    text: qsTr("Colour")
                    color: root.theme.muted
                    font.pixelSize: Theme.fontSmall
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    rowSpacing: Theme.spacingSm
                    columnSpacing: Theme.spacingSm

                    Repeater {
                        model: root.swatches

                        delegate: NekoSwatch {
                            required property var modelData
                            objectName: "text-panel-color-" + modelData.key
                            swatchColor: modelData.value
                            selected: Qt.colorEqual(root.color, modelData.value)
                            enabled: root.controlsEnabled
                            accessibleName: qsTr("Text colour: %1").arg(modelData.label)
                            onClicked: {
                                root.color = modelData.value
                                root.styleEdited("color", modelData.value)
                            }
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
                        objectName: "text-panel-hex"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.controlHeightSm
                        enabled: root.controlsEnabled
                        font.pixelSize: Theme.fontSmall
                        color: root.theme.text
                        placeholderText: qsTr("#RRGGBB")
                        placeholderTextColor: Theme.textTertiary
                        selectionColor: Theme.selection
                        selectedTextColor: root.theme.text
                        maximumLength: 7
                        leftPadding: Theme.spacingSm
                        rightPadding: Theme.spacingSm
                        verticalAlignment: TextInput.AlignVCenter

                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Text colour hex value")

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
                            color: Theme.background
                            border.width: hexField.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
                            border.color: hexField.activeFocus ? Theme.focusRing : root.theme.border
                        }
                    }
                }
            }

            // ── Reset ─────────────────────────────────────────────────────
            NekoButton {
                objectName: "text-panel-reset"
                Layout.fillWidth: true
                visible: root.showReset
                text: qsTr("Reset text style")
                iconName: "rotate"
                variant: "secondary"
                enabled: root.controlsEnabled
                onClicked: {
                    root.reset()
                    root.resetRequested()
                }
            }

            Text {
                objectName: "text-panel-hint"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.theme.muted
                font.pixelSize: Theme.fontSmall
                text: qsTr("Click the image to place text. Double-click an existing text object to edit it.")
            }
        }
    }
}
