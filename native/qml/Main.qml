import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import "UI"
import "shell"
import "dialogs"
import "panels"
import "filters"
import "objects"

ApplicationWindow {
    id: window
    width: 1440; height: 900; minimumWidth: 860; minimumHeight: 600
    visible: true
    title: (editor.hasImage ? editor.fileName + (editor.dirty ? " *" : "") + " - " : "") + "NekoPic"
    property bool darkTheme: true
    property bool followSystemTheme: false
    readonly property bool systemDark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    // Letter shortcuts must not fire while the user is typing in a modal.
    readonly property bool blockingModal: commandPalette.opened
        || exportDialog.opened || resizeDialog.opened || canvasSizeDialog.opened
        || shortcutsDialog.opened || aboutDialog.opened || settingsDialog.opened
        || discardDialog.opened || errorDialog.opened || foregroundColorDialog.visible
        || recoveryDialog.opened
    property bool discardConfirmed: false
    property bool saveBeforePending: false
    property string startupTool: ""
    property var textEditInfo: ({})
    property point pendingTextAnchor: Qt.point(-1, -1)
    property bool closingRequested: false
    property url pendingImage
    property url pendingExportUrl
    property url lastFolder: ""
    property string activeTool: "adjust"
    // Temporary keyboard overrides. They never change activeTool, so the tool
    // the user had selected is restored naturally on release.
    property bool spacePanHeld: false
    property bool compareHeld: false
    // A focused TextInput/TextEdit must keep Space and M for editing. TextInput
    // exposes an integer cursorPosition; overlays may expose a point with the
    // same name, so the type check matters.
    readonly property bool textInputFocused: activeFocusItem !== null
        && typeof activeFocusItem.cursorPosition === "number"
    readonly property bool canvasShortcutsEnabled: editor.hasImage && !editor.busy
        && !blockingModal && !textInputFocused
    readonly property bool spacePanActive: spacePanHeld && activeTool !== "pan" && !editor.busy
    // Hints shown in the canvas bottom bar while a tool is active.
    readonly property string activeToolHint: {
        if (!editor.hasImage) return ""
        if (spacePanActive) return qsTr("拖动画布")
        switch (activeTool) {
        case "select": return qsTr("点选对象 · Shift 多选 · Delete 删除")
        case "brush": return qsTr("拖动绘制 · 一笔一次撤销")
        case "text": return qsTr("点击画布放置文字")
        case "shapes": return shapePanel.shapeKind === "polygon"
                ? qsTr("点击顶点 · Enter 闭合")
                : qsTr("拖动绘制 · Shift 约束比例/角度")
        case "mosaic": return qsTr("拖动选择区域")
        case "crop": return qsTr("拖动边缘 · Enter 应用 / Esc 取消")
        case "pan": return qsTr("拖动画布")
        case "eye": return qsTr("点击取色 · Esc 取消")
        default: return ""
        }
    }
    property string transientStatus: ""
    property bool reduceMotion: false
    function showStatus(message) { transientStatus = message; statusTimer.restart() }
    function toolLabel(tool) {
        switch (tool) {
        case "select": return qsTr("Select")
        case "pan": return qsTr("Pan")
        case "adjust": return qsTr("Adjust")
        case "filters": return qsTr("Filters")
        case "brush": return qsTr("Brush")
        case "text": return qsTr("Text")
        case "shapes": return qsTr("Shapes")
        case "mosaic": return qsTr("Mosaic")
        case "eye": return qsTr("Eyedropper")
        case "crop": return qsTr("Crop")
        default: return ""
        }
    }
    /*! Objects currently in the document, refreshed from documentChanged. */
    property int objectCount: 0
    property bool _syncingForeground: false
    // True from drag start until the asynchronous object move commits, so the
    // live crop survives exactly until the new document image is available.
    property bool _awaitingMovePreview: false
    function refreshObjectCount() {
        if (typeof editor === "undefined" || editor === null) {
            objectCount = 0
            return
        }
        if (typeof editor.objectIds === "function") {
            const ids = editor.objectIds()
            objectCount = ids ? ids.length : 0
        } else {
            objectCount = editor.hasObjects ? 1 : 0
        }
    }
    // The shared foreground is the default ink for brush, text and shape
    // stroke. Each panel keeps its own picker: choosing there updates the
    // shared value, and the rail swatch pushes back to every drawing tool.
    function applyForegroundToTools() {
        if (!brushPanel || !textPanel || !shapePanel) return
        _syncingForeground = true
        if (!Qt.colorEqual(brushPanel.color, foregroundColor))
            brushPanel.color = foregroundColor
        if (!Qt.colorEqual(textPanel.color, foregroundColor))
            textPanel.color = foregroundColor
        if (!Qt.colorEqual(shapePanel.strokeColor, foregroundColor))
            shapePanel.strokeColor = foregroundColor
        _syncingForeground = false
    }
    function syncPersistedToolSettings() {
        brushPanel.diameter = toolSettings.brushDiameter
        brushPanel.inkOpacity = toolSettings.brushOpacity
        brushPanel.softness = toolSettings.brushSoftness
        applyForegroundToTools()
    }
    /*! Save destination for the edited export file name. */
    function exportDestinationUrl() {
        const base = window.pendingExportUrl
        if (!base || String(base).length === 0)
            return base
        const name = exportDialog.fileName.trim()
        if (name.length === 0 || /[\\/]/.test(name)
                || name === "." || name === "..")
            return base
        let finalName = name
        if (finalName.lastIndexOf(".") < 0 && exportDialog.formatSuffix.length > 0)
            finalName += "." + exportDialog.formatSuffix
        const text = String(base)
        const slash = text.lastIndexOf("/")
        const directory = slash >= 0 ? text.substring(0, slash + 1) : ""
        return directory + encodeURIComponent(finalName)
    }
    function beginSpacePan() {
        if (!canvasShortcutsEnabled || spacePanHeld) return false
        spacePanHeld = true
        showStatus(toolLabel("pan"))
        return true
    }
    function endSpacePan() {
        if (!spacePanHeld) return
        spacePanHeld = false
        if (editor.hasImage && !blockingModal) showStatus(toolLabel(activeTool))
    }
    function beginCompareHold() {
        if (!editor.hasImage || blockingModal || textInputFocused || compareHeld) return false
        compareHeld = true
        canvas.compareActive = true
        showStatus(qsTranslate("EditorCanvas", "ORIGINAL"))
        return true
    }
    function endCompareHold() {
        if (!compareHeld) return
        compareHeld = false
        canvas.compareActive = false
        if (editor.hasImage && !blockingModal) showStatus(qsTranslate("EditorCanvas", "WORKSPACE"))
    }
    function resetInteractionOverrides() {
        spacePanHeld = false
        compareHeld = false
        if (canvas) canvas.compareActive = false
    }
    function keyboardScopeContains(item) {
        while (item !== null && item !== undefined) {
            if (item === shellLayout) return true
            item = item.parent
        }
        return false
    }
    // Tools without a focusable overlay (mosaic) and closed dialogs can leave
    // focus on the window root. Without this, Space/M/Escape would never reach
    // the keyboard scope, so fall back to it once the current transition ends.
    function restoreKeyboardFocus() {
        if (!shellLayout) return
        if (!keyboardScopeContains(activeFocusItem))
            shellLayout.forceActiveFocus(Qt.OtherFocusReason)
    }
    function exitActiveTool() {
        if (activeTool === "adjust") return false
        if (canvas) {
            canvas.cancelPendingGesture()
            if (activeTool === "select") canvas.clearSelection()
        }
        activeTool = "adjust"
        showStatus(toolLabel("adjust"))
        return true
    }
    // One path for every "open another image" entry point so a dirty document
    // always asks for confirmation exactly like the Open dialog does.
    function requestOpen(url) {
        if (editor.busy || url === undefined || url === null || String(url).length === 0)
            return false
        if (editor.dirty) {
            pendingImage = url
            closingRequested = false
            discardDialog.open()
        } else {
            editor.openImage(url)
        }
        return true
    }
    function handleCanvasKeyPress(event) {
        // Auto-repeat must not toggle hold state on and off.
        if (event.isAutoRepeat) {
            if ((event.key === Qt.Key_Space && spacePanHeld)
                    || (event.key === Qt.Key_M && compareHeld)) {
                event.accepted = true
                return
            }
        }
        if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier) {
            if (beginSpacePan()) event.accepted = true
            return
        }
        if (event.key === Qt.Key_M && event.modifiers === Qt.NoModifier) {
            if (beginCompareHold()) event.accepted = true
            return
        }
        if (event.key === Qt.Key_Escape) {
            if (blockingModal || textInputFocused) return
            if (exitActiveTool()) event.accepted = true
        }
    }
    function handleCanvasKeyRelease(event) {
        if (event.key === Qt.Key_Space) {
            if (spacePanHeld) { endSpacePan(); event.accepted = true }
            return
        }
        if (event.key === Qt.Key_M) {
            if (compareHeld) { endCompareHold(); event.accepted = true }
        }
    }
    function applySettings() {
        if (typeof settings === "undefined") return
        const mode = settings.themeMode
        window.followSystemTheme = mode === "system"
        if (mode !== "system") window.darkTheme = mode === "dark"
        window.reduceMotion = settings.reduceMotion
        editor.exportQuality = settings.exportQuality
        editor.jpegBackground = settings.jpegBackground
        if (typeof recovery !== "undefined" && recovery !== null)
            recovery.autosaveEnabled = settings.recoveryEnabled
        // The persisted startup tool applies until a command-line --tool
        // override (set after component creation) replaces it.
        if (settings.startupTool.length > 0)
            window.startupTool = settings.startupTool
        if (typeof language !== "undefined" && settings.locale.length > 0
                && language.locale !== settings.locale)
            language.setLanguage(settings.locale)
    }
    // A recovery snapshot only makes sense before a document exists. If a
    // command-line image is still decoding, wait for it and then re-check, so
    // an explicitly opened file wins over the crash prompt.
    function maybeShowRecovery() {
        if (typeof recovery === "undefined" || recovery === null) return
        if (!recovery.hasRecovery || editor.hasImage) return
        if (editor.busy) {
            recoveryCheckTimer.restart()
            return
        }
        recoveryDialog.open()
    }
    function openSettings() {
        if (typeof settings !== "undefined") {
            settingsDialog.themeMode = settings.themeMode
            settingsDialog.reduceMotion = settings.reduceMotion
            settingsDialog.gpuPreviewEnabled = settings.gpuPreviewEnabled
            settingsDialog.exportQuality = settings.exportQuality
            settingsDialog.jpegBackground = settings.jpegBackground
            settingsDialog.localeId = settings.locale
            settingsDialog.confirmOnClose = settings.confirmOnClose
            settingsDialog.showCheckerboard = settings.showCheckerboard
            settingsDialog.recoveryEnabled = settings.recoveryEnabled
            settingsDialog.startupTool = settings.startupTool
        } else {
            settingsDialog.themeMode = window.followSystemTheme ? "system"
                                     : window.darkTheme ? "dark" : "light"
            settingsDialog.reduceMotion = window.reduceMotion
            settingsDialog.localeId = typeof language !== "undefined" ? language.locale : "zh_CN"
        }
        settingsDialog.open()
    }
    Component.onCompleted: {
        applySettings()
        syncPersistedToolSettings()
        refreshObjectCount()
        Qt.callLater(window.maybeShowRecovery)
    }
    function applyTextInfo(info) {
        textPanel.editId = info.id
        textPanel.text = info.text
        textPanel.fontFamily = info.fontFamily
        textPanel.fontSize = info.fontSize
        textPanel.alignment = info.alignment
        textPanel.outline = Number(info.outlineWidth) > 0
        textPanel.color = info.color
        window.textEditInfo = info
    }
    function refreshTextPanel() {
        const ids = canvas.selectionIds
        if (ids && ids.length === 1) {
            const info = editor.textInfo(ids[0])
            if (info && info.id !== undefined) {
                applyTextInfo(info)
                return
            }
        }
        textPanel.editId = 0
        window.textEditInfo = ({})
    }
    function textPanelArgs() {
        const info = window.textEditInfo
        return {
            text: textPanel.text,
            x: info.x,
            y: info.y,
            fontFamily: textPanel.fontFamily,
            fontWeight: textPanel.outline ? 700 : 400,
            fontSize: textPanel.fontSize,
            color: textPanel.color,
            alignment: textPanel.alignment,
            outlineColor: textPanel.outline ? "#151718" : "transparent",
            outlineWidth: textPanel.outline ? 2 : 0,
            lineHeight: info.lineHeight !== undefined ? info.lineHeight : 1.0,
            padding: info.padding !== undefined ? info.padding : 4.0
        }
    }
    function commitTextUpdate() {
        const info = window.textEditInfo
        if (!info || info.id === undefined || editor.busy) return
        const args = textPanelArgs()
        editor.updateText(info.id, args.text, args.x, args.y, args.fontFamily,
                          args.fontWeight, args.fontSize, args.color, args.alignment,
                          args.outlineColor, args.outlineWidth, args.lineHeight, args.padding)
    }
    function createTextAt(imageX, imageY) {
        if (!editor.hasImage || editor.busy) return
        const content = textPanel.text.trim().length > 0 ? textPanel.text : qsTr("Text")
        window.pendingTextAnchor = Qt.point(imageX, imageY)
        editor.addTextStyled(content, imageX, imageY, textPanel.fontFamily,
                             textPanel.outline ? 700 : 400, textPanel.fontSize,
                             textPanel.color, textPanel.alignment,
                             textPanel.outline ? "#151718" : "transparent",
                             textPanel.outline ? 2 : 0, 1.0, 4.0)
    }
    function formatSupportsQuality(id) {
        return ["jpeg", "webp", "avif", "heic", "heif", "jxl", "tiff", "png"].indexOf(id) >= 0
    }
    function applyCrop(area) {
        if (!editor.hasImage || editor.busy) return
        editor.cropImage(area)
        activeTool = "adjust"
    }
    onActiveToolChanged: {
        if (activeTool === "adjust" || activeTool === "filters")
            inspector.currentTab = activeTool === "filters" ? 1 : 0
        if (canvas) canvas.cancelPendingGesture()
        if (activeTool === "text") refreshTextPanel()
        showStatus(toolLabel(activeTool))
        Qt.callLater(window.restoreKeyboardFocus)
    }
    onBlockingModalChanged: {
        if (blockingModal) resetInteractionOverrides()
        else Qt.callLater(window.restoreKeyboardFocus)
    }
    onTextInputFocusedChanged: if (textInputFocused) resetInteractionOverrides()
    onActiveChanged: if (!active) resetInteractionOverrides()
    onClosing: function(close) {
        const shouldConfirm = typeof settings === "undefined" || settings.confirmOnClose
        if (editor.busy || (editor.dirty && shouldConfirm && !discardConfirmed)) {
            close.accepted = false
            if (!editor.busy) { closingRequested = true; discardDialog.open() }
            return
        }
        // Normal exit with nothing unsaved, or an explicit discard, must not
        // resurrect the session on the next launch.
        if (typeof recovery !== "undefined" && recovery !== null
                && (!editor.dirty || discardConfirmed))
            recovery.discardRecovery()
    }
    Settings { category: "ui"; property alias lastFolder: window.lastFolder }
    Settings {
        id: toolSettings
        category: "tools"
        property color foregroundColor: "#eeb99a"
        property real brushDiameter: 24
        property real brushOpacity: 100
        property real brushSoftness: 0
    }
    /*! Shared drawing ink; persisted between sessions. */
    property alias foregroundColor: toolSettings.foregroundColor
    onForegroundColorChanged: applyForegroundToTools()
    Binding { target: Theme; property: "dark"; value: window.followSystemTheme ? window.systemDark : window.darkTheme }
    Binding { target: Theme; property: "reduceMotion"; value: window.reduceMotion }
    color: theme.background
    palette.window: theme.panel
    palette.windowText: theme.text
    palette.base: theme.background
    palette.text: theme.text
    palette.button: theme.panel
    palette.buttonText: theme.text
    palette.highlight: theme.accent
    palette.highlightedText: "#202524"

    QtObject {
        id: theme
        readonly property color background: Theme.background
        readonly property color panel: Theme.panel
        readonly property color canvas: Theme.canvas
        readonly property color raised: Theme.surfaceRaised
        readonly property color hover: Theme.hover
        readonly property color text: Theme.textPrimary
        readonly property color muted: Theme.textSecondary
        readonly property color border: Theme.border
        readonly property color accent: Theme.accent
        readonly property color accentInk: Theme.accentInk
    }

    component Icon: NekoIcon {
        property color ink: Theme.textSecondary
        color: ink
    }
    component CommandButton: NekoButton {
        id: command
        property bool primary: false
        variant: primary ? "primary" : "secondary"
    }

    Action { id: openAction; text: qsTr("Open image…"); shortcut: StandardKey.Open; enabled: !editor.busy; onTriggered: openDialog.open() }
    Action { id: saveAction; text: qsTr("Save"); shortcut: StandardKey.Save; enabled: editor.hasImage && !editor.busy; onTriggered: editor.saveImage() }
    Action { id: saveAsAction; text: qsTr("Save as…"); shortcut: StandardKey.SaveAs; enabled: editor.hasImage && !editor.busy; onTriggered: saveDialog.open() }
    Action { id: settingsAction; text: qsTr("Preferences…"); shortcut: "Ctrl+,"; onTriggered: window.openSettings() }
    Action { id: commandPaletteAction; text: qsTr("Command palette…"); shortcut: "Ctrl+K"; onTriggered: commandPalette.opened ? commandPalette.close() : commandPalette.open() }
    Action { id: copyAction; text: qsTr("Copy image"); shortcut: "Ctrl+Shift+C"; enabled: editor.hasImage && !editor.busy; onTriggered: { editor.copyImageToClipboard(); window.showStatus(qsTr("Copied to clipboard")) } }
    Action { id: undoAction; text: qsTr("Undo"); shortcut: StandardKey.Undo; enabled: editor.canUndo && !editor.busy; onTriggered: { editor.undo(); window.showStatus(qsTr("Undone")) } }
    Action { id: redoAction; text: qsTr("Redo"); shortcut: StandardKey.Redo; enabled: editor.canRedo && !editor.busy; onTriggered: { editor.redo(); window.showStatus(qsTr("Redone")) } }
    Action { id: rotateRightAction; text: qsTr("Rotate clockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateClockwise() }
    Action { id: rotateLeftAction; text: qsTr("Rotate counterclockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateCounterClockwise() }
    Action { id: flipHorizontalAction; text: qsTr("Flip horizontally"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipHorizontal() }
    Action { id: flipVerticalAction; text: qsTr("Flip vertically"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipVertical() }
    Action { id: resizeImageAction; text: qsTr("Resize image…"); enabled: editor.hasImage && !editor.busy; onTriggered: resizeDialog.open() }
    Action { id: canvasSizeAction; text: qsTr("Canvas size…"); enabled: editor.hasImage && !editor.busy; onTriggered: canvasSizeDialog.open() }
    Action { id: shortcutsAction; text: qsTr("Keyboard shortcuts"); shortcut: "F1"; onTriggered: shortcutsDialog.open() }
    Action { id: brushAction; text: qsTr("Brush"); shortcut: "B"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "brush" }
    Action { id: shapeAction; text: qsTr("Shapes"); shortcut: "U"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "shapes" }
    Action { id: panAction; text: qsTr("Pan"); shortcut: "H"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "pan" }
    Action { id: selectAction; text: qsTr("Select"); shortcut: "V"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "select" }
    Action { id: textAction; text: qsTr("Add text"); shortcut: "T"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "text" }
    Action { id: eyedropperAction; text: qsTr("Eyedropper"); shortcut: "I"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "eye" }
    Action { id: cropAction; text: qsTr("Crop"); shortcut: "C"; enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "crop" }
    Action { id: zoomInAction; text: qsTr("Zoom in"); shortcut: "Ctrl+="; enabled: editor.hasImage; onTriggered: canvas.changeZoom(1.2) }
    Action { id: zoomOutAction; text: qsTr("Zoom out"); shortcut: "Ctrl+-"; enabled: editor.hasImage; onTriggered: canvas.changeZoom(1 / 1.2) }
    Action { id: fitAction; text: qsTr("Fit to window"); shortcut: "Ctrl+0"; enabled: editor.hasImage; onTriggered: canvas.fitImage() }
    Action { id: actualAction; text: qsTr("Actual size (100%)"); shortcut: "Ctrl+1"; enabled: editor.hasImage; onTriggered: canvas.actualSize() }
    FileDialog {
        id: openDialog; title: qsTr("Open image"); fileMode: FileDialog.OpenFile
        currentFolder: window.lastFolder.toString().length > 0 ? window.lastFolder
                : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: [qsTr("Images") + " (" + editor.readableImagePatterns.join(" ") + ")", qsTr("All files (*)")]
        onAccepted: {
            window.lastFolder = currentFolder
            window.requestOpen(selectedFile)
        }
    }
    FileDialog {
        id: saveDialog; title: qsTr("Save image as"); fileMode: FileDialog.SaveFile
        currentFolder: window.lastFolder.toString().length > 0 ? window.lastFolder
                : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        readonly property var formats: (typeof editor !== "undefined" && editor.writableFormats)
                                       ? editor.writableFormats : [{ id: "png", label: "PNG image",
                                                                     suffix: "png", patterns: ["*.png"] }]
        readonly property int selectedFormat: selectedNameFilter.index >= 0
                                              && selectedNameFilter.index < formats.length
                                              ? selectedNameFilter.index : 0
        nameFilters: formats.map(function(format) {
            return qsTr(format.label) + " (" + format.patterns.join(" ") + ")"
        })
        defaultSuffix: formats[selectedFormat].suffix
        onAccepted: {
            window.lastFolder = currentFolder
            const format = formats[selectedFormat]
            window.pendingExportUrl = selectedFile
            exportDialog.formatId = format.id
            exportDialog.formatLabel = format.label
            exportDialog.formatSuffix = format.suffix
            exportDialog.fileName = selectedFile.toString().split("/").pop()
            exportDialog.supportsQuality = window.formatSupportsQuality(format.id)
            exportDialog.initialQuality = editor.exportQuality >= 0 ? editor.exportQuality : 90
            exportDialog.initialBackground = editor.jpegBackground
            exportDialog.previewUrl = editor.imageUrl
            exportDialog.previewWidth = editor.imageWidth
            exportDialog.previewHeight = editor.imageHeight
            exportDialog.open()
        }
        onRejected: if (window.saveBeforePending) window.saveBeforePending = false
    }
    Menu {
        id: transformMenu
        objectName: "transformMenu"
        MenuItem { objectName: "transform-rotate-left"; action: rotateLeftAction }
        MenuItem { objectName: "transform-rotate-right"; action: rotateRightAction }
        MenuSeparator { }
        MenuItem { objectName: "transform-flip-horizontal"; action: flipHorizontalAction }
        MenuItem { objectName: "transform-flip-vertical"; action: flipVerticalAction }
    }
    ColorDialog {
        id: foregroundColorDialog
        objectName: "foregroundColorDialog"
        title: qsTr("Foreground colour")
        selectedColor: window.foregroundColor
        onAccepted: window.foregroundColor = selectedColor
    }
    Dialog {
        id: errorDialog; objectName: "errorDialog"
        title: qsTr("Unable to complete operation"); modal: true
        anchors.centerIn: parent; standardButtons: Dialog.Ok
        onClosed: editor.clearError()
        Label { text: editor.errorMessage; wrapMode: Text.WordWrap; width: 360; color: theme.text }
    }
    Dialog {
        id: discardDialog; objectName: "discardDialog"
        title: qsTr("Save changes before continuing?"); modal: true
        anchors.centerIn: parent; standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        onAccepted: {
            window.saveBeforePending = true
            if (editor.hasPath) editor.saveImage()
            else saveDialog.open()
        }
        onDiscarded: {
            if (window.closingRequested) {
                window.discardConfirmed = true
                window.close()
            } else {
                editor.openImageDiscardingChanges(window.pendingImage)
            }
        }
        Label { text: qsTr("Your unsaved changes will be lost."); color: theme.text; wrapMode: Text.WordWrap; width: 340 }
    }
    NekoDialog {
        id: aboutDialog
        objectName: "aboutDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("About NekoPic")
        acceptText: qsTr("Close")
        showCloseButton: true
        onAccepted: close()
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Label {
                text: "NekoPic " + Qt.application.version
                color: Theme.textPrimary
                font.pixelSize: Theme.fontTitle
                font.weight: Theme.fontWeightDemiBold
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("A local-first desktop photo editor. Your photos stay on this device.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontBody
            }
            Label {
                text: "Qt " + Qt.application.qtVersion + " · Linux"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }
    }
    RecoveryDialog {
        id: recoveryDialog
        objectName: "recoveryDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        sourceName: typeof recovery !== "undefined" && recovery !== null
                    ? recovery.sourceName : ""
        sourcePath: typeof recovery !== "undefined" && recovery !== null
                    ? recovery.sourcePath : ""
        capturedAtText: typeof recovery !== "undefined" && recovery !== null
                        ? recovery.capturedAtText : ""
        imageSizeText: typeof recovery !== "undefined" && recovery !== null
                       ? recovery.imageSizeText : ""
        flattened: typeof recovery !== "undefined" && recovery !== null
                   ? recovery.flattened : true
        onAccepted: if (typeof recovery !== "undefined" && recovery !== null)
                        recovery.restoreRecovery()
        onRejected: if (typeof recovery !== "undefined" && recovery !== null)
                        recovery.discardRecovery()
    }
    // Single-shot retry while a startup image is decoding; avoids spinning the
    // event loop with Qt.callLater.
    Timer {
        id: recoveryCheckTimer
        interval: 120
        repeat: false
        onTriggered: window.maybeShowRecovery()
    }
    ExportDialog {
        id: exportDialog
        objectName: "exportDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        busy: editor.busy
        onExportRequested: function(format, quality, background) {
            editor.exportQuality = quality
            editor.jpegBackground = background
            editor.saveAs(window.exportDestinationUrl(), format)
        }
        onRejected: if (window.saveBeforePending) window.saveBeforePending = false
    }
    ResizeImageDialog {
        id: resizeDialog
        objectName: "resizeImageDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: editor.imageWidth
        imageHeight: editor.imageHeight
        busy: editor.busy
        onResizeRequested: function(width, height) { editor.resizeImage(width, height) }
    }
    CanvasSizeDialog {
        id: canvasSizeDialog
        objectName: "canvasSizeDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: editor.imageWidth
        imageHeight: editor.imageHeight
        busy: editor.busy
        onCanvasResizeRequested: function(width, height, anchor, background) {
            editor.resizeCanvas(width, height, anchor, background)
        }
    }
    SettingsDialog {
        id: settingsDialog
        objectName: "settingsDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        recoveryAvailable: typeof recovery !== "undefined" && recovery !== null
                           && recovery.hasRecovery
        recoverySourceName: typeof recovery !== "undefined" && recovery !== null
                            ? recovery.sourceName : ""
        recoveryCapturedAt: typeof recovery !== "undefined" && recovery !== null
                            ? recovery.capturedAtText : ""
        recoveryImageSize: typeof recovery !== "undefined" && recovery !== null
                           ? recovery.imageSizeText : ""
        formatCapabilities: typeof formatRegistryInfo !== "undefined"
                            ? formatRegistryInfo
                            : ({ readableCount: 0, writableCount: 0 })
        onSettingChanged: function(key, value) {
            if (typeof settings === "undefined") return
            settings[key] = value
            if (key === "themeMode") {
                window.followSystemTheme = value === "system"
                if (value !== "system") window.darkTheme = value === "dark"
            } else if (key === "reduceMotion") {
                window.reduceMotion = value
            } else if (key === "exportQuality") {
                editor.exportQuality = value
            } else if (key === "jpegBackground") {
                editor.jpegBackground = value
            } else if (key === "recoveryEnabled") {
                if (typeof recovery !== "undefined" && recovery !== null)
                    recovery.autosaveEnabled = value
            } else if (key === "startupTool") {
                // Consumed by onImageOpened, so it takes effect the next time
                // a document is opened even if one is already on screen.
                window.startupTool = value
            }
        }
        onLocaleSelected: function(id) {
            if (typeof settings !== "undefined") settings.locale = id
            if (typeof language !== "undefined") language.setLanguage(id)
        }
        onShortcutsRequested: if (!shortcutsDialog.opened) shortcutsDialog.open()
        onRecoveryDiscardRequested: {
            if (typeof recovery !== "undefined" && recovery !== null)
                recovery.discardRecovery()
        }
    }
    ShortcutsDialog {
        id: shortcutsDialog
        objectName: "shortcutsDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
    }
    Connections {
        target: canvas
        function onSelectionIdsChanged() {
            if (window.activeTool === "text") window.refreshTextPanel()
        }
    }
    Connections {
        target: brushPanel
        function onColorChanged() {
            if (!window._syncingForeground) window.foregroundColor = brushPanel.color
        }
        function onDiameterChanged() { toolSettings.brushDiameter = brushPanel.diameter }
        function onInkOpacityChanged() { toolSettings.brushOpacity = brushPanel.inkOpacity }
        function onSoftnessChanged() { toolSettings.brushSoftness = brushPanel.softness }
    }
    Connections {
        target: textPanel
        function onColorChanged() {
            if (!window._syncingForeground) window.foregroundColor = textPanel.color
        }
    }
    Connections {
        target: shapePanel
        function onStrokeColorChanged() {
            if (!window._syncingForeground) window.foregroundColor = shapePanel.strokeColor
        }
    }
    Connections {
        target: editor
        function onErrorChanged() { if (editor.errorMessage.length > 0) errorDialog.open() }
        function onBusyChanged() {
            if (!editor.busy && window._awaitingMovePreview) {
                window._awaitingMovePreview = false
                editor.clearObjectMovePreview()
                canvas.clearMovePreview()
            }
            if (editor.busy || window.pendingTextAnchor.x < 0) return
            const anchor = window.pendingTextAnchor
            window.pendingTextAnchor = Qt.point(-1, -1)
            const id = editor.objectAt(anchor.x, anchor.y)
            if (id !== 0) {
                canvas.setSelectionIds([id])
                // A placed text object is almost always moved or restyled
                // next. Land in Select with the new object already selected so
                // it can be dragged immediately; T returns to adding text.
                window.activeTool = "select"
                window.showStatus(qsTr("Text placed — drag to move"))
            }
        }
        function onImageOpened(url) {
            window.resetInteractionOverrides()
            window.activeTool = window.startupTool.length > 0 ? window.startupTool : "adjust"
            window.startupTool = ""
            window.refreshObjectCount()
        }
        function onDocumentChanged() { window.refreshObjectCount() }
        function onImageSaved() {
            if (!window.saveBeforePending) {
                window.showStatus(qsTr("Image saved"))
                return
            }
            window.saveBeforePending = false
            if (window.closingRequested) {
                window.discardConfirmed = true
                window.close()
            } else if (window.pendingImage) {
                const target = window.pendingImage
                window.pendingImage = ""
                editor.openImage(target)
            }
        }
    }

    menuBar: MenuBar {
        background: Rectangle { color: theme.background }
        contentItem: RowLayout {
            spacing: 0
            RowLayout {
                Layout.leftMargin: 14; Layout.rightMargin: 12; spacing: 7
                Rectangle { width: 21; height: 21; radius: 5; color: theme.accent; Icon { anchors.centerIn: parent; width: 17; height: 17; name: "logo"; ink: theme.accentInk } }
                Label { text: "NekoPic"; color: theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
            Repeater { model: window.menuBar.contentModel }
            Item { Layout.fillWidth: true }
            Rectangle { width: 5; height: 5; radius: 3; color: "#99b4a3" }
            Label { Layout.leftMargin: 7; Layout.rightMargin: 17; text: qsTr("Local editing"); color: theme.muted; font.pixelSize: 10 }
        }
        Menu {
            title: qsTr("File")
            MenuItem { action: openAction }
            Menu {
                objectName: "recentMenu"
                title: qsTr("Open recent")
                enabled: typeof recentFiles !== "undefined" && recentFiles.entries.length > 0
                         && !editor.busy
                Repeater {
                    model: typeof recentFiles !== "undefined" ? recentFiles.entries : []
                    MenuItem {
                        required property var modelData
                        text: modelData.name
                        enabled: !editor.busy
                        onTriggered: window.requestOpen(modelData.url)
                    }
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Clear recent files")
                    enabled: typeof recentFiles !== "undefined" && recentFiles.entries.length > 0
                             && !editor.busy
                    onTriggered: if (typeof recentFiles !== "undefined") recentFiles.clear()
                }
            }
            MenuSeparator {}
            MenuItem { action: saveAction }
            MenuItem { action: saveAsAction }
        }
        Menu { title: qsTr("Edit"); MenuItem { action: undoAction } MenuItem { action: redoAction } MenuSeparator {} MenuItem { action: copyAction } }
        Menu { title: qsTr("Image"); MenuItem { action: rotateLeftAction } MenuItem { action: rotateRightAction } MenuItem { action: flipHorizontalAction } MenuItem { action: flipVerticalAction } MenuSeparator {} MenuItem { action: selectAction } MenuItem { action: brushAction } MenuItem { action: shapeAction } MenuItem { action: cropAction } MenuItem { action: textAction } MenuItem { action: eyedropperAction } MenuSeparator {} MenuItem { action: resizeImageAction } MenuItem { action: canvasSizeAction } }
        Menu {
            title: qsTr("View")
            MenuItem { action: zoomInAction } MenuItem { action: zoomOutAction } MenuItem { action: fitAction } MenuItem { action: actualAction } MenuSeparator {}
            MenuItem { action: commandPaletteAction } MenuSeparator {}
            MenuItem { text: qsTr("Follow system theme"); checkable: true; checked: window.followSystemTheme; onTriggered: window.followSystemTheme = checked }
            MenuItem { text: qsTr("Dark theme"); checkable: true; checked: window.darkTheme; enabled: !window.followSystemTheme; onTriggered: window.darkTheme = checked }
            MenuItem { text: qsTr("Reduce motion"); checkable: true; checked: window.reduceMotion; onTriggered: window.reduceMotion = checked }
            Menu {
                title: qsTr("Language")
                Repeater {
                    model: typeof language !== "undefined" ? language.availableLocales : []
                    MenuItem {
                        required property var modelData
                        text: modelData.nativeName
                        checkable: true
                        checked: typeof language !== "undefined" && language.locale === modelData.id
                        onTriggered: if (typeof language !== "undefined") language.setLanguage(modelData.id)
                    }
                }
            }
            MenuSeparator {}
            MenuItem { action: settingsAction }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: dropArea.containsDrag
        color: Theme.alpha(Theme.accent, 0.06)
        border.width: 2
        border.color: Theme.accent
        z: 1000
        Label {
            anchors.centerIn: parent
            text: qsTr("Drop to open image")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontHeadline
            font.weight: Theme.fontWeightDemiBold
        }
    }
    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: function(drop) {
            if (editor.busy || !drop.hasUrls || drop.urls.length === 0) return
            window.requestOpen(drop.urls[0])
            drop.acceptProposedAction()
        }
    }

    ColumnLayout {
        id: shellLayout
        objectName: "keyScope"
        anchors.fill: parent; spacing: 0
        focus: true
        activeFocusOnTab: false
        Keys.onPressed: function(event) { window.handleCanvasKeyPress(event) }
        Keys.onReleased: function(event) { window.handleCanvasKeyRelease(event) }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 58; color: theme.panel
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 18; spacing: 6
                CommandButton { action: openAction; iconName: "folder" }
                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 19; Layout.leftMargin: 5; Layout.rightMargin: 5; color: theme.border }
                CommandButton { action: undoAction; text: ""; iconName: "undo"; ToolTip.visible: hovered; ToolTip.text: undoAction.text }
                CommandButton { action: redoAction; text: ""; iconName: "redo"; ToolTip.visible: hovered; ToolTip.text: redoAction.text }
                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 19; Layout.leftMargin: 5; Layout.rightMargin: 5; color: theme.border }
                CommandButton { action: rotateRightAction; text: qsTr("Rotate"); iconName: "rotate" }
                CommandButton { action: cropAction; iconName: "crop" }
                CommandButton {
                    objectName: "action-transform"
                    text: qsTr("Transform"); iconName: "rotate"
                    enabled: editor.hasImage && !editor.busy
                    onClicked: transformMenu.open()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Rotate and flip")
                }
                CommandButton {
                    objectName: "action-canvas"
                    text: qsTr("Canvas"); iconName: "fit"
                    enabled: canvasSizeAction.enabled
                    onClicked: canvasSizeAction.trigger()
                    ToolTip.visible: hovered
                    ToolTip.text: canvasSizeAction.text
                }
                Item { Layout.fillWidth: true }
                NekoButton {
                    objectName: "settingsButton"
                    text: qsTr("Settings"); variant: "ghost"
                    onClicked: window.openSettings()
                    ToolTip.visible: hovered; ToolTip.text: qsTr("Preferences (Ctrl+,)")
                }
                NekoButton {
                    text: qsTr("Search"); variant: "ghost"
                    onClicked: commandPalette.open()
                    ToolTip.visible: hovered; ToolTip.text: qsTr("Command palette (Ctrl+K)")
                }
                BusyIndicator { running: editor.busy; visible: running; Layout.preferredWidth: 28; Layout.preferredHeight: 28 }
                CommandButton { action: saveAction; iconName: "save" }
                CommandButton { action: saveAsAction; primary: true }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.border }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            Rectangle {
                Layout.fillHeight: true; Layout.preferredWidth: 74; color: theme.panel
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    Flickable {
                        id: toolScroller
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: tools.implicitHeight + 20
                        clip: true; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: NekoScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: tools; width: parent.width; y: 10; spacing: 3
                            Repeater {
                                model: [
                                    { icon: "select", label: qsTr("Select") }, { icon: "pan", label: qsTr("Pan") },
                                    { icon: "adjust", label: qsTr("Adjust") }, { icon: "filters", label: qsTr("Filters") },
                                    { icon: "brush", label: qsTr("Brush") }, { icon: "text", label: qsTr("Text") },
                                    { icon: "shapes", label: qsTr("Shapes") }, { icon: "mosaic", label: qsTr("Mosaic") },
                                    { icon: "eye", label: qsTr("Eyedropper") }, { icon: "crop", label: qsTr("Crop") }
                                ]
                                delegate: NekoToolButton {
                                    id: toolButton
                                    required property var modelData
                                    required property int index
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: index === 2 || index === 4 ? 10 : 0
                                    objectName: "tool-" + modelData.icon
                                    text: modelData.label
                                    iconName: modelData.icon
                                    accessibleName: modelData.label
                                    readonly property bool available: modelData.icon === "pan" || modelData.icon === "select" || modelData.icon === "adjust" || modelData.icon === "filters" || modelData.icon === "brush" || modelData.icon === "mosaic" || modelData.icon === "text" || modelData.icon === "shapes" || modelData.icon === "eye" || modelData.icon === "crop"
                                    enabled: available && !editor.busy && (modelData.icon !== "crop" || editor.hasImage)
                                    checked: available && window.activeTool === modelData.icon
                                    onClicked: window.activeTool = modelData.icon
                                    ToolTip.visible: hovered
                                    ToolTip.text: available ? modelData.label : modelData.label + " · " + qsTr("Coming soon")
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.border }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingSm
                        Layout.bottomMargin: Theme.spacingMd
                        spacing: Theme.spacingXs
                        AbstractButton {
                            id: foregroundSwatch
                            objectName: "foreground-swatch"
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 34; implicitHeight: 34
                            hoverEnabled: true
                            focusPolicy: Qt.StrongFocus
                            activeFocusOnTab: true
                            scale: down ? 0.94 : hovered ? 1.05 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.duration(Motion.fast)
                                    easing.type: Motion.decelerateEasing
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Foreground colour")
                            Accessible.description: qsTr("Sets the shared ink for the brush, text and shape tools.")
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Foreground colour")
                            onClicked: {
                                foregroundColorDialog.selectedColor = window.foregroundColor
                                foregroundColorDialog.open()
                            }
                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: window.foregroundColor
                                border.width: 3
                                border.color: theme.panel
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    radius: Theme.radiusSm + 4
                                    color: "transparent"
                                    border.width: Theme.borderWidth
                                    border.color: foregroundSwatch.hovered ? theme.muted : theme.border
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Theme.focusRingOffset
                                radius: Theme.radiusSm + Theme.focusRingOffset
                                color: "transparent"
                                border.width: Theme.focusRingWidth
                                border.color: Theme.focusRing
                                visible: foregroundSwatch.visualFocus
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Colour")
                            color: theme.muted
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                }
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.border }
            EditorCanvas {
                id: canvas; Layout.fillWidth: true; Layout.fillHeight: true; theme: theme
                objectName: "editorCanvas"
                hasImage: editor.hasImage; imageUrl: editor.imageUrl; imageWidth: editor.imageWidth; imageHeight: editor.imageHeight
                baseImageUrl: typeof editor.baseImageUrl !== "undefined" ? editor.baseImageUrl : ""
                gpuPreviewAvailable: typeof renderCapabilities !== "undefined" && renderCapabilities.gpuPreviewAvailable
                                     && (typeof settings === "undefined" || settings.gpuPreviewEnabled)
                showCheckerboard: typeof settings === "undefined" || settings.showCheckerboard
                adjustmentPreviewActive: typeof editor.adjustmentPreviewGpuEligible !== "undefined"
                                         && editor.adjustmentPreviewGpuEligible
                                         && (typeof editor.filterPreset === "undefined" || editor.filterPreset === "none")
                previewExposure: typeof editor.pendingAdjustmentValues !== "undefined"
                                 && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.exposure / 25 : 0
                previewBrightness: typeof editor.pendingAdjustmentValues !== "undefined"
                                   && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.brightness / 100 : 0
                previewContrast: typeof editor.pendingAdjustmentValues !== "undefined"
                                 && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.contrast / 100 : 0
                previewSaturation: typeof editor.pendingAdjustmentValues !== "undefined"
                                   && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.saturation / 100 : 0
                previewHighlights: typeof editor.pendingAdjustmentValues !== "undefined"
                                   && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.highlights / 100 : 0
                previewShadows: typeof editor.pendingAdjustmentValues !== "undefined"
                                && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.shadows / 100 : 0
                previewWhites: typeof editor.pendingAdjustmentValues !== "undefined"
                               && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.whites / 100 : 0
                previewBlacks: typeof editor.pendingAdjustmentValues !== "undefined"
                               && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.blacks / 100 : 0
                previewTemperature: typeof editor.pendingAdjustmentValues !== "undefined"
                                    && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.temperature / 100 : 0
                previewTint: typeof editor.pendingAdjustmentValues !== "undefined"
                             && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.tint / 100 : 0
                previewVibrance: typeof editor.pendingAdjustmentValues !== "undefined"
                                 && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.vibrance / 100 : 0
                fileName: editor.fileName; dirty: editor.dirty
                mosaicActive: window.activeTool === "mosaic"
                cropActive: window.activeTool === "crop"
                eyedropperActive: window.activeTool === "eye"
                textActive: window.activeTool === "text"
                panActive: window.activeTool === "pan"
                spacePanActive: window.spacePanActive
                busy: editor.busy
                toolHint: window.activeToolHint
                selectionActive: window.activeTool === "select"
                movePreviewReady: editor.objectMovePreviewReady
                movePreviewBaseUrl: editor.objectMoveBaseUrl
                movePreviewObjectUrl: editor.objectMoveObjectUrl
                movePreviewBounds: editor.objectMoveBounds
                shapeActive: window.activeTool === "shapes" && shapePanel.shapeKind !== "polygon"
                polygonActive: window.activeTool === "shapes" && shapePanel.shapeKind === "polygon"
                brushActive: window.activeTool === "brush"
                brushDiameter: brushPanel.diameter
                brushColor: brushPanel.color
                brushOpacity: brushPanel.inkOpacity
                brushSoftness: brushPanel.softness
                onBrushStrokeCommitted: function(points) {
                    editor.addBrushStroke(points, brushPanel.diameter,
                                          brushPanel.effectiveColor,
                                          brushPanel.softness / 100)
                }
                onBrushCancelled: window.activeTool = "adjust"
                shapeKind: shapePanel.shapeKind
                shapeFillColor: shapePanel.fillColor
                shapeStrokeColor: shapePanel.strokeColor
                shapeStrokeWidth: shapePanel.strokeWidth
                shapeCornerRadius: shapePanel.cornerRadius
                shapeFilled: shapePanel.filled
                onShapeCommitted: function(kind, area) {
                    editor.addShape(kind, area,
                                    shapePanel.filled ? shapePanel.fillColor : "transparent",
                                    shapePanel.strokeColor, shapePanel.strokeWidth,
                                    shapePanel.cornerRadius)
                }
                onShapeCancelled: window.activeTool = "adjust"
                onPolygonCommitted: function(points) {
                    editor.addPolygon(points,
                                      shapePanel.filled ? shapePanel.fillColor : "transparent",
                                      shapePanel.strokeColor, shapePanel.strokeWidth)
                }
                objectAt: function(x, y) { return editor.objectAt(x, y) }
                objectBounds: function(id) { return editor.objectBounds(id) }
                onMoveObjectsRequested: function(ids, dx, dy) {
                    const moved = editor.moveObjects(ids, dx, dy)
                    if (!moved) {
                        window._awaitingMovePreview = false
                        editor.clearObjectMovePreview()
                        canvas.clearMovePreview()
                    }
                }
                onMoveStarted: function(ids) {
                    window._awaitingMovePreview = true
                    editor.beginObjectMovePreview(ids)
                }
                onMovePreview: function(ids, dx, dy) {
                    // The object crop offset is bound inside EditorCanvas to
                    // SelectionOverlay.movePreviewOffset; no controller work
                    // happens per pointer event.
                }
                onMoveFinished: function(ids, dx, dy) {
                    // The commit is already in flight via moveObjectsRequested;
                    // keep the crop until busyChanged reports completion.
                }
                onMoveCancelled: function() {
                    window._awaitingMovePreview = false
                    editor.clearObjectMovePreview()
                    canvas.clearMovePreview()
                }
                onRemoveObjectsRequested: function(ids) { editor.removeObjects(ids) }
                onObjectDoubleClicked: function(id) {
                    const info = editor.textInfo(id)
                    if (!info || info.id === undefined) return
                    window.activeTool = "text"
                    canvas.setSelectionIds([id])
                    window.applyTextInfo(info)
                }
                onTextPointSelected: function(imageX, imageY) { window.createTextAt(imageX, imageY) }
                onTextCancelled: window.activeTool = "adjust"
                colorSampler: function(x, y) { return editor.colorAt(x, y) }
                onColorPicked: function(value) { window.showStatus(qsTr("Picked %1").arg(value.toString())) }
                onEyedropperCancelled: window.activeTool = "adjust"
                cropAspectRatio: cropPanel.aspectRatio
                onCropApplyRequested: function(area) { window.applyCrop(area) }
                onCropCancelled: window.activeTool = "adjust"
                mosaicBrushMode: mosaicPanel.brushMode
                mosaicBrushDiameter: mosaicPanel.brushDiameter
                inputEnabled: !editor.busy
                onMosaicRectangleCommitted: function(area) {
                    if (mosaicPanel.effect === "blur") editor.blurRectangle(area, mosaicPanel.blurRadius)
                    else editor.mosaicRectangle(area, mosaicPanel.blockSize)
                }
                onMosaicStrokeCommitted: function(points) {
                    if (mosaicPanel.effect === "blur") editor.blurStroke(points, mosaicPanel.blurRadius)
                    else editor.mosaicStroke(points, mosaicPanel.brushDiameter, mosaicPanel.blockSize)
                }
                recentEntries: typeof recentFiles !== "undefined" ? recentFiles.entries : []
                onRecentRequested: function(url) { window.requestOpen(url) }
                onOpenRequested: if (!editor.busy) openDialog.open()
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.border }
            Inspector {
                id: inspector
                objectName: "inspector"
                visible: window.activeTool === "adjust"
                Layout.fillHeight: true
                Layout.preferredWidth: 320
                theme: theme
                adjustmentsEnabled: editor.hasImage && (!editor.busy || editor.adjustmentInteractive)
                adjustmentValues: editor.adjustmentValues
                histogramBins: editor.histogramBins
                onAdjustmentStarted: function(key) { editor.beginAdjustment(key) }
                onAdjustmentPreview: function(key, value) { editor.previewAdjustment(key, value) }
                onAdjustmentFinished: function(key, value) { editor.finishAdjustment(key, value) }
                onAdjustmentReset: editor.resetAdjustments()
                onAutoEnhanceRequested: {
                    editor.autoEnhance()
                    window.showStatus(qsTr("Auto enhance"))
                }
                filtersEnabled: editor.hasImage && !editor.busy
                filterIntensityEnabled: editor.hasImage && (!editor.busy || editor.filterIntensityInteractive)
                filterPreset: editor.filterPreset
                previewsAvailable: filterPreviews.ready
                previewRevision: filterPreviews.revision
                filterIntensity: editor.filterIntensity
                onFilterSelected: function(preset) {
                    editor.selectFilter(preset)
                    window.showStatus(preset === "none" ? qsTr("Filters")
                                                        : qsTr("Filters") + " · " + preset)
                }
                onFilterIntensityStarted: editor.beginFilterIntensity()
                onFilterIntensityPreview: function(value) { editor.previewFilterIntensity(value) }
                onFilterIntensityFinished: function(value) { editor.finishFilterIntensity(value) }
            }
            Rectangle {
                id: filtersToolPanel
                objectName: "filtersToolPanel"
                visible: window.activeTool === "filters"
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                color: theme.panel
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 20
                    contentWidth: width
                    contentHeight: filtersContent.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    FiltersPanel {
                        id: filtersContent
                        width: parent.width
                        currentPreset: editor.filterPreset
                        intensity: editor.filterIntensity
                        presetsEnabled: editor.hasImage && !editor.busy
                        intensityEnabled: editor.hasImage && (!editor.busy || editor.filterIntensityInteractive)
                        previewsAvailable: filterPreviews.ready
                        previewRevision: filterPreviews.revision
                        onFilterSelected: function(preset) {
                            editor.selectFilter(preset)
                            window.showStatus(preset === "none" ? qsTr("Filters")
                                                                : qsTr("Filters") + " · " + preset)
                        }
                        onIntensityStarted: editor.beginFilterIntensity()
                        onIntensityPreview: function(value) { editor.previewFilterIntensity(value) }
                        onIntensityFinished: function(value) { editor.finishFilterIntensity(value) }
                    }
                    ScrollBar.vertical: NekoScrollBar { policy: ScrollBar.AlwaysOff }
                }
            }
            MosaicPanel {
                id: mosaicPanel
                objectName: "mosaicPanel"
                visible: window.activeTool === "mosaic"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
            }
            TextPanel {
                id: textPanel
                objectName: "textPanel"
                visible: window.activeTool === "text"
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
                enabled: editor.hasImage && !editor.busy
                busy: editor.busy
                onTextEdited: function(text) {
                    if (textPanel.editMode) textCommitTimer.restart()
                }
                onStyleEdited: function(key, value) {
                    if (textPanel.editMode) window.commitTextUpdate()
                }
                onResetRequested: function() {
                    if (textPanel.editMode) window.commitTextUpdate()
                }
            }
            Timer {
                id: textCommitTimer
                interval: 450
                onTriggered: window.commitTextUpdate()
            }
            LayerPanel {
                id: layerPanel
                objectName: "layerPanel"
                visible: window.activeTool === "select"
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
                summaries: []
                selectedIds: canvas.selectionIds
                enabled: editor.hasImage && !editor.busy
                function refreshLayers() { summaries = editor.objectSummaries() }
                Component.onCompleted: refreshLayers()
                Connections { target: editor; function onDocumentChanged() { layerPanel.refreshLayers() } }
                onSelectionRequested: function(ids) { canvas.setSelectionIds(ids) }
                onVisibilityToggled: function(id, visible) { editor.setObjectVisible(id, visible) }
                onLockToggled: function(id, locked) { editor.setObjectLocked(id, locked) }
                onOrderRequested: function(id, action) {
                    if (action === "front") editor.bringObjectToFront(id)
                    else if (action === "back") editor.sendObjectToBack(id)
                    else if (action === "up") editor.raiseObject(id)
                    else editor.lowerObject(id)
                }
                onRemoveRequested: function(ids) { editor.removeObjects(ids) }
                onAlignRequested: function(ids, alignment) { editor.alignObjects(ids, alignment) }
            }
            BrushPanel {
                id: brushPanel; objectName: "brushPanel"
                visible: window.activeTool === "brush"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
            }
            ShapePanel {
                id: shapePanel; objectName: "shapePanel"
                visible: window.activeTool === "shapes"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
            }
            CropPanel {
                id: cropPanel; objectName: "cropPanel"
                visible: window.activeTool === "crop"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
                imageAspectRatio: editor.imageHeight > 0 ? editor.imageWidth / editor.imageHeight : 1
                selectionWidth: canvas.cropSelection.width
                selectionHeight: canvas.cropSelection.height
                canApply: editor.hasImage && !editor.busy && selectionWidth >= 1 && selectionHeight >= 1
                onApplyRequested: window.applyCrop(canvas.cropSelection)
                onCancelRequested: window.activeTool = "adjust"
                onResetRequested: canvas.resetCropSelection()
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 30; color: theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 15; anchors.rightMargin: 15
                spacing: Theme.spacingSm

                Label {
                    objectName: "status-dimensions"
                    text: editor.hasImage ? editor.imageWidth + " × " + editor.imageHeight + " px" : "— × — px"
                    color: theme.muted; font.pixelSize: Theme.fontCaption
                }
                Text { text: "/"; color: theme.border; font.pixelSize: Theme.fontCaption }
                Label {
                    objectName: "status-srgb"
                    text: "sRGB"
                    color: theme.muted; font.pixelSize: Theme.fontCaption
                }
                Text { text: "/"; color: theme.border; font.pixelSize: Theme.fontCaption }
                Label {
                    objectName: "status-object-count"
                    text: window.objectCount === 1 ? qsTr("1 object")
                                                  : qsTr("%1 objects").arg(window.objectCount)
                    color: theme.muted; font.pixelSize: Theme.fontCaption
                }
                Item { Layout.fillWidth: true }

                NekoIconButton {
                    objectName: "status-zoom-out"
                    iconName: "minus"; buttonSize: 22; iconSize: 14
                    accessibleName: qsTr("Zoom out")
                    enabled: editor.hasImage && canvas.zoom > 0.0501
                    onClicked: canvas.changeZoom(1 / 1.2)
                }
                NekoSlider {
                    id: statusZoomSlider
                    objectName: "status-zoom-slider"
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: Theme.sliderHeight
                    from: 5; to: 300; stepSize: 1
                    value: canvas.zoom * 100
                    enabled: editor.hasImage
                    accessibleName: qsTr("Canvas zoom")
                    onPreview: function(value) { canvas.setZoomValue(value / 100) }
                    onFinish: function(value) { canvas.setZoomValue(value / 100) }
                    Connections {
                        target: canvas
                        function onZoomChanged() {
                            if (!statusZoomSlider.dragging)
                                statusZoomSlider.value = canvas.zoom * 100
                        }
                    }
                }
                NekoIconButton {
                    objectName: "status-zoom-in"
                    iconName: "plus"; buttonSize: 22; iconSize: 14
                    accessibleName: qsTr("Zoom in")
                    enabled: editor.hasImage && canvas.zoom < 2.999
                    onClicked: canvas.changeZoom(1.2)
                }
                Label {
                    objectName: "status-zoom-value"
                    text: Math.round(canvas.zoom * 100) + "%"
                    color: theme.text; font.pixelSize: Theme.fontCaption
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignHCenter
                }
                NekoButton {
                    objectName: "status-zoom-actual"
                    text: qsTr("100%"); variant: "ghost"; implicitHeight: 22
                    enabled: editor.hasImage
                    onClicked: canvas.actualSize()
                }
                NekoButton {
                    objectName: "status-zoom-fit"
                    text: qsTr("Fit"); variant: "ghost"; implicitHeight: 22
                    enabled: editor.hasImage
                    onClicked: canvas.fitImage()
                }
                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 16; color: theme.border }
                Label {
                    objectName: "statusMessage"
                    text: editor.busy ? qsTr("Working…")
                          : window.transientStatus.length > 0 ? window.transientStatus
                          : editor.dirty ? qsTr("Unsaved changes") : qsTr("Local editing")
                    color: theme.muted; font.pixelSize: Theme.fontCaption
                    elide: Text.ElideRight
                    Layout.maximumWidth: 190
                }
                Timer { id: statusTimer; interval: 2200; onTriggered: window.transientStatus = "" }
            }
        }
    }

    CommandPalette {
        id: commandPalette
        objectName: "commandPalette"
        anchors.fill: parent
        commands: [
            { title: openAction.text, detail: qsTr("File"), shortcut: "Ctrl+O", enabled: openAction.enabled,
              run: function() { openDialog.open() } },
            { title: saveAction.text, detail: qsTr("File"), shortcut: "Ctrl+S", enabled: saveAction.enabled,
              run: function() { editor.saveImage() } },
            { title: saveAsAction.text, detail: qsTr("File"), shortcut: "Ctrl+Shift+S", enabled: saveAsAction.enabled,
              run: function() { saveDialog.open() } },
            { title: undoAction.text, detail: qsTr("Edit"), shortcut: "Ctrl+Z", enabled: undoAction.enabled,
              run: function() { editor.undo() } },
            { title: redoAction.text, detail: qsTr("Edit"), shortcut: "Ctrl+Shift+Z", enabled: redoAction.enabled,
              run: function() { editor.redo() } },
            { title: copyAction.text, detail: qsTr("Edit"), shortcut: "Ctrl+Shift+C", enabled: copyAction.enabled,
              run: function() { editor.copyImageToClipboard(); window.showStatus(qsTr("Copied to clipboard")) } },
            { title: rotateRightAction.text, detail: qsTr("Image"), enabled: rotateRightAction.enabled,
              run: function() { editor.rotateClockwise() } },
            { title: rotateLeftAction.text, detail: qsTr("Image"), enabled: rotateLeftAction.enabled,
              run: function() { editor.rotateCounterClockwise() } },
            { title: flipHorizontalAction.text, detail: qsTr("Image"), enabled: flipHorizontalAction.enabled,
              run: function() { editor.flipHorizontal() } },
            { title: flipVerticalAction.text, detail: qsTr("Image"), enabled: flipVerticalAction.enabled,
              run: function() { editor.flipVertical() } },
            { title: qsTr("Auto enhance"), detail: qsTr("Image"), enabled: editor.hasImage && !editor.busy,
              run: function() { editor.autoEnhance() } },
            { title: cropAction.text, detail: qsTr("Tools"), shortcut: "C", enabled: cropAction.enabled,
              run: function() { window.activeTool = "crop" } },
            { title: panAction.text, detail: qsTr("Tools"), shortcut: "H", enabled: panAction.enabled,
              run: function() { window.activeTool = "pan" } },
            { title: selectAction.text, detail: qsTr("Tools"), shortcut: "V", enabled: selectAction.enabled,
              run: function() { window.activeTool = "select" } },
            { title: brushAction.text, detail: qsTr("Tools"), shortcut: "B", enabled: brushAction.enabled,
              run: function() { window.activeTool = "brush" } },
            { title: shapeAction.text, detail: qsTr("Tools"), shortcut: "U", enabled: shapeAction.enabled,
              run: function() { window.activeTool = "shapes" } },
            { title: textAction.text, detail: qsTr("Tools"), shortcut: "T", enabled: textAction.enabled,
              run: function() { window.activeTool = "text" } },
            { title: eyedropperAction.text, detail: qsTr("Tools"), shortcut: "I", enabled: eyedropperAction.enabled,
              run: function() { window.activeTool = "eye" } },
            { title: resizeImageAction.text, detail: qsTr("Image"), enabled: resizeImageAction.enabled,
              run: function() { resizeDialog.open() } },
            { title: canvasSizeAction.text, detail: qsTr("Image"), enabled: canvasSizeAction.enabled,
              run: function() { canvasSizeDialog.open() } },
            { title: shortcutsAction.text, detail: qsTr("Help"), shortcut: "F1",
              run: function() { shortcutsDialog.open() } },
            { title: settingsAction.text, detail: qsTr("Help"), shortcut: "Ctrl+,",
              run: function() { window.openSettings() } },
            { title: zoomInAction.text, detail: qsTr("View"), shortcut: "Ctrl+=", enabled: zoomInAction.enabled,
              run: function() { canvas.changeZoom(1.2) } },
            { title: zoomOutAction.text, detail: qsTr("View"), shortcut: "Ctrl+-", enabled: zoomOutAction.enabled,
              run: function() { canvas.changeZoom(1 / 1.2) } },
            { title: fitAction.text, detail: qsTr("View"), shortcut: "Ctrl+0", enabled: fitAction.enabled,
              run: function() { canvas.fitImage() } },
            { title: actualAction.text, detail: qsTr("View"), shortcut: "Ctrl+1", enabled: actualAction.enabled,
              run: function() { canvas.actualSize() } },
            { title: qsTr("Toggle dark theme"), detail: qsTr("View"),
              run: function() { window.followSystemTheme = false; window.darkTheme = !window.darkTheme } },
            { title: qsTr("Follow system theme"), detail: qsTr("View"),
              run: function() { window.followSystemTheme = !window.followSystemTheme } },
            { title: qsTr("Toggle reduce motion"), detail: qsTr("View"),
              run: function() { window.reduceMotion = !window.reduceMotion } },
            { title: qsTr("Switch to English"), detail: qsTr("Language"),
              enabled: typeof language !== "undefined",
              run: function() { if (typeof language !== "undefined") language.setLanguage("en") } },
            { title: qsTr("切换到简体中文"), detail: qsTr("Language"),
              enabled: typeof language !== "undefined",
              run: function() { if (typeof language !== "undefined") language.setLanguage("zh_CN") } }
        ].concat((typeof recentFiles !== "undefined" && recentFiles.entries)
                 ? recentFiles.entries.map(function(entry) {
                       return { title: entry.name, detail: qsTr("Recent"),
                                enabled: !editor.busy,
                                run: function() { window.requestOpen(entry.url) } }
                   })
                 : [])
    }
}
