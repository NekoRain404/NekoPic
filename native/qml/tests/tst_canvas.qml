import QtQuick
import QtTest
import ".."

TestCase {
    name: "CanvasZoom"
    when: windowShown
    visible: true
    width: 640
    height: 480
    EditorCanvas {
        id: canvas
        width: 600
        height: 400
        imageWidth: 1200
        imageHeight: 800
        hasImage: true
    }
    function test_fitAndActual() {
        canvas.fitImage()
        verify(canvas.zoom < 1)
        canvas.actualSize()
        compare(canvas.zoom, 1)
    }
    function test_zoomKeepsPointerOnImage() {
        canvas.actualSize()
        const view = findChild(canvas, "canvasView")
        const picture = findChild(canvas, "canvasPicture")
        verify(view !== null && picture !== null)
        view.contentX = 240
        view.contentY = 150
        const x = 250
        const y = 150
        const imageX = (view.contentX + x - picture.x) / canvas.zoom
        const imageY = (view.contentY + y - picture.y) / canvas.zoom
        canvas.zoomAt(1.2, x, y)
        fuzzyCompare((view.contentX + x - picture.x) / canvas.zoom, imageX, 0.01)
        fuzzyCompare((view.contentY + y - picture.y) / canvas.zoom, imageY, 0.01)
    }
    function test_panAndFitReset() {
        canvas.actualSize()
        const view = findChild(canvas, "canvasView")
        view.contentX = 200
        view.contentY = 120
        canvas.panBy(30, 20)
        compare(view.contentX, 170)
        compare(view.contentY, 100)
        canvas.fitImage()
        compare(view.contentX, 0)
        compare(view.contentY, 0)
    }
    function test_wheelAndMiddleDrag() {
        canvas.actualSize()
        const view = findChild(canvas, "canvasView")
        verify(view.width > 0 && view.height > 0)
        mouseWheel(view, 250, 150, 0, 120, Qt.NoButton)
        verify(canvas.zoom > 1)
        view.contentX = 240
        view.contentY = 150
        mouseDrag(view, 250, 150, 30, 20, Qt.MiddleButton)
        verify(view.contentX < 240)
        verify(view.contentY < 150)
    }
}
