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
        property int cropCalls: 0
        property rect cropArea
        property var readableImagePatterns: ["*.png", "*.PNG"]
        signal errorChanged()
        function openImage(url) {}
        function saveImage() {}
        function saveAs(url, format) {}
        function clearError() {}
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
        verify(inspector.visible)
        compare(inspector.currentTab, 1)
        verify(!canvas.mosaicActive)
        inspector.currentTab = 0
        compare(window.activeTool, "adjust")
        visualChild(window.contentItem, "tool-filters").clicked()
        compare(window.activeTool, "filters")
        compare(inspector.currentTab, 1)
        editor.hasImage = false
        editor.imageWidth = 0; editor.imageHeight = 0
        window.destroy()
    }
}
