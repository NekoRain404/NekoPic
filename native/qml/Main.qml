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
    property string themeVariant: ""
    property bool followSystemTheme: false
    readonly property bool systemDark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    // Letter shortcuts must not fire while the user is typing in a modal.
    readonly property bool blockingModal: commandPalette.opened || dialogs.anyBlockingOpen
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
    // Launch/screenshot hook: which settings category to open.
    property string settingsCategory: ""
    // Every tool keeps the same right-hand function area so switching tools
    // never reflows the canvas.
    readonly property int toolPanelWidth: window.width < 1100 ? 260 : 292
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
        const name = dialogs.exportFileName.trim()
        if (name.length === 0 || /[\\/]/.test(name)
                || name === "." || name === "..")
            return base
        let finalName = name
        if (finalName.lastIndexOf(".") < 0 && dialogs.exportFormatSuffix.length > 0)
            finalName += "." + dialogs.exportFormatSuffix
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
            dialogs.openDiscardDialog()
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
    /*!
        Effective portable shortcut for a settings action key. The helper reads
        settings.shortcuts directly so every calling Action binding refreshes
        when shortcutsChanged() is emitted.
    */
    function shortcutFor(key, fallback) {
        if (typeof settings === "undefined" || settings === null)
            return fallback
        const overrides = settings.shortcuts
        const value = overrides ? overrides[key] : undefined
        return value !== undefined && String(value).length > 0 ? value : fallback
    }
    function applyThemeMode(mode) {
        const variants = ["midnight", "warm", "graphite", "contrast",
                          "nordic", "sakura", "forest", "solarized"]
        const lightVariants = ["light", "warm", "nordic", "sakura"]
        window.themeVariant = variants.indexOf(mode) >= 0 ? mode : ""
        window.followSystemTheme = mode === "system"
        window.darkTheme = mode === "system" ? window.systemDark
                                             : lightVariants.indexOf(mode) < 0
    }
    function applySettings() {
        if (typeof settings === "undefined") return
        const mode = settings.themeMode
        applyThemeMode(mode)
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
        dialogs.showRecovery()
    }
    function openSettings() {
        dialogs.openSettings(window.settingsCategory)
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
            if (!editor.busy) { closingRequested = true; dialogs.openDiscardDialog() }
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
    Binding { target: Theme; property: "themeId"; value: window.themeVariant }
    Binding { target: Theme; property: "reduceMotion"; value: window.reduceMotion }
    Binding {
        target: Theme
        property: "fontScale"
        value: typeof settings !== "undefined" && settings !== null
               ? settings.uiFontScale / 100 : 1.0
    }
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

    Action { id: openAction; text: qsTr("Open image…"); shortcut: window.shortcutFor("open", "Ctrl+O"); enabled: !editor.busy; onTriggered: dialogs.openOpenDialog() }
    Action { id: saveAction; text: qsTr("Save"); shortcut: window.shortcutFor("save", "Ctrl+S"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.saveImage() }
    Action { id: saveAsAction; text: qsTr("Save as…"); shortcut: window.shortcutFor("saveAs", "Ctrl+Shift+S"); enabled: editor.hasImage && !editor.busy; onTriggered: dialogs.openSaveDialog() }
    Action { id: settingsAction; text: qsTr("Preferences…"); shortcut: window.shortcutFor("settings", "Ctrl+,"); onTriggered: window.openSettings() }
    Action { id: commandPaletteAction; text: qsTr("Command palette…"); shortcut: window.shortcutFor("commandPalette", "Ctrl+K"); onTriggered: commandPalette.opened ? commandPalette.close() : commandPalette.open() }
    Action { id: copyAction; text: qsTr("Copy image"); shortcut: window.shortcutFor("copy", "Ctrl+Shift+C"); enabled: editor.hasImage && !editor.busy; onTriggered: { editor.copyImageToClipboard(); window.showStatus(qsTr("Copied to clipboard")) } }
    Action { id: undoAction; text: qsTr("Undo"); shortcut: window.shortcutFor("undo", "Ctrl+Z"); enabled: editor.canUndo && !editor.busy; onTriggered: { editor.undo(); window.showStatus(qsTr("Undone")) } }
    Action { id: redoAction; text: qsTr("Redo"); shortcut: window.shortcutFor("redo", "Ctrl+Shift+Z"); enabled: editor.canRedo && !editor.busy; onTriggered: { editor.redo(); window.showStatus(qsTr("Redone")) } }
    Action { id: rotateRightAction; text: qsTr("Rotate clockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateClockwise() }
    Action { id: rotateLeftAction; text: qsTr("Rotate counterclockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateCounterClockwise() }
    Action { id: flipHorizontalAction; text: qsTr("Flip horizontally"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipHorizontal() }
    Action { id: flipVerticalAction; text: qsTr("Flip vertically"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipVertical() }
    Action { id: resizeImageAction; text: qsTr("Resize image…"); enabled: editor.hasImage && !editor.busy; onTriggered: dialogs.openResizeDialog() }
    Action { id: canvasSizeAction; text: qsTr("Canvas size…"); enabled: editor.hasImage && !editor.busy; onTriggered: dialogs.openCanvasSizeDialog() }
    Action { id: shortcutsAction; text: qsTr("Keyboard shortcuts"); shortcut: "F1"; onTriggered: dialogs.openShortcutsDialog() }
    Action { id: brushAction; text: qsTr("Brush"); shortcut: window.shortcutFor("brush", "B"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "brush" }
    Action { id: shapeAction; text: qsTr("Shapes"); shortcut: window.shortcutFor("shape", "U"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "shapes" }
    Action { id: panAction; text: qsTr("Pan"); shortcut: window.shortcutFor("pan", "H"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "pan" }
    Action { id: selectAction; text: qsTr("Select"); shortcut: window.shortcutFor("select", "V"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "select" }
    Action { id: textAction; text: qsTr("Add text"); shortcut: window.shortcutFor("text", "T"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "text" }
    Action { id: eyedropperAction; text: qsTr("Eyedropper"); shortcut: window.shortcutFor("eyedropper", "I"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "eye" }
    Action { id: cropAction; text: qsTr("Crop"); shortcut: window.shortcutFor("crop", "C"); enabled: editor.hasImage && !editor.busy && !window.blockingModal; onTriggered: window.activeTool = "crop" }
    Action { id: zoomInAction; text: qsTr("Zoom in"); shortcut: window.shortcutFor("zoomIn", "Ctrl+="); enabled: editor.hasImage; onTriggered: canvas.changeZoom(1.2) }
    Action { id: zoomOutAction; text: qsTr("Zoom out"); shortcut: window.shortcutFor("zoomOut", "Ctrl+-"); enabled: editor.hasImage; onTriggered: canvas.changeZoom(1 / 1.2) }
    Action { id: fitAction; text: qsTr("Fit to window"); shortcut: window.shortcutFor("fit", "Ctrl+0"); enabled: editor.hasImage; onTriggered: canvas.fitImage() }
    Action { id: actualAction; text: qsTr("Actual size (100%)"); shortcut: window.shortcutFor("actual", "Ctrl+1"); enabled: editor.hasImage; onTriggered: canvas.actualSize() }
    /*! Shared action catalogue for the menu bar, toolbar and command palette. */
    readonly property var actionMap: ({
        open: openAction, save: saveAction, saveAs: saveAsAction,
        settings: settingsAction, commandPalette: commandPaletteAction,
        copy: copyAction, undo: undoAction, redo: redoAction,
        rotateLeft: rotateLeftAction, rotateRight: rotateRightAction,
        rotate: rotateRightAction,
        flipHorizontal: flipHorizontalAction, flipVertical: flipVerticalAction,
        resizeImage: resizeImageAction, canvasSize: canvasSizeAction,
        shortcuts: shortcutsAction, brush: brushAction, shape: shapeAction,
        pan: panAction, select: selectAction, text: textAction,
        eyedropper: eyedropperAction, crop: cropAction,
        zoomIn: zoomInAction, zoomOut: zoomOutAction,
        fit: fitAction, actual: actualAction
    })
    AppDialogs {
        id: dialogs
        actions: window.actionMap
        editorModel: editor
        recoveryService: typeof recovery !== "undefined" ? recovery : null
        settingsStore: typeof settings !== "undefined" ? settings : null
        languageService: typeof language !== "undefined" ? language : null
        formatInfo: typeof formatRegistryInfo !== "undefined"
                    ? formatRegistryInfo : ({ readableCount: 0, writableCount: 0 })
        lastFolder: window.lastFolder
        busy: editor.busy
        closingRequested: window.closingRequested
        pendingImage: window.pendingImage
        foregroundColor: window.foregroundColor
        followSystemTheme: window.followSystemTheme
        darkTheme: window.darkTheme
        reduceMotion: window.reduceMotion
        localeId: typeof language !== "undefined" ? language.locale : "zh_CN"

        onImageOpenRequested: function(selectedFile, folder) {
            window.lastFolder = folder
            window.requestOpen(selectedFile)
        }
        onExportDestinationSelected: function(selectedFile, folder) {
            window.lastFolder = folder
            window.pendingExportUrl = selectedFile
        }
        onSaveBeforeRequested: window.saveBeforePending = true
        onSaveBeforeCancelled: if (window.saveBeforePending) window.saveBeforePending = false
        onDiscardAndCloseRequested: {
            window.discardConfirmed = true
            window.close()
        }
        onForegroundColorPicked: function(value) { window.foregroundColor = value }
        onExportRequested: function(format, quality, background) {
            editor.exportQuality = quality
            editor.jpegBackground = background
            editor.saveAs(window.exportDestinationUrl(), format)
        }
        onThemeModeChanged: function(value) {
            window.applyThemeMode(value)
        }
        onReduceMotionRequested: window.reduceMotion = value
        onStartupToolChanged: window.startupTool = value
    }
    // Single-shot retry while a startup image is decoding; avoids spinning the
    // event loop with Qt.callLater.
    Timer {
        id: recoveryCheckTimer
        interval: 120
        repeat: false
        onTriggered: window.maybeShowRecovery()
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
        function onErrorChanged() { dialogs.showError() }
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

    menuBar: AppMenuBar {
        actions: window.actionMap
        followSystemTheme: window.followSystemTheme
        darkTheme: window.darkTheme
        reduceMotion: window.reduceMotion
        recentEntries: typeof recentFiles !== "undefined" ? recentFiles.entries : []
        busy: editor.busy
        availableLocales: typeof language !== "undefined" ? language.availableLocales : []
        localeId: typeof language !== "undefined" ? language.locale : ""
        onFollowSystemThemeToggled: function(checked) { window.followSystemTheme = checked }
        onDarkThemeToggled: function(checked) { window.darkTheme = checked }
        onReduceMotionToggled: function(checked) { window.reduceMotion = checked }
        onLocaleSelected: function(id) {
            if (typeof language !== "undefined") language.setLanguage(id)
        }
        onRecentRequested: function(url) { window.requestOpen(url) }
        onClearRecentRequested: if (typeof recentFiles !== "undefined") recentFiles.clear()
    }

    DropTarget {
        anchors.fill: parent
        busy: editor.busy
        onOpenRequested: function(url) { window.requestOpen(url) }
    }

    ColumnLayout {
        id: shellLayout
        objectName: "keyScope"
        anchors.fill: parent; spacing: 0
        focus: true
        activeFocusOnTab: false
        Keys.onPressed: function(event) { window.handleCanvasKeyPress(event) }
        Keys.onReleased: function(event) { window.handleCanvasKeyRelease(event) }
        TopActionBar {
            actions: window.actionMap
            hasImage: editor.hasImage
            busy: editor.busy
            onTransformRequested: dialogs.openTransformMenu()
            onCanvasSizeRequested: canvasSizeAction.trigger()
            onSettingsRequested: window.openSettings()
            onCommandPaletteRequested: commandPalette.open()
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.border }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            ToolRail {
                activeTool: window.activeTool
                hasImage: editor.hasImage
                busy: editor.busy
                foregroundColor: window.foregroundColor
                onToolSelected: function(tool) { window.activeTool = tool }
                onForegroundColorRequested: dialogs.pickForegroundColor(window.foregroundColor)
            }
            EditorSurface {
                id: canvas
                editorModel: editor
                panels: ({ brush: brushPanel, text: textPanel, shape: shapePanel,
                           mosaic: mosaicPanel, crop: cropPanel })
                settingsObject: typeof settings !== "undefined" ? settings : null
                renderCapabilitiesObject: typeof renderCapabilities !== "undefined"
                                          ? renderCapabilities : null
                recentFilesObject: typeof recentFiles !== "undefined" ? recentFiles : null
                activeTool: window.activeTool
                toolHint: window.activeToolHint
                spacePanActive: window.spacePanActive
                onToolChangeRequested: function(tool) { window.activeTool = tool }
                onStatusRequested: function(message) { window.showStatus(message) }
                onTextObjectActivated: function(info) {
                    window.activeTool = "text"
                    canvas.setSelectionIds([info.id])
                    window.applyTextInfo(info)
                }
                onTextPointChosen: function(imageX, imageY) { window.createTextAt(imageX, imageY) }
                onCropApplyChosen: function(area) { window.applyCrop(area) }
                onMovePreviewStarted: window._awaitingMovePreview = true
                onMovePreviewSettled: window._awaitingMovePreview = false
                onRecentOpenRequested: function(url) { window.requestOpen(url) }
                onOpenDialogRequested: if (!editor.busy) dialogs.openOpenDialog()
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.border }
            Inspector {
                id: inspector
                objectName: "inspector"
                visible: window.activeTool === "adjust"
                Layout.fillHeight: true
                Layout.preferredWidth: window.toolPanelWidth
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
                Layout.preferredWidth: window.toolPanelWidth
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
                Layout.preferredWidth: window.toolPanelWidth
                theme: theme
            }
            TextPanel {
                id: textPanel
                objectName: "textPanel"
                visible: window.activeTool === "text"
                Layout.fillHeight: true
                Layout.preferredWidth: window.toolPanelWidth
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
                Layout.preferredWidth: window.toolPanelWidth
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
                Layout.preferredWidth: window.toolPanelWidth
                theme: theme
            }
            ShapePanel {
                id: shapePanel; objectName: "shapePanel"
                visible: window.activeTool === "shapes"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.toolPanelWidth
                theme: theme
            }
            CropPanel {
                id: cropPanel; objectName: "cropPanel"
                visible: window.activeTool === "crop"
                enabled: editor.hasImage && !editor.busy
                Layout.fillHeight: true
                Layout.preferredWidth: window.toolPanelWidth
                theme: theme
                imageAspectRatio: editor.imageHeight > 0 ? editor.imageWidth / editor.imageHeight : 1
                selectionWidth: canvas.cropSelection.width
                selectionHeight: canvas.cropSelection.height
                canApply: editor.hasImage && !editor.busy && selectionWidth >= 1 && selectionHeight >= 1
                onApplyRequested: window.applyCrop(canvas.cropSelection)
                onCancelRequested: window.activeTool = "adjust"
                onResetRequested: canvas.resetCropSelection()
            }
            ToolInfoPanel {
                objectName: "toolInfoPanel"
                visible: window.activeTool === "pan" || window.activeTool === "eye"
                Layout.preferredWidth: window.toolPanelWidth
                title: window.toolLabel(window.activeTool)
                hint: window.activeToolHint
                iconName: window.activeTool
                shortcut: window.activeTool === "pan" ? window.shortcutFor("pan", "H")
                                                       : window.shortcutFor("eyedropper", "I")
                shortcutLabel: qsTr("Keyboard shortcuts")
            }
        }
        StatusBar {
            hasImage: editor.hasImage
            imageWidth: editor.imageWidth
            imageHeight: editor.imageHeight
            objectCount: window.objectCount
            busy: editor.busy
            dirty: editor.dirty
            transientStatus: window.transientStatus
            zoom: canvas.zoom
            onZoomOutRequested: canvas.changeZoom(1 / 1.2)
            onZoomInRequested: canvas.changeZoom(1.2)
            onZoomValueRequested: function(value) { canvas.setZoomValue(value) }
            onActualSizeRequested: canvas.actualSize()
            onFitRequested: canvas.fitImage()
        }
        Timer { id: statusTimer; interval: 2200; onTriggered: window.transientStatus = "" }
    }

    CommandCatalog {
        id: commandCatalog
        actions: window.actionMap
        busy: editor.busy
        hasImage: editor.hasImage
        languageAvailable: typeof language !== "undefined"
        recentEntries: typeof recentFiles !== "undefined" ? recentFiles.entries : []
        onUndoRequested: editor.undo()
        onRedoRequested: editor.redo()
        onAutoEnhanceRequested: editor.autoEnhance()
        onToggleDarkThemeRequested: {
            window.followSystemTheme = false
            window.darkTheme = !window.darkTheme
        }
        onToggleFollowSystemThemeRequested: window.followSystemTheme = !window.followSystemTheme
        onToggleReduceMotionRequested: window.reduceMotion = !window.reduceMotion
        onLanguageSelected: function(id) {
            if (typeof language !== "undefined") language.setLanguage(id)
        }
        onRecentRequested: function(url) { window.requestOpen(url) }
    }

    CommandPalette {
        id: commandPalette
        objectName: "commandPalette"
        anchors.fill: parent
        commands: commandCatalog.commands
    }
}
