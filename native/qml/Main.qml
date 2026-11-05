import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import "UI"
import "shell"
import "dialogs"

ApplicationWindow {
    id: window
    width: 1440; height: 900; minimumWidth: 860; minimumHeight: 600
    visible: true
    title: (editor.hasImage ? editor.fileName + (editor.dirty ? " *" : "") + " - " : "") + "NekoPic"
    property bool darkTheme: true
    property bool followSystemTheme: false
    readonly property bool systemDark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    // Letter shortcuts must not fire while the user is typing in a modal.
    readonly property bool blockingModal: commandPalette.opened || textDialog.opened
        || exportDialog.opened || resizeDialog.opened || canvasSizeDialog.opened
        || shortcutsDialog.opened || aboutDialog.opened || discardDialog.opened || errorDialog.opened
    property bool discardConfirmed: false
    property bool saveBeforePending: false
    property bool closingRequested: false
    property url pendingImage
    property url pendingExportUrl
    property url lastFolder: ""
    property string activeTool: "adjust"
    property string transientStatus: ""
    property bool reduceMotion: false
    function showStatus(message) { transientStatus = message; statusTimer.restart() }
    function openTextDialog(imageX, imageY) {
        textDialog.text = ""
        textDialog.anchorX = imageX
        textDialog.anchorY = imageY
        textDialog.open()
    }
    function formatSupportsQuality(id) {
        return ["jpeg", "webp", "avif", "heic", "heif", "jxl", "tiff", "png"].indexOf(id) >= 0
    }
    function applyCrop(area) {
        if (!editor.hasImage || editor.busy) return
        editor.cropImage(area)
        activeTool = "adjust"
    }
    onActiveToolChanged: if (activeTool === "adjust" || activeTool === "filters")
                            inspector.currentTab = activeTool === "filters" ? 1 : 0
    onClosing: function(close) {
        if (editor.busy || (editor.dirty && !discardConfirmed)) {
            close.accepted = false
            if (!editor.busy) { closingRequested = true; discardDialog.open() }
        }
    }
    Settings { category: "ui"; property alias darkTheme: window.darkTheme; property alias reduceMotion: window.reduceMotion; property alias followSystemTheme: window.followSystemTheme; property alias lastFolder: window.lastFolder }
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
    Action { id: commandPaletteAction; text: qsTr("Command palette…"); shortcut: "Ctrl+K"; onTriggered: commandPalette.opened ? commandPalette.close() : commandPalette.open() }
    Action { id: copyAction; text: qsTr("Copy image"); shortcut: "Ctrl+Shift+C"; enabled: editor.hasImage && !editor.busy; onTriggered: { editor.copyImageToClipboard(); window.showStatus(qsTr("Copied to clipboard")) } }
    Action { id: undoAction; text: qsTr("Undo"); shortcut: StandardKey.Undo; enabled: editor.canUndo && !editor.busy; onTriggered: editor.undo() }
    Action { id: redoAction; text: qsTr("Redo"); shortcut: StandardKey.Redo; enabled: editor.canRedo && !editor.busy; onTriggered: editor.redo() }
    Action { id: rotateRightAction; text: qsTr("Rotate clockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateClockwise() }
    Action { id: rotateLeftAction; text: qsTr("Rotate counterclockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateCounterClockwise() }
    Action { id: flipHorizontalAction; text: qsTr("Flip horizontally"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipHorizontal() }
    Action { id: flipVerticalAction; text: qsTr("Flip vertically"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipVertical() }
    Action { id: resizeImageAction; text: qsTr("Resize image…"); enabled: editor.hasImage && !editor.busy; onTriggered: resizeDialog.open() }
    Action { id: canvasSizeAction; text: qsTr("Canvas size…"); enabled: editor.hasImage && !editor.busy; onTriggered: canvasSizeDialog.open() }
    Action { id: shortcutsAction; text: qsTr("Keyboard shortcuts"); shortcut: "F1"; onTriggered: shortcutsDialog.open() }
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
            if (editor.dirty) {
                window.pendingImage = selectedFile
                window.closingRequested = false
                discardDialog.open()
            } else {
                editor.openImage(selectedFile)
            }
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
            exportDialog.fileName = selectedFile.toString().split("/").pop()
            exportDialog.supportsQuality = window.formatSupportsQuality(format.id)
            exportDialog.initialQuality = editor.exportQuality >= 0 ? editor.exportQuality : 90
            exportDialog.initialBackground = editor.jpegBackground
            exportDialog.open()
        }
        onRejected: if (window.saveBeforePending) window.saveBeforePending = false
    }
    Dialog {
        id: errorDialog; title: qsTr("Unable to complete operation"); modal: true
        anchors.centerIn: parent; standardButtons: Dialog.Ok
        onClosed: editor.clearError()
        Label { text: editor.errorMessage; wrapMode: Text.WordWrap; width: 360; color: theme.text }
    }
    Dialog {
        id: discardDialog; title: qsTr("Save changes before continuing?"); modal: true
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
    ExportDialog {
        id: exportDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        busy: editor.busy
        onExportRequested: function(format, quality, background) {
            editor.exportQuality = quality
            editor.jpegBackground = background
            editor.saveAs(window.pendingExportUrl, format)
        }
        onRejected: if (window.saveBeforePending) window.saveBeforePending = false
    }
    ResizeImageDialog {
        id: resizeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: editor.imageWidth
        imageHeight: editor.imageHeight
        busy: editor.busy
        onResizeRequested: function(width, height) { editor.resizeImage(width, height) }
    }
    CanvasSizeDialog {
        id: canvasSizeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: editor.imageWidth
        imageHeight: editor.imageHeight
        busy: editor.busy
        onCanvasResizeRequested: function(width, height, anchor, background) {
            editor.resizeCanvas(width, height, anchor, background)
        }
    }
    TextDialog {
        id: textDialog
        objectName: "textDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        imageWidth: editor.imageWidth
        imageHeight: editor.imageHeight
        busy: editor.busy
        onTextRequested: function(text, imageX, imageY, fontSize, color, alignment) {
            editor.addText(text, imageX, imageY, fontSize, color, alignment)
        }
        onClosed: if (window.activeTool === "text") window.activeTool = "adjust"
    }
    ShortcutsDialog {
        id: shortcutsDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
    }
    Connections {
        target: editor
        function onErrorChanged() { if (editor.errorMessage.length > 0) errorDialog.open() }
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
                title: qsTr("Open recent")
                enabled: typeof recentFiles !== "undefined" && recentFiles.entries.length > 0
                Repeater {
                    model: typeof recentFiles !== "undefined" ? recentFiles.entries : []
                    MenuItem {
                        required property var modelData
                        text: modelData.name
                        onTriggered: {
                            if (editor.dirty) {
                                window.pendingImage = modelData.url
                                window.closingRequested = false
                                discardDialog.open()
                            } else {
                                editor.openImage(modelData.url)
                            }
                        }
                    }
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Clear recent files")
                    enabled: typeof recentFiles !== "undefined" && recentFiles.entries.length > 0
                    onTriggered: if (typeof recentFiles !== "undefined") recentFiles.clear()
                }
            }
            MenuSeparator {}
            MenuItem { action: saveAction }
            MenuItem { action: saveAsAction }
        }
        Menu { title: qsTr("Edit"); MenuItem { action: undoAction } MenuItem { action: redoAction } MenuSeparator {} MenuItem { action: copyAction } }
        Menu { title: qsTr("Image"); MenuItem { action: rotateLeftAction } MenuItem { action: rotateRightAction } MenuItem { action: flipHorizontalAction } MenuItem { action: flipVerticalAction } MenuSeparator {} MenuItem { action: selectAction } MenuItem { action: cropAction } MenuItem { action: textAction } MenuItem { action: eyedropperAction } MenuSeparator {} MenuItem { action: resizeImageAction } MenuItem { action: canvasSizeAction } }
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
            const target = drop.urls[0]
            if (editor.dirty) {
                window.pendingImage = target
                window.closingRequested = false
                discardDialog.open()
            } else {
                editor.openImage(target)
            }
            drop.acceptProposedAction()
        }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
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
                Item { Layout.fillWidth: true }
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
                Flickable {
                    anchors.fill: parent; contentHeight: tools.implicitHeight + 20; clip: true; boundsBehavior: Flickable.StopAtBounds
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
                                readonly property bool available: modelData.icon === "select" || modelData.icon === "adjust" || modelData.icon === "filters" || modelData.icon === "mosaic" || modelData.icon === "text" || modelData.icon === "eye" || modelData.icon === "crop"
                                enabled: available && !editor.busy && (modelData.icon !== "crop" || editor.hasImage)
                                checked: available && window.activeTool === modelData.icon
                                onClicked: window.activeTool = modelData.icon
                                ToolTip.visible: hovered
                                ToolTip.text: available ? modelData.label : modelData.label + " · " + qsTr("Coming soon")
                            }
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
                adjustmentPreviewActive: typeof editor.adjustmentInteractive !== "undefined"
                                         && editor.adjustmentInteractive
                                         && (typeof editor.filterPreset === "undefined" || editor.filterPreset === "none")
                previewExposure: typeof editor.pendingAdjustmentValues !== "undefined"
                                 && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.exposure / 50 : 0
                previewBrightness: typeof editor.pendingAdjustmentValues !== "undefined"
                                   && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.brightness / 100 : 0
                previewContrast: typeof editor.pendingAdjustmentValues !== "undefined"
                                 && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.contrast / 100 : 0
                previewSaturation: typeof editor.pendingAdjustmentValues !== "undefined"
                                   && editor.pendingAdjustmentValues ? editor.pendingAdjustmentValues.saturation / 100 : 0
                fileName: editor.fileName; dirty: editor.dirty
                mosaicActive: window.activeTool === "mosaic"
                cropActive: window.activeTool === "crop"
                eyedropperActive: window.activeTool === "eye"
                textActive: window.activeTool === "text"
                selectionActive: window.activeTool === "select"
                objectAt: function(x, y) { return editor.objectAt(x, y) }
                objectBounds: function(id) { return editor.objectBounds(id) }
                onMoveObjectRequested: function(id, dx, dy) { editor.moveObject(id, dx, dy) }
                onRemoveObjectRequested: function(id) { editor.removeObject(id) }
                onTextPointSelected: function(imageX, imageY) { window.openTextDialog(imageX, imageY) }
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
                onRecentRequested: function(url) { editor.openImage(url) }
                onOpenRequested: openDialog.open()
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.border }
            Inspector {
                id: inspector
                objectName: "inspector"
                visible: window.activeTool === "adjust" || window.activeTool === "filters"
                onCurrentTabChanged: if (visible) window.activeTool = currentTab === 1 ? "filters" : "adjust"
                Layout.fillHeight: true
                Layout.preferredWidth: window.width < 1100 ? 260 : 292
                theme: theme
                adjustmentsEnabled: editor.hasImage && (!editor.busy || editor.adjustmentInteractive)
                adjustmentValues: editor.adjustmentValues
                onAdjustmentStarted: function(key) { editor.beginAdjustment(key) }
                onAdjustmentPreview: function(key, value) { editor.previewAdjustment(key, value) }
                onAdjustmentFinished: function(key, value) { editor.finishAdjustment(key, value) }
                onAdjustmentReset: editor.resetAdjustments()
                filtersEnabled: editor.hasImage && !editor.busy
                filterIntensityEnabled: editor.hasImage && (!editor.busy || editor.filterIntensityInteractive)
                filterPreset: editor.filterPreset
                previewsAvailable: filterPreviews.ready
                previewRevision: filterPreviews.revision
                filterIntensity: editor.filterIntensity
                onFilterSelected: function(preset) { editor.selectFilter(preset) }
                onFilterIntensityStarted: editor.beginFilterIntensity()
                onFilterIntensityPreview: function(value) { editor.previewFilterIntensity(value) }
                onFilterIntensityFinished: function(value) { editor.finishFilterIntensity(value) }
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
            Layout.fillWidth: true; Layout.preferredHeight: 27; color: theme.panel
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 15
                Label { text: editor.hasImage ? editor.imageWidth + " × " + editor.imageHeight + " px" : "— × — px"; color: theme.muted; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Label { text: window.transientStatus.length > 0 ? window.transientStatus : (editor.busy ? qsTr("Working…") : editor.dirty ? qsTr("Unsaved changes") : qsTr("Local editing")); color: theme.muted; font.pixelSize: 10 }
                Timer { id: statusTimer; interval: 2200; onTriggered: window.transientStatus = "" }
            }
        }
    }

    CommandPalette {
        id: commandPalette
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
            { title: cropAction.text, detail: qsTr("Tools"), shortcut: "C", enabled: cropAction.enabled,
              run: function() { window.activeTool = "crop" } },
            { title: selectAction.text, detail: qsTr("Tools"), shortcut: "V", enabled: selectAction.enabled,
              run: function() { window.activeTool = "select" } },
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
                                run: function() { editor.openImage(entry.url) } }
                   })
                 : [])
    }
}
