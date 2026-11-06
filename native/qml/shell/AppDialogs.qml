import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
import "../UI"
import "../dialogs"

/*!
    AppDialogs — the shell's modal surfaces.

    The component owns the file pickers, the transform menu and every dialog,
    but never reaches into window ids. External state arrives through
    properties; user intent leaves through signals. This keeps Main as the
    composition root while preserving all objectNames and existing signals.

    Static labels keep the original "Main" translation context so no catalogue
    changes are needed.
*/
Item {
    id: root

    property var actions: ({})
    property var editorModel: null
    property var recoveryService: null
    property var settingsStore: null
    property var languageService: null
    property var formatInfo: ({ readableCount: 0, writableCount: 0 })

    property url lastFolder: ""
    property bool busy: false
    property bool closingRequested: false
    property url pendingImage: ""
    property color foregroundColor: "#eeb99a"
    property bool followSystemTheme: false
    property bool darkTheme: true
    property bool reduceMotion: false
    property string localeId: "zh_CN"

    readonly property string exportFileName: exportDialog.fileName
    readonly property string exportFormatSuffix: exportDialog.formatSuffix
    readonly property bool anyBlockingOpen: exportDialog.opened || resizeDialog.opened
        || canvasSizeDialog.opened || shortcutsDialog.opened || aboutDialog.opened
        || settingsDialog.opened || discardDialog.opened || errorDialog.opened
        || foregroundColorDialog.visible || recoveryDialog.opened

    signal imageOpenRequested(url selectedFile, url folder)
    signal exportDestinationSelected(url selectedFile, url folder)
    signal saveBeforeRequested()
    signal saveBeforeCancelled()
    signal discardAndCloseRequested()
    signal foregroundColorPicked(color value)
    signal exportRequested(string format, var quality, color background)
    signal themeModeChanged(string mode)
    signal reduceMotionRequested(bool value)
    signal startupToolChanged(string tool)

    function openOpenDialog() { openDialog.open() }
    function openSaveDialog() { saveDialog.open() }
    function openTransformMenu() { transformMenu.open() }
    function openResizeDialog() { resizeDialog.open() }
    function openCanvasSizeDialog() { canvasSizeDialog.open() }
    function openShortcutsDialog() {
        if (!shortcutsDialog.opened)
            shortcutsDialog.open()
    }
    function openAboutDialog() {
        if (!aboutDialog.opened)
            aboutDialog.open()
    }
    function showError() {
        if (root.editorModel && root.editorModel.errorMessage.length > 0)
            errorDialog.open()
    }
    function openDiscardDialog() { discardDialog.open() }
    function showRecovery() { recoveryDialog.open() }

    function pickForegroundColor(current) {
        foregroundColorDialog.selectedColor = current
        foregroundColorDialog.open()
    }

    function openSettings() {
        if (root.settingsStore) {
            settingsDialog.themeMode = root.settingsStore.themeMode
            settingsDialog.reduceMotion = root.settingsStore.reduceMotion
            settingsDialog.gpuPreviewEnabled = root.settingsStore.gpuPreviewEnabled
            settingsDialog.exportQuality = root.settingsStore.exportQuality
            settingsDialog.jpegBackground = root.settingsStore.jpegBackground
            settingsDialog.localeId = root.settingsStore.locale
            settingsDialog.confirmOnClose = root.settingsStore.confirmOnClose
            settingsDialog.showCheckerboard = root.settingsStore.showCheckerboard
            settingsDialog.recoveryEnabled = root.settingsStore.recoveryEnabled
            settingsDialog.startupTool = root.settingsStore.startupTool
        } else {
            settingsDialog.themeMode = root.followSystemTheme ? "system"
                                     : root.darkTheme ? "dark" : "light"
            settingsDialog.reduceMotion = root.reduceMotion
            settingsDialog.localeId = root.localeId
        }
        settingsDialog.open()
    }

    function formatSupportsQuality(id) {
        return ["jpeg", "webp", "avif", "heic", "heif", "jxl", "tiff", "png"].indexOf(id) >= 0
    }

    function openExportDialog(formatId, formatLabel, formatSuffix, supportsQuality, fileName) {
        exportDialog.formatId = formatId
        exportDialog.formatLabel = formatLabel
        exportDialog.formatSuffix = formatSuffix
        exportDialog.fileName = fileName
        exportDialog.supportsQuality = supportsQuality
        exportDialog.initialQuality = root.editorModel && root.editorModel.exportQuality >= 0
                                      ? root.editorModel.exportQuality : 90
        exportDialog.initialBackground = root.editorModel ? root.editorModel.jpegBackground : "#ffffff"
        exportDialog.previewUrl = root.editorModel ? root.editorModel.imageUrl : ""
        exportDialog.previewWidth = root.editorModel ? root.editorModel.imageWidth : 0
        exportDialog.previewHeight = root.editorModel ? root.editorModel.imageHeight : 0
        exportDialog.open()
    }

    FileDialog {
        id: openDialog
        title: qsTranslate("Main", "Open image")
        fileMode: FileDialog.OpenFile
        currentFolder: root.lastFolder.toString().length > 0 ? root.lastFolder
                : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: [qsTranslate("Main", "Images") + " ("
                      + (root.editorModel ? root.editorModel.readableImagePatterns.join(" ") : "")
                      + ")", qsTranslate("Main", "All files (*)")]
        onAccepted: root.imageOpenRequested(selectedFile, currentFolder)
    }

    FileDialog {
        id: saveDialog
        title: qsTranslate("Main", "Save image as")
        fileMode: FileDialog.SaveFile
        currentFolder: root.lastFolder.toString().length > 0 ? root.lastFolder
                : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        readonly property var formats: (root.editorModel && root.editorModel.writableFormats)
                                       ? root.editorModel.writableFormats
                                       : [{ id: "png", label: "PNG image",
                                            suffix: "png", patterns: ["*.png"] }]
        readonly property int selectedFormat: selectedNameFilter.index >= 0
                                              && selectedNameFilter.index < formats.length
                                              ? selectedNameFilter.index : 0
        nameFilters: formats.map(function(format) {
            return qsTranslate("Main", format.label) + " (" + format.patterns.join(" ") + ")"
        })
        defaultSuffix: formats[selectedFormat].suffix
        onAccepted: {
            const format = formats[selectedFormat]
            root.exportDestinationSelected(selectedFile, currentFolder)
            root.openExportDialog(format.id, format.label, format.suffix,
                                  root.formatSupportsQuality(format.id),
                                  selectedFile.toString().split("/").pop())
        }
        onRejected: root.saveBeforeCancelled()
    }

    NekoMenu {
        id: transformMenu
        objectName: "transformMenu"
        NekoMenuItem { objectName: "transform-rotate-left"; action: root.actions.rotateLeft }
        NekoMenuItem { objectName: "transform-rotate-right"; action: root.actions.rotateRight }
        NekoMenuSeparator { }
        NekoMenuItem { objectName: "transform-flip-horizontal"; action: root.actions.flipHorizontal }
        NekoMenuItem { objectName: "transform-flip-vertical"; action: root.actions.flipVertical }
    }

    ColorDialog {
        id: foregroundColorDialog
        objectName: "foregroundColorDialog"
        title: qsTranslate("Main", "Foreground colour")
        selectedColor: root.foregroundColor
        onAccepted: root.foregroundColorPicked(selectedColor)
    }

    Dialog {
        id: errorDialog
        objectName: "errorDialog"
        title: qsTranslate("Main", "Unable to complete operation")
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        onClosed: if (root.editorModel) root.editorModel.clearError()
        Label {
            text: root.editorModel ? root.editorModel.errorMessage : ""
            wrapMode: Text.WordWrap
            width: 360
            color: Theme.textPrimary
        }
    }

    Dialog {
        id: discardDialog
        objectName: "discardDialog"
        title: qsTranslate("Main", "Save changes before continuing?")
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        onAccepted: {
            root.saveBeforeRequested()
            if (root.editorModel && root.editorModel.hasPath)
                root.editorModel.saveImage()
            else
                root.openSaveDialog()
        }
        onDiscarded: {
            if (root.closingRequested)
                root.discardAndCloseRequested()
            else if (root.editorModel)
                root.editorModel.openImageDiscardingChanges(root.pendingImage)
        }
        Label {
            text: qsTranslate("Main", "Your unsaved changes will be lost.")
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
            width: 340
        }
    }

    NekoDialog {
        id: aboutDialog
        objectName: "aboutDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTranslate("Main", "About NekoPic")
        acceptText: qsTranslate("Main", "Close")
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
                text: qsTranslate("Main", "A local-first desktop photo editor. Your photos stay on this device.")
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
        sourceName: root.recoveryService ? root.recoveryService.sourceName : ""
        sourcePath: root.recoveryService ? root.recoveryService.sourcePath : ""
        capturedAtText: root.recoveryService ? root.recoveryService.capturedAtText : ""
        imageSizeText: root.recoveryService ? root.recoveryService.imageSizeText : ""
        flattened: root.recoveryService ? root.recoveryService.flattened : true
        onAccepted: if (root.recoveryService) root.recoveryService.restoreRecovery()
        onRejected: if (root.recoveryService) root.recoveryService.discardRecovery()
    }

    ExportDialog {
        id: exportDialog
        objectName: "exportDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        busy: root.busy
        onExportRequested: function(format, quality, background) {
            root.exportRequested(format, quality, background)
        }
        onRejected: root.saveBeforeCancelled()
    }

    ResizeImageDialog {
        id: resizeDialog
        objectName: "resizeImageDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: root.editorModel ? root.editorModel.imageWidth : 0
        imageHeight: root.editorModel ? root.editorModel.imageHeight : 0
        busy: root.busy
        onResizeRequested: function(width, height) {
            if (root.editorModel) root.editorModel.resizeImage(width, height)
        }
    }

    CanvasSizeDialog {
        id: canvasSizeDialog
        objectName: "canvasSizeDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: root.editorModel ? root.editorModel.imageWidth : 0
        imageHeight: root.editorModel ? root.editorModel.imageHeight : 0
        busy: root.busy
        onCanvasResizeRequested: function(width, height, anchor, background) {
            if (root.editorModel)
                root.editorModel.resizeCanvas(width, height, anchor, background)
        }
    }

    SettingsDialog {
        id: settingsDialog
        objectName: "settingsDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        localeOptions: root.languageService ? root.languageService.availableLocales : []
        recoveryAvailable: root.recoveryService ? root.recoveryService.hasRecovery : false
        recoverySourceName: root.recoveryService ? root.recoveryService.sourceName : ""
        recoveryCapturedAt: root.recoveryService ? root.recoveryService.capturedAtText : ""
        recoveryImageSize: root.recoveryService ? root.recoveryService.imageSizeText : ""
        formatCapabilities: root.formatInfo
        onSettingChanged: function(key, value) {
            if (!root.settingsStore) return
            root.settingsStore[key] = value
            if (key === "themeMode")
                root.themeModeChanged(value)
            else if (key === "reduceMotion")
                root.reduceMotionRequested(value)
            else if (key === "exportQuality" && root.editorModel)
                root.editorModel.exportQuality = value
            else if (key === "jpegBackground" && root.editorModel)
                root.editorModel.jpegBackground = value
            else if (key === "recoveryEnabled" && root.recoveryService)
                root.recoveryService.autosaveEnabled = value
            else if (key === "startupTool")
                root.startupToolChanged(value)
        }
        onLocaleSelected: function(id) {
            if (root.settingsStore) root.settingsStore.locale = id
            if (root.languageService) root.languageService.setLanguage(id)
        }
        onShortcutsRequested: root.openShortcutsDialog()
        onRecoveryDiscardRequested: {
            if (root.recoveryService) root.recoveryService.discardRecovery()
        }
    }

    ShortcutsDialog {
        id: shortcutsDialog
        objectName: "shortcutsDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
    }
}
