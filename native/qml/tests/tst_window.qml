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
        function openImage(url) {}
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

    function test_textToolCreatesTextThroughDialog() {
        editor.hasImage = true
        editor.imageWidth = 800
        editor.imageHeight = 600
        editor.textCall = ""
        const component = Qt.createComponent("../Main.qml")
        compare(component.status, Component.Ready, component.errorString())
        const window = component.createObject(null)
        try {
            window.openTextDialog(120, 80)
            wait(0)
            const dialog = findChild(window, "textDialog")
            verify(dialog !== null)
            const input = findChild(dialog, "text-dialog-text")
            verify(input !== null)
            input.text = "Hello"
            wait(0)
            mouseClick(findChild(dialog, "text-dialog-accept"))
            wait(0)
            verify(editor.textCall.indexOf("Hello:120:80") === 0)
            compare(window.activeTool, "adjust")
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
}
