import QtQuick
import QtTest
import ".."

TestCase {
    name: "CropOverlay"
    when: windowShown
    visible: true; width: 640; height: 480
    EditorCanvas {
        id: canvas; width: 600; height: 420
        hasImage: true; imageWidth: 1000; imageHeight: 500
    }
    SignalSpy { id: applies; target: canvas; signalName: "cropApplyRequested" }
    SignalSpy { id: cancels; target: canvas; signalName: "cropCancelled" }
    function init() {
        verify(canvas.cropActive !== undefined, "Crop tool must be available")
        canvas.inputEnabled = true
        canvas.imageWidth = 1000; canvas.imageHeight = 500
        canvas.cropAspectRatio = 0
        canvas.cropActive = false
        canvas.fitImage()
        canvas.cropActive = true
        applies.clear(); cancels.clear()
    }
    function cleanup() { canvas.cropActive = false }
    function test_initialRatioAndImageReset() {
        compare(canvas.cropSelection, Qt.rect(0, 0, 1000, 500))
        canvas.cropAspectRatio = 1
        compare(canvas.cropSelection, Qt.rect(250, 0, 500, 500))
        canvas.imageWidth = 400
        compare(canvas.cropSelection, Qt.rect(0, 50, 400, 400))
    }
    function test_resizeMoveAndCommit() {
        const overlay = findChild(canvas, "cropOverlay")
        verify(overlay !== null)
        mouseDrag(overlay, 1, 1, 80, 40)
        verify(canvas.cropSelection.width < 1000)
        verify(canvas.cropSelection.x > 0)
        const s = canvas.cropSelection
        const before = Qt.rect(s.x, s.y, s.width, s.height)
        mouseDrag(overlay, (before.x + before.width / 2) * canvas.zoom,
                  (before.y + before.height / 2) * canvas.zoom, -30, -10)
        fuzzyCompare(canvas.cropSelection.width, before.width, 0.01)
        verify(canvas.cropSelection.x < before.x)
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(applies.count, 1)
        compare(applies.signalArguments[0][0], canvas.cropSelection)
        keyClick(Qt.Key_Escape)
        compare(cancels.count, 1)
    }
    function test_fixedRatioClampedAndDisabled() {
        canvas.cropAspectRatio = 4 / 3
        const overlay = findChild(canvas, "cropOverlay")
        let area = canvas.cropSelection
        mouseDrag(overlay, (area.x + area.width) * canvas.zoom - 1,
                  (area.y + area.height) * canvas.zoom - 1, -60, -20)
        area = canvas.cropSelection
        fuzzyCompare(area.width / area.height, 4 / 3, 0.001)
        verify(area.x >= 0 && area.y >= 0)
        verify(area.x + area.width <= 1000.001 && area.y + area.height <= 500.001)
        canvas.inputEnabled = false
        mouseDrag(overlay, 100, 100, 60, 30)
        compare(canvas.cropSelection, area)
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(applies.count, 0)
    }
    function test_keepsPanZoomAndBoundedBacking() {
        canvas.actualSize()
        const view = findChild(canvas, "canvasView")
        view.contentX = 200; view.contentY = 80
        mouseDrag(view, 200, 140, 30, 20, Qt.MiddleButton)
        verify(view.contentX < 200)
        const previous = canvas.zoom
        mouseWheel(view, 200, 140, 0, 120, Qt.NoButton)
        verify(canvas.zoom > previous)
        canvas.cropActive = false
        canvas.fitting = false
        canvas.imageWidth = 8192; canvas.imageHeight = 8192; canvas.zoom = 3
        const drawing = findChild(canvas, "cropPreview")
        verify(drawing !== null)
        verify(drawing.width <= view.width && drawing.height <= view.height)
        canvas.cropActive = true
        verify(drawing.canvasSize.width <= view.width)
    }
}
