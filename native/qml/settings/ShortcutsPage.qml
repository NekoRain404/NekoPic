import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    ShortcutsPage — editable keyboard-shortcut surface.

    The catalogue mirrors Main.qml's Action ids. The page receives only the
    current override map and reports persistence requests through signals, so
    SettingsDialog/AppDialogs remain the single integration point.

    Pressing a combination captures it immediately; Esc cancels the popup and
    Delete restores the action's built-in sequence. Duplicate combinations are
    rejected locally and also by SettingsManager, so two Actions can never end
    up with the same active shortcut.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-shortcuts"

    property bool busy: false
    property var shortcuts: ({})
    /*! SettingsManager instance used for portable-text key conversion. */
    property var shortcutService: null
    property string errorText: ""

    property string _captureKey: ""
    property string _capturePreview: ""

    signal shortcutChangeRequested(string key, string sequence)
    signal shortcutResetRequested(string key)
    signal shortcutsResetRequested()

    readonly property var groups: [
        {
            id: "file",
            title: qsTr("File"),
            actions: [
                { key: "open", label: qsTr("Open image…"), fallback: "Ctrl+O" },
                { key: "save", label: qsTr("Save"), fallback: "Ctrl+S" },
                { key: "saveAs", label: qsTr("Save as…"), fallback: "Ctrl+Shift+S" }
            ]
        },
        {
            id: "edit",
            title: qsTr("Edit"),
            actions: [
                { key: "undo", label: qsTr("Undo"), fallback: "Ctrl+Z" },
                { key: "redo", label: qsTr("Redo"), fallback: "Ctrl+Shift+Z" },
                { key: "copy", label: qsTr("Copy image"), fallback: "Ctrl+Shift+C" }
            ]
        },
        {
            id: "view",
            title: qsTr("View"),
            actions: [
                { key: "zoomIn", label: qsTr("Zoom in"), fallback: "Ctrl+=" },
                { key: "zoomOut", label: qsTr("Zoom out"), fallback: "Ctrl+-" },
                { key: "fit", label: qsTr("Fit to window"), fallback: "Ctrl+0" },
                { key: "actual", label: qsTr("Actual size (100%)"), fallback: "Ctrl+1" },
                { key: "commandPalette", label: qsTr("Command palette…"), fallback: "Ctrl+K" }
            ]
        },
        {
            id: "tools",
            title: qsTr("Tools"),
            actions: [
                { key: "brush", label: qsTr("Brush"), fallback: "B" },
                { key: "shape", label: qsTr("Shapes"), fallback: "U" },
                { key: "pan", label: qsTr("Pan"), fallback: "H" },
                { key: "select", label: qsTr("Select"), fallback: "V" },
                { key: "text", label: qsTr("Add text"), fallback: "T" },
                { key: "eyedropper", label: qsTr("Eyedropper"), fallback: "I" },
                { key: "crop", label: qsTr("Crop"), fallback: "C" }
            ]
        },
        {
            id: "help",
            title: qsTr("Help"),
            actions: [
                { key: "settings", label: qsTr("Preferences…"), fallback: "Ctrl+," }
            ]
        }
    ]

    readonly property var flatActions: {
        const result = []
        for (let g = 0; g < groups.length; ++g) {
            const group = groups[g]
            for (let a = 0; a < group.actions.length; ++a) {
                const action = group.actions[a]
                result.push({
                    key: action.key,
                    label: action.label,
                    fallback: action.fallback,
                    group: group.title
                })
            }
        }
        return result
    }

    readonly property int customCount: {
        let count = 0
        for (let i = 0; i < flatActions.length; ++i) {
            const key = flatActions[i].key
            const value = shortcuts ? shortcuts[key] : undefined
            if (value !== undefined && String(value).length > 0)
                ++count
        }
        return count
    }

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function defaultFor(key) {
        for (let i = 0; i < flatActions.length; ++i) {
            if (flatActions[i].key === key)
                return flatActions[i].fallback
        }
        return ""
    }

    function hasOverride(key) {
        const value = shortcuts ? shortcuts[key] : undefined
        return value !== undefined && String(value).length > 0
    }

    function effectiveShortcut(key) {
        if (hasOverride(key))
            return String(shortcuts[key])
        return defaultFor(key)
    }

    function conflicts(sequence, exceptKey) {
        const normalised = String(sequence).trim().toLowerCase()
        if (normalised.length === 0)
            return false
        for (let i = 0; i < flatActions.length; ++i) {
            const key = flatActions[i].key
            if (key === exceptKey)
                continue
            if (effectiveShortcut(key).trim().toLowerCase() === normalised)
                return true
        }
        return false
    }

    function _portableKeySequence(key, modifiers) {
        if (modifiers === undefined || modifiers === null)
            modifiers = 0
        const parts = []
        if (modifiers & Qt.ControlModifier) parts.push("Ctrl")
        if (modifiers & Qt.AltModifier) parts.push("Alt")
        if (modifiers & Qt.ShiftModifier) parts.push("Shift")
        if (modifiers & Qt.MetaModifier) parts.push("Meta")

        let text = ""
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            text = String.fromCharCode(key)
        else if (key >= Qt.Key_0 && key <= Qt.Key_9)
            text = String.fromCharCode(key)
        else {
            switch (key) {
            case Qt.Key_Comma: text = ","; break
            case Qt.Key_Period: text = "."; break
            case Qt.Key_Slash: text = "/"; break
            case Qt.Key_Semicolon: text = ";"; break
            case Qt.Key_Apostrophe: text = "'"; break
            case Qt.Key_BracketLeft: text = "["; break
            case Qt.Key_BracketRight: text = "]"; break
            case Qt.Key_Backslash: text = "\\"; break
            case Qt.Key_Minus: text = "-"; break
            case Qt.Key_Equal: text = "="; break
            case Qt.Key_Plus: text = "+"; break
            case Qt.Key_Space: text = "Space"; break
            case Qt.Key_Tab: text = "Tab"; break
            case Qt.Key_Return: text = "Return"; break
            case Qt.Key_Enter: text = "Enter"; break
            case Qt.Key_Backspace: text = "Backspace"; break
            case Qt.Key_Delete: text = "Del"; break
            case Qt.Key_Home: text = "Home"; break
            case Qt.Key_End: text = "End"; break
            case Qt.Key_PageUp: text = "PgUp"; break
            case Qt.Key_PageDown: text = "PgDown"; break
            case Qt.Key_Up: text = "Up"; break
            case Qt.Key_Down: text = "Down"; break
            case Qt.Key_Left: text = "Left"; break
            case Qt.Key_Right: text = "Right"; break
            case Qt.Key_F1: text = "F1"; break
            case Qt.Key_F2: text = "F2"; break
            case Qt.Key_F3: text = "F3"; break
            case Qt.Key_F4: text = "F4"; break
            case Qt.Key_F5: text = "F5"; break
            case Qt.Key_F6: text = "F6"; break
            case Qt.Key_F7: text = "F7"; break
            case Qt.Key_F8: text = "F8"; break
            case Qt.Key_F9: text = "F9"; break
            case Qt.Key_F10: text = "F10"; break
            case Qt.Key_F11: text = "F11"; break
            case Qt.Key_F12: text = "F12"; break
            default: break
            }
        }
        if (text.length === 0)
            return ""
        parts.push(text)
        return parts.join("+")
    }

    /*! Uses SettingsManager in the app; the JS fallback keeps standalone tests usable. */
    function keySequence(key, modifiers) {
        if (shortcutService && typeof shortcutService.keySequence === "function") {
            const result = shortcutService.keySequence(key, modifiers)
            if (result !== undefined && result !== null && String(result).length > 0)
                return String(result)
        }
        return page._portableKeySequence(key, modifiers)
    }

    function openCapture(key) {
        page.errorText = ""
        page._captureKey = key
        page._capturePreview = effectiveShortcut(key)
        capturePopup.open()
    }

    function closeCapture() {
        capturePopup.close()
    }

    function applyShortcut(key, sequence) {
        if (key.length === 0)
            return false
        if (sequence.length === 0) {
            page.errorText = ""
            page.shortcutChangeRequested(key, "")
            return true
        }
        if (conflicts(sequence, key)) {
            page.errorText = qsTr("%1 is already assigned to another action.").arg(sequence)
            return false
        }
        page.errorText = ""
        page.shortcutChangeRequested(key, sequence)
        return true
    }

    /*!
        Handles one key press from the capture popup. Split out so tests can
        exercise the same path without depending on compositor focus.
        Returns true when the event was consumed.
    */
    function captureKey(key, modifiers) {
        if (key === Qt.Key_Escape) {
            page.errorText = ""
            page.closeCapture()
            return true
        }
        if (key === Qt.Key_Delete || key === Qt.Key_Backspace) {
            page.errorText = ""
            page.shortcutChangeRequested(page._captureKey, "")
            page.closeCapture()
            return true
        }
        // Ignore modifier keys pressed on their own.
        if (key === Qt.Key_Control || key === Qt.Key_Shift || key === Qt.Key_Alt
                || key === Qt.Key_Meta || key === Qt.Key_AltGr)
            return true

        const sequence = page.keySequence(key, modifiers)
        if (sequence.length === 0)
            return false
        page._capturePreview = sequence
        if (page.applyShortcut(page._captureKey, sequence))
            page.closeCapture()
        return true
    }

    NekoSectionHeader {
        objectName: "settings-section-shortcuts"
        Layout.fillWidth: true
        text: qsTr("Shortcuts")
        eyebrow: true
        showDivider: true
    }

    Text {
        Layout.fillWidth: true
        text: qsTr("Select Edit, then press a key combination. Changes apply immediately and are saved automatically.")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: page.groups

        delegate: ColumnLayout {
            id: groupColumn
            required property var modelData

            objectName: "settings-shortcut-group-" + modelData.id
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            NekoSectionHeader {
                Layout.fillWidth: true
                text: groupColumn.modelData.title
                eyebrow: true
                showDivider: true
            }

            Repeater {
                model: groupColumn.modelData.actions

                delegate: RowLayout {
                    id: shortcutRow
                    required property var modelData

                    objectName: "settings-shortcut-row-" + modelData.key
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Text {
                        Layout.fillWidth: true
                        text: shortcutRow.modelData.label
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        implicitWidth: shortcutLabel.implicitWidth + Theme.spacingMd * 2
                        implicitHeight: Theme.iconSizeLg
                        radius: Theme.radiusXs
                        color: Theme.background
                        border.width: Theme.borderWidth
                        border.color: page.hasOverride(shortcutRow.modelData.key)
                                      ? Theme.accent : Theme.border

                        Text {
                            id: shortcutLabel
                            objectName: "settings-shortcut-value-" + shortcutRow.modelData.key
                            anchors.centerIn: parent
                            text: page.effectiveShortcut(shortcutRow.modelData.key)
                            color: page.hasOverride(shortcutRow.modelData.key)
                                   ? Theme.accent : Theme.textSecondary
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    NekoButton {
                        objectName: "settings-shortcut-edit-" + shortcutRow.modelData.key
                        text: qsTr("Edit")
                        variant: "secondary"
                        enabled: !page.busy
                        accessibleName: qsTr("Edit shortcut for %1")
                                        .arg(shortcutRow.modelData.label)
                        onClicked: page.openCapture(shortcutRow.modelData.key)
                    }

                    NekoButton {
                        objectName: "settings-shortcut-reset-" + shortcutRow.modelData.key
                        text: qsTr("Reset")
                        variant: "ghost"
                        visible: page.hasOverride(shortcutRow.modelData.key)
                        enabled: !page.busy
                        accessibleName: qsTr("Reset shortcut for %1")
                                        .arg(shortcutRow.modelData.label)
                        onClicked: {
                            page.errorText = ""
                            page.shortcutResetRequested(shortcutRow.modelData.key)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.borderWidth
        color: Theme.separator
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: page.customCount === 0
                  ? qsTr("All shortcuts use their built-in keys.")
                  : qsTr("%1 custom shortcut(s).").arg(page.customCount)
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.WordWrap
        }

        NekoButton {
            objectName: "settings-shortcuts-reset-all"
            text: qsTr("Reset all")
            variant: "secondary"
            enabled: !page.busy && page.customCount > 0
            accessibleName: qsTr("Reset all shortcuts")
            onClicked: {
                page.errorText = ""
                page.shortcutsResetRequested()
            }
        }
    }

    Text {
        objectName: "settings-shortcut-error"
        Layout.fillWidth: true
        visible: page.errorText.length > 0
        text: page.errorText
        color: Theme.danger
        font.pixelSize: Theme.fontCaption
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }

    Popup {
        id: capturePopup
        objectName: "shortcut-capture"
        anchors.centerIn: Overlay.overlay
        width: 340
        height: 200
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        padding: Theme.spacingLg

        background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.surfaceRaised
            border.width: Theme.borderWidth
            border.color: Theme.border
        }

        contentItem: FocusScope {
            id: captureFocus
            focus: true

            Keys.onPressed: function(event) {
                if (page.captureKey(event.key, event.modifiers))
                    event.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacingMd

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Press a shortcut")
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontWeightDemiBold
                }

                Text {
                    objectName: "shortcut-capture-preview"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: page._capturePreview
                    color: Theme.accent
                    font.pixelSize: Theme.fontHeadline
                    font.weight: Theme.fontWeightMedium
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Delete clears the custom shortcut · Esc cancels")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    visible: page.errorText.length > 0
                    text: page.errorText
                    color: Theme.danger
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        onOpened: captureFocus.forceActiveFocus()
        onClosed: captureFocus.focus = false
    }
}
