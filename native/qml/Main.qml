import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    width: 1440; height: 900; minimumWidth: 860; minimumHeight: 600
    visible: true
    title: (editor.hasImage ? editor.fileName + (editor.dirty ? " *" : "") + " - " : "") + "NekoPic"
    property bool darkTheme: true
    property bool discardConfirmed: false
    property bool closingRequested: false
    property url pendingImage
    property string activeTool: "adjust"
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
    Settings { category: "ui"; property alias darkTheme: window.darkTheme }
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
        readonly property color background: window.darkTheme ? "#181a1b" : "#edece8"
        readonly property color panel: window.darkTheme ? "#222426" : "#f7f6f2"
        readonly property color canvas: window.darkTheme ? "#151718" : "#dcded9"
        readonly property color raised: window.darkTheme ? "#2b2d2f" : "#ffffff"
        readonly property color hover: window.darkTheme ? "#343638" : "#e6e5df"
        readonly property color text: window.darkTheme ? "#e9e9e6" : "#303734"
        readonly property color muted: window.darkTheme ? "#929794" : "#68716b"
        readonly property color border: window.darkTheme ? "#343638" : "#d6d7d1"
        readonly property color accent: window.darkTheme ? "#edbc9d" : "#a45934"
        readonly property color accentInk: window.darkTheme ? "#292420" : "#fff6ed"
    }

    component Icon: Canvas {
        property string name: ""
        property color ink: theme.muted
        implicitWidth: 18; implicitHeight: 18
        onNameChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset(); c.scale(width / 24, height / 24)
            c.strokeStyle = ink; c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round"; c.beginPath()
            if (name === "logo") { c.moveTo(4,18); c.lineTo(4,5); c.lineTo(12,12); c.lineTo(20,5); c.lineTo(20,18); c.moveTo(8,18); c.lineTo(8,14); c.moveTo(16,18); c.lineTo(16,14) }
            else if (name === "folder") { c.moveTo(3,7); c.lineTo(10,7); c.lineTo(12,9); c.lineTo(21,9); c.lineTo(21,19); c.lineTo(3,19); c.closePath() }
            else if (name === "save") { c.moveTo(4,3); c.lineTo(17,3); c.lineTo(21,7); c.lineTo(21,21); c.lineTo(3,21); c.lineTo(3,3); c.moveTo(7,3); c.lineTo(7,9); c.lineTo(17,9); c.lineTo(17,3); c.moveTo(7,21); c.lineTo(7,13); c.lineTo(17,13); c.lineTo(17,21) }
            else if (name === "undo" || name === "redo") { if (name === "redo") { c.translate(24,0); c.scale(-1,1) }; c.moveTo(8,4); c.lineTo(3,9); c.lineTo(8,14); c.moveTo(3,9); c.lineTo(14,9); c.quadraticCurveTo(21,9,21,16); c.lineTo(21,20) }
            else if (name === "rotate") { c.arc(12,12,9,-2.9,2.4); c.moveTo(3,3); c.lineTo(3,10); c.lineTo(10,10) }
            else if (name === "crop") { c.moveTo(6,2); c.lineTo(6,16); c.lineTo(22,16); c.moveTo(2,6); c.lineTo(18,6); c.lineTo(18,22) }
            else if (name === "adjust") { c.moveTo(3,7); c.lineTo(21,7); c.moveTo(3,17); c.lineTo(21,17); c.moveTo(12,7); c.arc(9,7,3,0,Math.PI*2); c.moveTo(19,17); c.arc(16,17,3,0,Math.PI*2) }
            else if (name === "filters") { c.moveTo(12,3); c.lineTo(14.5,9.5); c.lineTo(21,12); c.lineTo(14.5,14.5); c.lineTo(12,21); c.lineTo(9.5,14.5); c.lineTo(3,12); c.lineTo(9.5,9.5); c.closePath() }
            else if (name === "brush") { c.moveTo(11,12); c.lineTo(19,3); c.lineTo(21,5); c.lineTo(13,14); c.moveTo(11,12); c.lineTo(13,14); c.moveTo(10,13); c.quadraticCurveTo(4,12,4,17); c.lineTo(2,21); c.quadraticCurveTo(10,21,10,17) }
            else if (name === "text") { c.moveTo(4,6); c.lineTo(4,3); c.lineTo(20,3); c.lineTo(20,6); c.moveTo(12,3); c.lineTo(12,21); c.moveTo(8,21); c.lineTo(16,21) }
            else if (name === "shapes") { c.rect(3,3,12,12); c.moveTo(22,16); c.arc(16,16,6,0,Math.PI*2) }
            else if (name === "mosaic") { c.rect(3,3,7,7); c.rect(14,3,7,7); c.rect(3,14,7,7); c.rect(14,14,7,7) }
            else if (name === "select") { c.moveTo(5,3); c.lineTo(20,13); c.lineTo(13,14); c.lineTo(10,21); c.closePath() }
            else if (name === "pan") { c.moveTo(8,12); c.lineTo(8,5); c.quadraticCurveTo(10,2,12,5); c.lineTo(12,11); c.lineTo(12,4); c.quadraticCurveTo(14,1,16,4); c.lineTo(16,11); c.lineTo(16,6); c.quadraticCurveTo(18,3,20,6); c.lineTo(20,15); c.quadraticCurveTo(20,22,13,22); c.quadraticCurveTo(9,22,7,18); c.lineTo(3,12); c.quadraticCurveTo(4,9,6,11); c.lineTo(8,13) }
            c.stroke()
        }
    }
    component CommandButton: Button {
        id: command
        property string iconName: ""
        property bool primary: false
        implicitHeight: 34; implicitWidth: content.implicitWidth + 20
        padding: 0
        background: Rectangle { radius: 5; color: command.primary && command.enabled ? theme.accent : command.hovered && command.enabled ? theme.hover : "transparent" }
        contentItem: RowLayout {
            id: content; spacing: 7
            Icon { visible: command.iconName !== ""; name: command.iconName; ink: command.primary && command.enabled ? theme.accentInk : theme.muted; opacity: command.enabled ? 1 : 0.35; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
            Label { visible: command.text.length > 0; text: command.text; color: command.primary && command.enabled ? theme.accentInk : theme.text; opacity: command.enabled ? 1 : 0.35; font.pixelSize: 11; font.weight: command.primary ? Font.DemiBold : Font.Normal }
        }
    }

    Action { id: openAction; text: qsTr("Open image…"); shortcut: StandardKey.Open; enabled: !editor.busy; onTriggered: openDialog.open() }
    Action { id: saveAction; text: qsTr("Save"); shortcut: StandardKey.Save; enabled: editor.hasImage && !editor.busy; onTriggered: editor.saveImage() }
    Action { id: saveAsAction; text: qsTr("Save as…"); shortcut: StandardKey.SaveAs; enabled: editor.hasImage && !editor.busy; onTriggered: saveDialog.open() }
    Action { id: undoAction; text: qsTr("Undo"); shortcut: StandardKey.Undo; enabled: editor.canUndo && !editor.busy; onTriggered: editor.undo() }
    Action { id: redoAction; text: qsTr("Redo"); shortcut: StandardKey.Redo; enabled: editor.canRedo && !editor.busy; onTriggered: editor.redo() }
    Action { id: rotateRightAction; text: qsTr("Rotate clockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateClockwise() }
    Action { id: rotateLeftAction; text: qsTr("Rotate counterclockwise"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.rotateCounterClockwise() }
    Action { id: flipHorizontalAction; text: qsTr("Flip horizontally"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipHorizontal() }
    Action { id: flipVerticalAction; text: qsTr("Flip vertically"); enabled: editor.hasImage && !editor.busy; onTriggered: editor.flipVertical() }
    Action { id: cropAction; text: qsTr("Crop"); shortcut: "C"; enabled: editor.hasImage && !editor.busy; onTriggered: window.activeTool = "crop" }
    Action { id: fitAction; text: qsTr("Fit to window"); shortcut: "Ctrl+0"; enabled: editor.hasImage; onTriggered: canvas.fitImage() }
    Action { id: actualAction; text: qsTr("Actual size (100%)"); shortcut: "Ctrl+1"; enabled: editor.hasImage; onTriggered: canvas.actualSize() }
    FileDialog {
        id: openDialog; title: qsTr("Open image"); fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Images") + " (" + editor.readableImagePatterns.join(" ") + ")", qsTr("All files (*)")]
        onAccepted: {
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
        nameFilters: [qsTr("PNG image (*.png)"), qsTr("JPEG image (*.jpg *.jpeg)")]
        defaultSuffix: selectedNameFilter.index === 1 ? "jpg" : "png"
        onAccepted: editor.saveAs(selectedFile, selectedNameFilter.index === 1 ? "jpeg" : "png")
    }
    Dialog {
        id: errorDialog; title: qsTr("Unable to complete operation"); modal: true
        anchors.centerIn: parent; standardButtons: Dialog.Ok
        onClosed: editor.clearError()
        Label { text: editor.errorMessage; wrapMode: Text.WordWrap; width: 360; color: theme.text }
    }
    Dialog {
        id: discardDialog; title: qsTr("Discard unsaved changes?"); modal: true
        anchors.centerIn: parent; standardButtons: Dialog.Discard | Dialog.Cancel
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
    Connections { target: editor; function onErrorChanged() { if (editor.errorMessage.length > 0) errorDialog.open() } }

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
        Menu { title: qsTr("File"); MenuItem { action: openAction } MenuSeparator {} MenuItem { action: saveAction } MenuItem { action: saveAsAction } }
        Menu { title: qsTr("Edit"); MenuItem { action: undoAction } MenuItem { action: redoAction } }
        Menu { title: qsTr("Image"); MenuItem { action: rotateLeftAction } MenuItem { action: rotateRightAction } MenuItem { action: flipHorizontalAction } MenuItem { action: flipVerticalAction } MenuSeparator {} MenuItem { action: cropAction } }
        Menu {
            title: qsTr("View")
            MenuItem { action: fitAction } MenuItem { action: actualAction } MenuSeparator {}
            MenuItem { text: qsTr("Dark theme"); checkable: true; checked: window.darkTheme; onTriggered: window.darkTheme = checked }
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
                                { icon: "crop", label: qsTr("Crop") }
                            ]
                            delegate: ToolButton {
                                id: toolButton
                                required property var modelData; required property int index
                                Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 52; Layout.preferredHeight: 52
                                Layout.topMargin: index === 2 || index === 4 ? 10 : 0
                                objectName: "tool-" + modelData.icon
                                readonly property bool available: modelData.icon === "adjust" || modelData.icon === "filters" || modelData.icon === "mosaic" || modelData.icon === "crop"
                                enabled: available && !editor.busy && (modelData.icon !== "crop" || editor.hasImage)
                                checkable: available; checked: available && window.activeTool === modelData.icon
                                onClicked: window.activeTool = modelData.icon
                                ToolTip.visible: hovered; ToolTip.text: available ? modelData.label : modelData.label + " · " + qsTr("Coming soon")
                                background: Rectangle {
                                    radius: 6; color: toolButton.checked ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.08) : toolButton.hovered && toolButton.enabled ? theme.hover : "transparent"
                                    Rectangle { visible: toolButton.checked; x: -11; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 18; radius: 1; color: theme.accent }
                                    Rectangle { visible: toolButton.index === 2 || toolButton.index === 4; x: 0; y: -7; width: parent.width; height: 1; color: theme.border }
                                }
                                contentItem: ColumnLayout {
                                    spacing: 3
                                    Icon { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 19; Layout.preferredHeight: 19; name: toolButton.modelData.icon; ink: toolButton.checked ? theme.accent : theme.muted; opacity: toolButton.enabled ? 1 : 0.4 }
                                    Label { Layout.alignment: Qt.AlignHCenter; text: toolButton.modelData.label; color: toolButton.checked ? theme.accent : theme.muted; opacity: toolButton.enabled ? 1 : 0.4; font.pixelSize: 9 }
                                }
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
                fileName: editor.fileName; dirty: editor.dirty
                mosaicActive: window.activeTool === "mosaic"
                cropActive: window.activeTool === "crop"
                cropAspectRatio: cropPanel.aspectRatio
                onCropApplyRequested: function(area) { window.applyCrop(area) }
                onCropCancelled: window.activeTool = "adjust"
                mosaicBrushMode: mosaicPanel.brushMode
                mosaicBrushDiameter: mosaicPanel.brushDiameter
                inputEnabled: !editor.busy
                onMosaicRectangleCommitted: function(area) { editor.mosaicRectangle(area, mosaicPanel.blockSize) }
                onMosaicStrokeCommitted: function(points) { editor.mosaicStroke(points, mosaicPanel.brushDiameter, mosaicPanel.blockSize) }
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
                Label { text: editor.busy ? qsTr("Working…") : qsTr("Local editing"); color: theme.muted; font.pixelSize: 10 }
            }
        }
    }
}
