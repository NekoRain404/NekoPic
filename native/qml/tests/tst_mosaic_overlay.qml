import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "MosaicOverlayInput"
    when: windowShown
    visible: true
    width: 320
    height: 240

    MouseArea {
        id: canvasPan
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property int presses: 0
        onPressed: ++presses
    }
    Loader {
        id: overlayLoader
        x: 20; y: 20; width: 200; height: 100
        source: "../MosaicOverlay.qml"
    }
    property var overlay: overlayLoader.item
    SignalSpy { id: rectangles; target: testCase.overlay; signalName: "rectangleCommitted" }
    SignalSpy { id: strokes; target: testCase.overlay; signalName: "strokeCommitted" }

    function initTestCase() {
        compare(overlayLoader.status, Loader.Ready)
    }
    function init() {
        overlay.active = true
        overlay.inputEnabled = true
        overlay.brushMode = true
        overlay.brushDiameter = 24
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.2
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        rectangles.clear()
        strokes.clear()
        canvasPan.presses = 0
    }
    function test_brushDragMapsToImagePixels() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 50, 40)
        mouseRelease(overlay, 80, 60)
        compare(strokes.count, 1)
        compare(rectangles.count, 0)
        const points = strokes.signalArguments[0][0]
        compare(points[0].x, 100)
        compare(points[0].y, 50)
        compare(points[points.length - 1].x, 400)
        compare(points[points.length - 1].y, 300)
    }
    function test_brushClickCommitsSinglePoint() {
        mouseClick(overlay, 60, 30)
        compare(strokes.count, 1)
        const points = strokes.signalArguments[0][0]
        compare(points.length, 1)
        compare(points[0].x, 300)
        compare(points[0].y, 150)
    }
    function test_mappingUsesActualDisplaySize() {
        overlay.viewScale = 0.5
        mouseClick(overlay, 60, 30)
        const points = strokes.signalArguments[0][0]
        compare(points[0].x, 300)
        compare(points[0].y, 150)
    }
    function test_viewportPreviewKeepsImageSpacePainting() {
        overlay.visibleRect = Qt.rect(40, 20, 120, 60)
        overlay.brushMode = false
        const preview = findChild(overlay, "mosaicPreview")
        compare(preview.x, 40)
        compare(preview.y, 20)
        compare(preview.canvasSize, Qt.size(120, 60))
        mousePress(overlay, 60, 30)
        mouseMove(overlay, 120, 60)
        tryVerify(function() {
            return preview.getContext("2d").getImageData(40, 25, 1, 1).data[3] > 0
        }, 1000, "Rectangle preview must cover its image-space interior")
        compare(preview.getContext("2d").getImageData(5, 5, 1, 1).data[3], 0)
        // Moving the viewport must redraw the same image-space rectangle at
        // its new canvas-local position, without changing the gesture.
        overlay.visibleRect = Qt.rect(80, 40, 100, 50)
        tryVerify(function() {
            return preview.getContext("2d").getImageData(10, 10, 1, 1).data[3] > 0
        })
        compare(preview.getContext("2d").getImageData(60, 35, 1, 1).data[3], 0)
        mouseRelease(overlay, 120, 60)
        compare(rectangles.count, 1)
        compare(rectangles.signalArguments[0][0], Qt.rect(300, 150, 300, 150))
        overlay.brushMode = true
        overlay.brushDiameter = 100
        mousePress(overlay, 100, 50)
        tryVerify(function() {
            return preview.getContext("2d").getImageData(20, 10, 1, 1).data[3] > 0
        }, 1000, "Brush preview must stay centered on its image point")
        compare(preview.getContext("2d").getImageData(60, 35, 1, 1).data[3], 0)
        mouseRelease(overlay, 100, 50)
        mouseMove(overlay, 110, 60)
        tryVerify(function() {
            return preview.getContext("2d").getImageData(40, 20, 1, 1).data[3] > 0
                   && preview.getContext("2d").getImageData(30, 20, 1, 1).data[3] === 0
        }, 1000, "Cursor outline must use the same viewport translation as the brush")
    }
    function test_brushThinsNearbyMovesButKeepsEndpoint() {
        overlay.brushDiameter = 100
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 21, 10)
        mouseRelease(overlay, 21, 10)
        const points = strokes.signalArguments[0][0]
        compare(points.length, 2)
        compare(points[0].x, 100)
        compare(points[1].x, 105)
    }
    function test_longBrushStrokeIsBoundedAndKeepsEndpoints() {
        mousePress(overlay, 20, 10)
        for (let i = 0; i < 4200; ++i)
            mouseMove(overlay, i % 2 ? 20 : 180, 30, 0)
        mouseRelease(overlay, 100, 30)
        compare(strokes.count, 1)
        const points = strokes.signalArguments[0][0]
        verify(points.length <= 4096)
        compare(points[0].x, 100)
        compare(points[0].y, 50)
        compare(points[points.length - 1].x, 500)
        compare(points[points.length - 1].y, 150)
    }
    function test_rectangleNormalizesReverseDrag() {
        overlay.brushMode = false
        mousePress(overlay, 140, 80)
        mouseMove(overlay, 20, 10)
        mouseRelease(overlay, 20, 10)
        compare(rectangles.count, 1)
        compare(strokes.count, 0)
        const area = rectangles.signalArguments[0][0]
        compare(area.x, 100)
        compare(area.y, 50)
        compare(area.width, 600)
        compare(area.height, 350)
    }
    function test_rectangleClipsAtImageEdge() {
        overlay.brushMode = false
        mousePress(overlay, 180, 80)
        mouseMove(overlay, 240, 140)
        mouseRelease(overlay, 240, 140)
        compare(rectangles.count, 1)
        const area = rectangles.signalArguments[0][0]
        compare(area.x, 900)
        compare(area.y, 400)
        compare(area.width, 100)
        compare(area.height, 100)
    }
    function test_rectangleClickDoesNotCommit() {
        overlay.brushMode = false
        mouseClick(overlay, 60, 30)
        compare(rectangles.count, 0)
    }
    function test_escapeCancels_data() {
        return [{tag: "brush", brush: true}, {tag: "rectangle", brush: false}]
    }
    function test_escapeCancels(data) {
        overlay.brushMode = data.brush
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60)
        keyClick(Qt.Key_Escape)
        mouseRelease(overlay, 80, 60)
        compare(strokes.count, 0)
        compare(rectangles.count, 0)
    }
    function test_inactiveAndDisabledDoNotStealInput_data() {
        return [{tag: "inactive", active: false, input: true},
                {tag: "disabled", active: true, input: false}]
    }
    function test_inactiveAndDisabledDoNotStealInput(data) {
        overlay.active = data.active
        overlay.inputEnabled = data.input
        mouseClick(overlayLoader, 60, 30)
        compare(strokes.count, 0)
        compare(rectangles.count, 0)
        compare(canvasPan.presses, 1)
    }
    function test_middleButtonReachesCanvasPan() {
        mouseDrag(overlay, 20, 10, 40, 30, Qt.MiddleButton)
        compare(strokes.count, 0)
        compare(rectangles.count, 0)
        compare(canvasPan.presses, 1)
    }
    function test_disablingDuringDragCancelsCommit() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60)
        overlay.inputEnabled = false
        mouseRelease(overlay, 80, 60)
        compare(strokes.count, 0)
        compare(rectangles.count, 0)
    }
}
