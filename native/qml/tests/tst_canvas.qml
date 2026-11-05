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
    SignalSpy { id: mosaicRectangles; target: canvas; signalName: "mosaicRectangleCommitted" }
    SignalSpy { id: mosaicStrokes; target: canvas; signalName: "mosaicStrokeCommitted" }
    SignalSpy { id: recentRequests; target: canvas; signalName: "recentRequested" }
    function test_fitAndActual() {
        canvas.fitImage()
        verify(canvas.zoom < 1)
        canvas.actualSize()
        compare(canvas.zoom, 1)
    }
    function test_pictureCentersWithGuttersAfterResize() {
        canvas.mosaicActive = false
        canvas.fitting = false
        canvas.imageWidth = 200
        canvas.imageHeight = 100
        canvas.zoom = 1
        const view = findChild(canvas, "canvasView")
        const picture = findChild(canvas, "canvasPicture")
        try {
            wait(0)
            compare(picture.parent, view.contentItem)
            compare(picture.x, 200)
            compare(picture.y, (view.height - 100) / 2)
            canvas.width = 620
            canvas.height = 420
            wait(0)
            compare(picture.x, 210)
            compare(picture.y, (view.height - 100) / 2)
            canvas.zoom = 3
            wait(0)
            compare(picture.x, 40)
            compare(picture.y, 40)
        } finally {
            canvas.width = 600
            canvas.height = 400
            canvas.imageWidth = 1200
            canvas.imageHeight = 800
            canvas.fitImage()
        }
    }
    function test_recentEntryEmitsRequest() {
        const saved = canvas.recentEntries
        canvas.hasImage = false
        canvas.recentEntries = [{ name: "demo.jpg", url: "file:///tmp/demo.jpg" }]
        wait(0)
        const button = findChild(canvas, "recent-0")
        verify(button !== null)
        mouseClick(button)
        compare(recentRequests.count, 1)
        compare(recentRequests.signalArguments[0][0].toString(), "file:///tmp/demo.jpg")
        canvas.recentEntries = saved
        canvas.hasImage = true
    }

    function test_gpuPreviewUsesBaseImageAndPendingValues() {
        const picture = findChild(canvas, "canvasPicture")
        const effect = findChild(canvas, "adjustmentPreview")
        verify(picture !== null && effect !== null)
        canvas.baseImageUrl = "file:///tmp/base-preview.png"
        canvas.imageUrl = "file:///tmp/current-preview.png"
        canvas.gpuPreviewAvailable = true
        canvas.adjustmentPreviewActive = true
        canvas.previewExposure = 1.5
        compare(effect.sourceItem, picture)
        compare(effect.active, true)
        fuzzyCompare(effect.exposure, 1.5, 0.001)
        verify(picture.source.toString().indexOf("base-preview.png") >= 0)
        canvas.adjustmentPreviewActive = false
        verify(picture.source.toString().indexOf("current-preview.png") >= 0)
        canvas.gpuPreviewAvailable = false
        canvas.baseImageUrl = ""
        canvas.imageUrl = ""
        canvas.previewExposure = 0
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
    function test_mosaicBrushAndRectangleFollowDisplayedImage() {
        verify(canvas.mosaicActive !== undefined)
        canvas.fitImage()
        canvas.mosaicActive = true
        canvas.mosaicBrushMode = true
        mosaicRectangles.clear(); mosaicStrokes.clear()
        const overlay = findChild(canvas, "mosaicOverlay")
        const picture = findChild(canvas, "canvasPicture")
        verify(overlay !== null)
        compare(overlay.width, picture.width)
        compare(overlay.height, picture.height)
        mouseClick(overlay, overlay.width / 4, overlay.height / 4)
        compare(mosaicStrokes.count, 1)
        compare(mosaicRectangles.count, 0)
        const points = mosaicStrokes.signalArguments[0][0]
        fuzzyCompare(points[0].x, 300, 4)
        fuzzyCompare(points[0].y, 200, 4)
        canvas.mosaicBrushMode = false
        mousePress(overlay, overlay.width / 4, overlay.height / 4)
        mouseMove(overlay, overlay.width / 2, overlay.height / 2)
        compare(mosaicRectangles.count, 0)
        mouseRelease(overlay, overlay.width / 2, overlay.height / 2)
        compare(mosaicRectangles.count, 1)
        const area = mosaicRectangles.signalArguments[0][0]
        fuzzyCompare(area.x, 300, 4)
        fuzzyCompare(area.y, 200, 4)
        fuzzyCompare(area.width, 300, 4)
        fuzzyCompare(area.height, 200, 4)
        canvas.inputEnabled = false
        mouseClick(overlay, 20, 20)
        compare(mosaicRectangles.count, 1)
        compare(mosaicStrokes.count, 1)
        canvas.inputEnabled = true
        canvas.mosaicActive = false
    }
    function test_mosaicKeepsWheelAndMiddlePan() {
        verify(canvas.mosaicActive !== undefined)
        canvas.mosaicActive = true
        canvas.actualSize()
        const view = findChild(canvas, "canvasView")
        view.contentX = 240
        view.contentY = 150
        mouseDrag(view, 250, 150, 30, 20, Qt.MiddleButton)
        verify(view.contentX < 240)
        verify(view.contentY < 150)
        const previousZoom = canvas.zoom
        mouseWheel(view, 250, 150, 0, 120, Qt.NoButton)
        verify(canvas.zoom > previousZoom)
        canvas.mosaicActive = false
    }
    function test_mosaicHugeImageUsesViewportBacking() {
        // Keep the old full-image Canvas invisible until its size is checked:
        // allocating a 24576-square raster would otherwise consume over 2 GiB.
        canvas.mosaicActive = false
        canvas.fitting = false
        canvas.imageWidth = 8192
        canvas.imageHeight = 8192
        canvas.zoom = 3
        const view = findChild(canvas, "canvasView")
        const picture = findChild(canvas, "canvasPicture")
        const overlay = findChild(canvas, "mosaicOverlay")
        const preview = findChild(overlay, "mosaicPreview")
        try {
            compare(overlay.width, 24576)
            verify(preview.width <= view.width, "Preview backing must fit the viewport")
            verify(preview.height <= view.height, "Preview backing must fit the viewport")
            verify(preview.canvasSize.width <= view.width)
            verify(preview.canvasSize.height <= view.height)
            canvas.mosaicActive = true
            canvas.mosaicBrushMode = true
            wait(0)
            view.contentX = picture.x + 3000
            view.contentY = picture.y + 1500
            compare(preview.x, 3000)
            compare(preview.y, 1500)
            mosaicStrokes.clear()
            mousePress(view, 120, 90)
            mouseMove(view, 240, 150)
            mouseRelease(view, 240, 150)
            compare(mosaicStrokes.count, 1)
            const points = mosaicStrokes.signalArguments[0][0]
            compare(points[0].x, 1040)
            compare(points[0].y, 530)
            compare(points[points.length - 1].x, 1080)
            compare(points[points.length - 1].y, 550)
            canvas.mosaicBrushMode = false
            mosaicRectangles.clear()
            mouseDrag(view, 120, 90, 120, 60)
            compare(mosaicRectangles.count, 1)
            compare(mosaicRectangles.signalArguments[0][0], Qt.rect(1040, 530, 40, 20))
            canvas.zoomAt(0.5, 240, 150)
            verify(preview.canvasSize.width <= view.width)
            verify(preview.canvasSize.height <= view.height)
            fuzzyCompare(preview.x, view.contentX - picture.x, 0.01)
            fuzzyCompare(preview.y, view.contentY - picture.y, 0.01)
            canvas.mosaicBrushMode = true
            mouseClick(view, 240, 150)
            compare(mosaicStrokes.count, 2)
            const zoomedPoint = mosaicStrokes.signalArguments[1][0][0]
            compare(zoomedPoint.x, 1080)
            compare(zoomedPoint.y, 550)
        } finally {
            canvas.mosaicActive = false
            canvas.mosaicBrushMode = true
            canvas.imageWidth = 1200
            canvas.imageHeight = 800
            canvas.fitImage()
        }
    }
    function test_contentChangePreservesZoomAndPan() {
        canvas.actualSize()
        canvas.changeZoom(1.2)
        const view = findChild(canvas, "canvasView")
        view.contentX = 240
        view.contentY = 150
        canvas.imageUrl = Qt.resolvedUrl("../../../assets/demo.jpg")
        canvas.dirty = !canvas.dirty
        wait(0)
        compare(canvas.zoom, 1.2)
        compare(view.contentX, 240)
        compare(view.contentY, 150)
        canvas.imageUrl = ""
    }
}
