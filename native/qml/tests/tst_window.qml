import QtQuick
import QtTest
import ".."

TestCase {
    name: "Window"
    QtObject {
        id: filterPreviews
        property bool ready: false
        property double revision: 0
    }
    function visualChild(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; ++i) {
            const child = visualChild(item.children[i], name)
            if (child) return child
        }
        return null
    }
    QtObject {
        id: editor
        property string fileName: ""
        property url imageUrl: ""
        property bool busy: false
        property string errorMessage: ""
        property bool hasImage: false
        property int imageWidth: 0
        property int imageHeight: 0
        property bool dirty: false
        property bool adjustmentInteractive: false
        property var adjustmentValues: ({})
        property string filterPreset: "none"
        property real filterIntensity: 100
        property bool filterIntensityInteractive: false
        property string filterCall: ""
        property string adjustmentCall: ""
        property int mosaicCalls: 0
        property rect mosaicArea
        property var mosaicPoints: []
        property real mosaicDiameter: 0
        property int mosaicBlockSize: 0
        property int blurCalls: 0
        property int blurStrokeCalls: 0
        property rect blurArea
        property int blurRadius: 0
        property var blurPoints: []
        property int moveCalls: 0
        property int removeCalls: 0
        property real moveDx: 0
        property real moveDy: 0
        property int lastObjectId: 0
        property var lastObjectIds: []
        function objectSummaries() { return [] }
        function moveObjects(ids, dx, dy) { ++moveCalls; lastObjectIds = ids; moveDx = dx; moveDy = dy }
        function removeObjects(ids) { ++removeCalls; lastObjectIds = ids }
        function setObjectVisible(id, visible) { return true }
        function setObjectLocked(id, locked) { return true }
        function bringObjectToFront(id) { return true }
        function sendObjectToBack(id) { return true }
        function raiseObject(id) { return true }
        function lowerObject(id) { return true }
        function alignObjects(ids, alignment) { return true }
        property int cropCalls: 0
        property string textCall: ""
        property rect cropArea
        property var readableImagePatterns: ["*.png", "*.PNG"]
        signal errorChanged()
        signal imageSaved()
        property int openCalls: 0
        property var lastOpenUrl
        property int openDiscardingCalls: 0
        property int autoEnhanceCalls: 0
        function openImage(url) { ++openCalls; lastOpenUrl = url }
        function openImageDiscardingChanges(url) { ++openDiscardingCalls; lastOpenUrl = url }
        function autoEnhance() { ++autoEnhanceCalls }
        function saveImage() {}
        function saveAs(url, format) {}
        function clearError() {}
        function objectAt(x, y) { return 7 }
        function objectBounds(id) { return Qt.rect(100, 50, 80, 40) }
        function moveObject(id, dx, dy) { ++moveCalls; lastObjectId = id; moveDx = dx; moveDy = dy }
        function removeObject(id) { ++removeCalls; lastObjectId = id; return true }
        function addText(text, x, y, fontSize, color, alignment) {
            textCall = text + ":" + x + ":" + y + ":" + fontSize + ":" + alignment
        }
        function addTextStyled(text, x, y, fontFamily, fontWeight, fontSize, color, alignment,
                               outlineColor, outlineWidth, lineHeight, padding) {
            textCall = text + ":" + x + ":" + y + ":" + fontSize + ":" + alignment
        }
        function beginAdjustment(key) { adjustmentCall = "begin:" + key }
        function previewAdjustment(key, value) { adjustmentCall = "preview:" + key + ":" + value }
        function finishAdjustment(key, value) { adjustmentCall = "finish:" + key + ":" + value }
        function selectFilter(preset) { filterCall = "select:" + preset }
        function beginFilterIntensity() { filterCall = "begin" }
        function previewFilterIntensity(value) { filterCall = "preview:" + value }
        function finishFilterIntensity(value) { filterCall = "finish:" + value }
        function mosaicRectangle(area, blockSize) {
            ++mosaicCalls; mosaicArea = area; mosaicBlockSize = blockSize
        }
        function blurRectangle(area, radius) {
            ++blurCalls; blurArea = area; blurRadius = radius
        }
        function blurStroke(points, radius) {
            ++blurStrokeCalls; blurPoints = points; blurRadius = radius
        }
        function mosaicStroke(points, diameter, blockSize) {
            ++mosaicCalls; mosaicPoints = points; mosaicDiameter = diameter; mosaicBlockSize = blockSize
        }
        function cropImage(area) { ++cropCalls; cropArea = area }
    }
    function test_initialState() {
        let component = Qt.createComponent("../Main.qml")
        compare(component.status, Component.Ready, component.errorString())
        let window = component.createObject(null)
        verify(window !== null, component.errorString())
        compare(window.title, "NekoPic")
        window.darkTheme = true
        verify(window.darkTheme)
        window.darkTheme = false
        verify(!window.darkTheme)
        window.destroy()
    }
    function test_cropToolRoutesAndCancels() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        const canvas = findChild(window, "editorCanvas")
        const panel = findChild(window, "cropPanel")
        const tool = visualChild(window.contentItem, "tool-crop")
        verify(panel !== null && tool !== null)
        editor.hasImage = true; editor.imageWidth = 1000; editor.imageHeight = 500
        editor.cropCalls = 0
        verify(tool.enabled)
        tool.clicked()
        compare(window.activeTool, "crop")
        verify(panel.visible && canvas.cropActive)
        panel.aspectRatio = 1
        compare(canvas.cropSelection, Qt.rect(250, 0, 500, 500))
        panel.applyRequested()
        compare(editor.cropCalls, 1)
        compare(editor.cropArea, Qt.rect(250, 0, 500, 500))
        compare(window.activeTool, "adjust")
        tool.clicked()
        canvas.cropCancelled()
        compare(window.activeTool, "adjust")
        tool.clicked()
        editor.busy = true
        verify(!panel.canApply)
        verify(!tool.enabled)
        editor.busy = false
        panel.cancelRequested()
        compare(editor.cropCalls, 1)
        editor.hasImage = false; editor.imageWidth = 0; editor.imageHeight = 0
        window.destroy()
    }
    function test_adjustmentsConnected() {
        let component = Qt.createComponent("../Main.qml")
        let window = component.createObject(null)
        verify(window !== null, component.errorString())
        let inspector = findChild(window, "inspector")
        verify(inspector !== null)
        editor.hasImage = true
        verify(inspector.adjustmentsEnabled)
        inspector.adjustmentStarted("exposure")
        compare(editor.adjustmentCall, "begin:exposure")
        inspector.adjustmentPreview("exposure", 35)
        compare(editor.adjustmentCall, "preview:exposure:35")
        inspector.adjustmentFinished("exposure", 35)
        compare(editor.adjustmentCall, "finish:exposure:35")
        editor.hasImage = false
        window.destroy()
    }
    function test_filtersConnectedAndBusyGated() {
        let component = Qt.createComponent("../Main.qml")
        let window = component.createObject(null)
        verify(window !== null, component.errorString())
        let inspector = findChild(window, "inspector")
        editor.hasImage = true
        editor.filterPreset = "warm"
        editor.filterIntensity = 45
        compare(inspector.filterPreset, "warm")
        compare(inspector.filterIntensity, 45)
        inspector.filterSelected("mono")
        compare(editor.filterCall, "select:mono")
        inspector.filterIntensityStarted()
        compare(editor.filterCall, "begin")
        inspector.filterIntensityPreview(42)
        compare(editor.filterCall, "preview:42")
        inspector.filterIntensityFinished(35)
        compare(editor.filterCall, "finish:35")
        editor.busy = true
        editor.filterIntensityInteractive = true
        verify(!inspector.filtersEnabled)
        editor.busy = false
        editor.filterIntensityInteractive = false
        editor.hasImage = false
        window.destroy()
    }
    function test_selectionToolRoutesMoveAndRemove() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        editor.hasImage = true
        editor.imageWidth = 1000; editor.imageHeight = 500
        editor.moveCalls = 0; editor.removeCalls = 0
        const tool = visualChild(window.contentItem, "tool-select")
        verify(tool !== null)
        tool.clicked()
        compare(window.activeTool, "select")
        const canvas = findChild(window, "editorCanvas")
        verify(canvas.selectionActive)
        const overlay = findChild(canvas, "selectionOverlay")
        verify(overlay !== null)
        compare(overlay.selectAt(110, 60), 7)
        compare(overlay.selectedId, 7)
        verify(findChild(window, "layerPanel").visible)
        canvas.moveObjectsRequested([7], 5, 6)
        compare(editor.moveCalls, 1)
        compare(editor.moveDx, 5)
        compare(editor.moveDy, 6)
        compare(editor.lastObjectIds.length, 1)
        canvas.removeObjectsRequested([7])
        compare(editor.removeCalls, 1)
        editor.hasImage = false
        window.destroy()
    }

    function test_mosaicPanelRoutesBlurEffect() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        const panel = findChild(window, "mosaicPanel")
        const canvas = findChild(window, "editorCanvas")
        verify(panel !== null && canvas !== null)
        editor.hasImage = true
        editor.imageWidth = 1000; editor.imageHeight = 500
        editor.blurCalls = 0; editor.blurStrokeCalls = 0; editor.mosaicCalls = 0
        panel.effect = "blur"
        panel.blurRadius = 21
        canvas.mosaicRectangleCommitted(Qt.rect(10, 20, 100, 60))
        compare(editor.blurCalls, 1)
        compare(editor.mosaicCalls, 0)
        compare(editor.blurArea, Qt.rect(10, 20, 100, 60))
        compare(editor.blurRadius, 21)
        canvas.mosaicStrokeCommitted([Qt.point(30, 40), Qt.point(50, 60)])
        compare(editor.blurStrokeCalls, 1)
        compare(editor.blurPoints.length, 2)
        compare(editor.blurRadius, 21)
        panel.effect = "mosaic"
        editor.hasImage = false
        window.destroy()
    }

    function test_settingsButtonOpensDialog() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        const button = visualChild(window.contentItem, "settingsButton")
        verify(button !== null)
        mouseClick(button)
        const dialog = findChild(window, "settingsDialog")
        verify(dialog !== null)
        tryVerify(function() { return dialog.opened }, 1500)
        dialog.close()
        window.destroy()
    }

    function test_toolPanelsAreMutuallyExclusive() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        editor.hasImage = true
        editor.imageWidth = 800; editor.imageHeight = 600
        const canvas = findChild(window, "editorCanvas")
        const inspector = findChild(window, "inspector")
        verify(canvas !== null && inspector !== null)

        visualChild(window.contentItem, "tool-text").clicked()
        compare(window.activeTool, "text")
        verify(canvas.textActive)
        verify(!canvas.cropActive && !canvas.mosaicActive && !canvas.brushActive && !canvas.shapeActive)
        verify(!inspector.visible)

        visualChild(window.contentItem, "tool-brush").clicked()
        compare(window.activeTool, "brush")
        verify(canvas.brushActive)
        verify(!canvas.textActive && !canvas.cropActive)
        verify(findChild(window, "brushPanel").visible)

        visualChild(window.contentItem, "tool-shapes").clicked()
        compare(window.activeTool, "shapes")
        verify(canvas.shapeActive)
        verify(findChild(window, "shapePanel").visible)

        visualChild(window.contentItem, "tool-crop").clicked()
        compare(window.activeTool, "crop")
        verify(canvas.cropActive)
        verify(!canvas.shapeActive && !canvas.brushActive)
        verify(findChild(window, "cropPanel").visible)

        visualChild(window.contentItem, "tool-select").clicked()
        compare(window.activeTool, "select")
        verify(canvas.selectionActive)
        verify(!canvas.cropActive)

        editor.hasImage = false
        window.destroy()
    }

    function test_textToolCreatesTextFromPanel() {
        editor.hasImage = true
        editor.imageWidth = 800
        editor.imageHeight = 600
        editor.textCall = ""
        const component = Qt.createComponent("../Main.qml")
        compare(component.status, Component.Ready, component.errorString())
        const window = component.createObject(null)
        try {
            window.activeTool = "text"
            wait(0)
            const panel = findChild(window, "textPanel")
            verify(panel !== null)
            verify(panel.visible)
            panel.text = "Hello"
            window.createTextAt(120, 80)
            wait(0)
            verify(editor.textCall.indexOf("Hello:120:80") === 0)
        } finally {
            window.destroy()
            editor.hasImage = false
            editor.imageWidth = 0
            editor.imageHeight = 0
        }
    }

    function test_mosaicToolRoutesParametersAndLocksWhileBusy() {
        const component = Qt.createComponent("../Main.qml")
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        verify(window.activeTool !== undefined)
        const panel = findChild(window, "mosaicPanel")
        const canvas = findChild(window, "editorCanvas")
        const inspector = findChild(window, "inspector")
        const tool = visualChild(window.contentItem, "tool-mosaic")
        verify(panel !== null && canvas !== null && tool !== null)
        editor.hasImage = true
        editor.imageWidth = 1000; editor.imageHeight = 500
        editor.mosaicCalls = 0
        tool.clicked()
        compare(window.activeTool, "mosaic")
        verify(panel.visible)
        verify(!inspector.visible)
        verify(canvas.mosaicActive)
        panel.brushMode = false
        panel.blockSize = 18
        compare(canvas.mosaicBrushMode, false)
        canvas.mosaicRectangleCommitted(Qt.rect(10, 20, 100, 60))
        compare(editor.mosaicCalls, 1)
        compare(editor.mosaicArea, Qt.rect(10, 20, 100, 60))
        compare(editor.mosaicBlockSize, 18)
        panel.brushMode = true
        panel.brushDiameter = 48
        canvas.mosaicStrokeCommitted([Qt.point(30, 40), Qt.point(40, 50)])
        compare(editor.mosaicCalls, 2)
        compare(editor.mosaicPoints.length, 2)
        compare(editor.mosaicPoints[0].x, 30)
        compare(editor.mosaicPoints[1].y, 50)
        compare(editor.mosaicDiameter, 48)
        compare(editor.mosaicBlockSize, 18)
        editor.busy = true
        verify(!panel.enabled)
        verify(!canvas.inputEnabled)
        verify(!tool.enabled)
        editor.busy = false
        visualChild(window.contentItem, "tool-filters").clicked()
        compare(window.activeTool, "filters")
        verify(!panel.visible)
        verify(!inspector.visible)
        verify(findChild(window, "filtersToolPanel").visible)
        verify(!canvas.mosaicActive)
        visualChild(window.contentItem, "tool-adjust").clicked()
        compare(window.activeTool, "adjust")
        verify(inspector.visible)
        visualChild(window.contentItem, "tool-filters").clicked()
        compare(window.activeTool, "filters")
        verify(findChild(window, "filtersToolPanel").visible)
        editor.hasImage = false
        editor.imageWidth = 0; editor.imageHeight = 0
        window.destroy()
    }

    function keyEvent(key, autoRepeat) {
        return { key: key, modifiers: Qt.NoModifier,
                 isAutoRepeat: autoRepeat === true, accepted: false }
    }
    function createWindow() {
        const component = Qt.createComponent("../Main.qml")
        compare(component.status, Component.Ready, component.errorString())
        const window = component.createObject(null)
        verify(window !== null, component.errorString())
        return window
    }
    function resetEditor() {
        editor.hasImage = false
        editor.imageWidth = 0
        editor.imageHeight = 0
        editor.dirty = false
        editor.busy = false
        editor.errorMessage = ""
        editor.fileName = ""
    }

    function test_spacePanTemporarilyPansAndRestoresTool() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            const view = findChild(canvas, "canvasView")
            verify(canvas !== null && view !== null)
            editor.hasImage = true
            editor.imageWidth = 1200
            editor.imageHeight = 800
            wait(0)
            window.activeTool = "brush"
            compare(window.activeTool, "brush")
            canvas.fitting = false
            canvas.zoom = 2
            wait(0)
            view.contentX = 200
            view.contentY = 150

            const press = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(press)
            verify(press.accepted)
            verify(window.spacePanHeld)
            verify(window.spacePanActive)
            verify(canvas.effectivePanActive)
            verify(!canvas.panActive)
            compare(window.activeTool, "brush")
            verify(window.transientStatus.length > 0)

            mousePress(canvas, 300, 200)
            mouseMove(canvas, 260, 160)
            mouseRelease(canvas, 260, 160)
            verify(view.contentX > 200 || view.contentY > 150,
                   "left-drag must pan while Space is held")

            // Auto-repeat must not toggle pan off.
            const repeat = keyEvent(Qt.Key_Space, true)
            window.handleCanvasKeyPress(repeat)
            verify(window.spacePanActive)
            verify(repeat.accepted)

            const release = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyRelease(release)
            verify(release.accepted)
            verify(!window.spacePanHeld)
            verify(!window.spacePanActive)
            verify(!canvas.effectivePanActive)
            compare(window.activeTool, "brush")
            verify(window.transientStatus.length > 0)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_spacePanIgnoredWithoutImageOrWhileBusy() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            editor.hasImage = false
            wait(0)
            const noImage = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(noImage)
            verify(!window.spacePanHeld)

            editor.hasImage = true
            editor.imageWidth = 800
            editor.imageHeight = 600
            wait(0)
            editor.busy = true
            wait(0)
            const busyPress = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(busyPress)
            verify(!window.spacePanHeld)
            verify(!canvas.effectivePanActive)
            verify(!busyPress.accepted)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_compareHoldShowsBaseAndIgnoresAutoRepeat() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            const picture = findChild(canvas, "canvasPicture")
            verify(picture !== null)
            editor.hasImage = true
            editor.imageWidth = 800
            editor.imageHeight = 600
            wait(0)
            canvas.baseImageUrl = "file:///tmp/base-hold.png"
            canvas.imageUrl = "file:///tmp/current-hold.png"
            wait(0)
            verify(picture.source.toString().indexOf("current-hold.png") >= 0)

            const press = keyEvent(Qt.Key_M, false)
            window.handleCanvasKeyPress(press)
            verify(press.accepted)
            verify(window.compareHeld)
            verify(canvas.compareActive)
            verify(picture.source.toString().indexOf("base-hold.png") >= 0)
            verify(window.transientStatus.length > 0)

            const repeat = keyEvent(Qt.Key_M, true)
            window.handleCanvasKeyPress(repeat)
            verify(canvas.compareActive)
            verify(repeat.accepted)

            const release = keyEvent(Qt.Key_M, false)
            window.handleCanvasKeyRelease(release)
            verify(release.accepted)
            verify(!window.compareHeld)
            verify(!canvas.compareActive)
            verify(picture.source.toString().indexOf("current-hold.png") >= 0)
            verify(window.transientStatus.length > 0)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_escapeExitsEveryToolAndClearsSelection() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            const shapePanel = findChild(window, "shapePanel")
            editor.hasImage = true
            editor.imageWidth = 1000
            editor.imageHeight = 500
            wait(0)
            const tools = ["select", "brush", "text", "shapes", "mosaic", "eye",
                           "crop", "pan", "filters"]
            for (let i = 0; i < tools.length; ++i) {
                window.activeTool = tools[i]
                compare(window.activeTool, tools[i])
                const event = keyEvent(Qt.Key_Escape, false)
                window.handleCanvasKeyPress(event)
                compare(window.activeTool, "adjust", "Esc must leave " + tools[i])
                verify(event.accepted)
            }
            // Polygon shares the Shapes tool but has its own overlay.
            shapePanel.shapeKind = "polygon"
            window.activeTool = "shapes"
            let event = keyEvent(Qt.Key_Escape, false)
            window.handleCanvasKeyPress(event)
            compare(window.activeTool, "adjust")
            verify(event.accepted)
            shapePanel.shapeKind = "rectangle"

            window.activeTool = "select"
            canvas.setSelectionIds([7, 9])
            compare(canvas.selectionIds.length, 2)
            event = keyEvent(Qt.Key_Escape, false)
            window.handleCanvasKeyPress(event)
            compare(window.activeTool, "adjust")
            compare(canvas.selectionIds.length, 0)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_toolSwitchKeepsOverlaysExclusiveAndHintsPresent() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            const shapePanel = findChild(window, "shapePanel")
            editor.hasImage = true
            editor.imageWidth = 1000
            editor.imageHeight = 500
            wait(0)
            const tools = ["select", "brush", "text", "shapes", "mosaic", "eye", "crop"]
            for (let i = 0; i < tools.length; ++i) {
                window.activeTool = tools[i]
                const active = [canvas.cropActive, canvas.mosaicActive, canvas.textActive,
                                canvas.brushActive, canvas.shapeActive, canvas.polygonActive,
                                canvas.selectionActive, canvas.eyedropperActive]
                let count = 0
                for (let j = 0; j < active.length; ++j) if (active[j]) ++count
                compare(count, 1, "exactly one overlay for " + tools[i])
                verify(window.activeToolHint.length > 0)
                compare(canvas.toolHint, window.activeToolHint)
            }
            window.activeTool = "adjust"
            compare(window.activeToolHint, "")
            window.activeTool = "filters"
            compare(window.activeToolHint, "")
            window.activeTool = "shapes"
            const rectangleHint = window.activeToolHint
            shapePanel.shapeKind = "polygon"
            wait(0)
            verify(window.activeToolHint !== rectangleHint)
            shapePanel.shapeKind = "rectangle"
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_busyStateGatesActionsAndShowsBusyFeedback() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            const status = findChild(window, "statusMessage")
            const panArea = findChild(canvas, "panMouseArea")
            const tool = visualChild(window.contentItem, "tool-brush")
            verify(status !== null && panArea !== null && tool !== null)
            editor.hasImage = true
            editor.imageWidth = 800
            editor.imageHeight = 600
            wait(0)
            editor.busy = true
            wait(0)
            verify(!tool.enabled)
            verify(canvas.busy)
            compare(panArea.cursorShape, Qt.BusyCursor)
            compare(status.text, qsTr("Working…"))

            const space = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(space)
            verify(!window.spacePanHeld)

            editor.openCalls = 0
            verify(!window.requestOpen("file:///tmp/blocked.png"))
            compare(editor.openCalls, 0)

            editor.busy = false
            wait(0)
            verify(tool.enabled)
            verify(!canvas.busy)
            compare(panArea.cursorShape, Qt.ArrowCursor)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_modalAndTextFieldSuppressCanvasKeys() {
        const window = createWindow()
        try {
            const canvas = findChild(window, "editorCanvas")
            editor.hasImage = true
            editor.imageWidth = 800
            editor.imageHeight = 600
            wait(0)
            window.activeTool = "brush"
            const dialog = findChild(window, "settingsDialog")
            verify(dialog !== null)
            dialog.open()
            tryVerify(function() { return dialog.opened && window.blockingModal }, 1500)

            const space = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(space)
            verify(!window.spacePanHeld)
            const m = keyEvent(Qt.Key_M, false)
            window.handleCanvasKeyPress(m)
            verify(!canvas.compareActive)
            const esc = keyEvent(Qt.Key_Escape, false)
            window.handleCanvasKeyPress(esc)
            compare(window.activeTool, "brush")
            dialog.close()
            tryVerify(function() { return !dialog.opened }, 1500)

            // The Brush panel hex field is the only non-modal text field.
            const field = findChild(window, "brush-hex-field")
            verify(field !== null)
            field.forceActiveFocus()
            tryVerify(function() { return window.textInputFocused }, 1500)
            const space2 = keyEvent(Qt.Key_Space, false)
            window.handleCanvasKeyPress(space2)
            verify(!window.spacePanHeld)
            const m2 = keyEvent(Qt.Key_M, false)
            window.handleCanvasKeyPress(m2)
            verify(!canvas.compareActive)
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_sharedOpenPathConfirmsDiscardAndShowsErrors() {
        const window = createWindow()
        try {
            const dialog = findChild(window, "discardDialog")
            const errorDialog = findChild(window, "errorDialog")
            verify(dialog !== null && errorDialog !== null)

            editor.hasImage = true
            editor.dirty = false
            editor.openCalls = 0
            verify(window.requestOpen("file:///tmp/clean.png"))
            compare(editor.openCalls, 1)

            editor.dirty = true
            verify(window.requestOpen("file:///tmp/pending.png"))
            compare(editor.openCalls, 1)
            verify(dialog.opened)
            compare(window.pendingImage.toString(), "file:///tmp/pending.png")
            dialog.discarded()
            compare(editor.openDiscardingCalls, 1)
            editor.dirty = false

            // A failed load must not clear the current document and must surface
            // the controller error through the shared dialog.
            editor.errorMessage = "Could not open image"
            editor.errorChanged()
            tryVerify(function() { return errorDialog.opened }, 1500)
            verify(editor.hasImage)
            errorDialog.close()
            tryVerify(function() { return !errorDialog.opened }, 1500)

            const recentMenu = findChild(window, "recentMenu")
            verify(recentMenu !== null)
            verify(!recentMenu.enabled, "recent menu is disabled when empty")
        } finally {
            resetEditor()
            window.destroy()
        }
    }

    function test_statusMessagesForToolsFiltersAndAutoEnhance() {
        const window = createWindow()
        try {
            const inspector = findChild(window, "inspector")
            editor.hasImage = true
            editor.imageWidth = 800
            editor.imageHeight = 600
            wait(0)
            window.activeTool = "brush"
            compare(window.transientStatus, qsTr("Brush"))
            inspector.filterSelected("mono")
            verify(window.transientStatus.indexOf("mono") >= 0)
            editor.autoEnhanceCalls = 0
            inspector.autoEnhanceRequested()
            compare(editor.autoEnhanceCalls, 1)
            compare(window.transientStatus, qsTr("Auto enhance"))
        } finally {
            resetEditor()
            window.destroy()
        }
    }
}
