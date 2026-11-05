import QtQuick
import QtTest
import "../UI"
import "../overlays"
import "../panels"

/*!
    Contract tests for the brush tool UI: coordinate mapping, sampling,
    gesture lifecycle, preview, pass-through and the settings panel.
*/
TestCase {
    id: testCase
    name: "BrushTool"
    when: windowShown
    visible: true
    width: 900
    height: 700

    // Stand-in for the canvas pan/wheel layer underneath the overlay.
    MouseArea {
        id: canvasPan
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property int presses: 0
        property int wheelEvents: 0
        onPressed: ++presses
        onWheel: function(event) { ++wheelEvents; event.accepted = true }
    }

    BrushOverlay {
        id: overlay
        objectName: "brushOverlay"
        x: 30
        y: 24
        imageWidth: 1000
        imageHeight: 500
        viewScale: 0.25
    }

    BrushPanel {
        id: panel
        objectName: "brushPanel"
        x: 500
        y: 0
        width: 292
        height: 620
    }

    SignalSpy { id: strokes; target: overlay; signalName: "strokeCommitted" }
    SignalSpy { id: overlayCancelled; target: overlay; signalName: "cancelled" }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true

        overlay.active = false
        overlay.inputEnabled = true
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.25
        overlay.diameter = 24
        overlay.color = "#000000"
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        overlay.active = true
        overlay.reset()

        strokes.clear()
        overlayCancelled.clear()
        canvasPan.presses = 0
        canvasPan.wheelEvents = 0

        panel.enabled = true
        panel.width = 292
        panel.height = 620
        const scroller = findChild(panel, "brush-scroll")
        if (scroller !== null)
            scroller.contentY = 0
        panel.diameter = 24
        panel.color = panel.blackColor
    }

    function cleanup() {
        overlay.active = false
    }

    function preview() {
        return findChild(overlay, "brushPreview")
    }

    function alphaAt(x, y) {
        const ctx = preview().getContext("2d")
        return ctx.getImageData(x, y, 1, 1).data[3]
    }

    function panelChild(name) {
        return findChild(panel, name)
    }

    // ── Coordinate mapping ──────────────────────────────────────────────────

    function test_mappingUnderZoomAndPan() {
        compare(overlay.width, 250)
        compare(overlay.height, 125)
        compare(overlay.scaleX, 0.25)
        compare(overlay.scaleY, 0.25)

        let p = overlay.pointAt(50, 25)
        compare(p.x, 200)
        compare(p.y, 100)

        p = overlay.pointAt(0, 0)
        compare(p.x, 0)
        compare(p.y, 0)

        p = overlay.pointAt(250, 125)
        compare(p.x, 1000)
        compare(p.y, 500)

        p = overlay.displayPoint(200, 100)
        compare(p.x, 50)
        compare(p.y, 25)

        // Zoom changes the mapping through the actual display size.
        overlay.viewScale = 0.5
        compare(overlay.width, 500)
        compare(overlay.height, 250)
        p = overlay.pointAt(50, 25)
        compare(p.x, 100)
        compare(p.y, 50)

        // Panning only moves the viewport; the pixel mapping is stable.
        overlay.visibleRect = Qt.rect(120, 40, 300, 200)
        p = overlay.pointAt(50, 25)
        compare(p.x, 100)
        compare(p.y, 50)
    }

    function test_clampsCoordinates() {
        let p = overlay.pointAt(-40, -10)
        compare(p.x, 0)
        compare(p.y, 0)

        p = overlay.pointAt(9999, 9999)
        compare(p.x, 1000)
        compare(p.y, 500)

        p = overlay.pointAt(NaN, 10)
        compare(p.x, 0)
        compare(p.y, 0)

        p = overlay.pointAt(10, Infinity)
        compare(p.x, 0)
        compare(p.y, 0)
    }

    // ── Gesture lifecycle ───────────────────────────────────────────────────

    function test_clickCommitsSinglePoint() {
        mouseClick(overlay, 60, 30)
        compare(strokes.count, 1)
        compare(overlayCancelled.count, 0)
        const points = strokes.signalArguments[0][0]
        compare(points.length, 1)
        compare(points[0].x, 240)
        compare(points[0].y, 120)
    }

    function test_dragMapsAndEmitsExactlyOneStroke() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 40, 10, Qt.LeftButton)
        mouseMove(overlay, 160, 80, 10, Qt.LeftButton)
        compare(strokes.count, 0)
        compare(overlay.drawing, true)
        verify(overlay.sampleCount >= 2, "intermediate moves were not sampled")
        mouseRelease(overlay, 200, 100)

        compare(strokes.count, 1)
        const points = strokes.signalArguments[0][0]
        verify(points.length >= 3, "length=" + points.length)
        compare(points[0].x, 80)
        compare(points[0].y, 40)
        compare(points[points.length - 1].x, 800)
        compare(points[points.length - 1].y, 400)
        compare(overlay.drawing, false)
        compare(overlay.sampleCount, 0)
    }

    function test_samplingDistanceFilter() {
        overlay.diameter = 100
        mousePress(overlay, 20, 10)
        compare(overlay.sampleDistance, 15)
        // Both moves are within 15 image px of the last accepted sample.
        mouseMove(overlay, 21, 10, 0, Qt.LeftButton)
        mouseMove(overlay, 22, 10, 0, Qt.LeftButton)
        compare(overlay.sampleCount, 1)
        // A deliberate move is accepted.
        mouseMove(overlay, 40, 10, 0, Qt.LeftButton)
        compare(overlay.sampleCount, 2)
        // Releasing on the last sample does not duplicate it.
        mouseRelease(overlay, 40, 10)
        compare(strokes.count, 1)
        let points = strokes.signalArguments[0][0]
        compare(points.length, 2)
        compare(points[0].x, 80)
        compare(points[1].x, 160)

        // A tiny diameter still samples no denser than one image pixel.
        strokes.clear()
        overlay.diameter = 2
        mousePress(overlay, 20, 10)
        compare(overlay.sampleDistance, 1)
        mouseRelease(overlay, 20, 10)
        compare(strokes.count, 1)
    }

    function test_longStrokeIsCappedAt4096AndKeepsEndpoints() {
        mousePress(overlay, 20, 10)
        for (let i = 0; i < 4200; ++i)
            mouseMove(overlay, i % 2 ? 20 : 180, 30, 0, Qt.LeftButton)
        mouseRelease(overlay, 100, 30)

        compare(strokes.count, 1)
        const points = strokes.signalArguments[0][0]
        verify(points.length <= 4096)
        // The budget was actually reached and decimated, not silently dropped.
        verify(points.length > 1000, "length=" + points.length)
        verify(overlay.sampleDistance > 3.6, "cap must coarsen the threshold")
        compare(points[0].x, 80)
        compare(points[0].y, 40)
        compare(points[points.length - 1].x, 400)
        compare(points[points.length - 1].y, 120)
    }

    function test_escapeCancelsWithoutCommitting() {
        overlay.forceActiveFocus()
        mousePress(overlay, 50, 25)
        mouseMove(overlay, 80, 50, 0, Qt.LeftButton)
        compare(overlay.drawing, true)
        tryVerify(function() { return alphaAt(50, 25) > 0 }, 1000,
                  "The live preview must be visible before cancelling")

        keyClick(Qt.Key_Escape)
        compare(overlay.drawing, false)
        compare(overlay.sampleCount, 0)
        compare(overlayCancelled.count, 1)
        compare(strokes.count, 0)

        mouseRelease(overlay, 80, 50)
        compare(strokes.count, 0)
        tryVerify(function() {
            return alphaAt(50, 25) === 0 && alphaAt(80, 50) === 0
        }, 1000, "Escape must clear the preview")
    }

    function test_previewDoesNotEmitAndClearsOnRelease() {
        verify(preview() !== null)
        mousePress(overlay, 50, 25)
        tryVerify(function() { return alphaAt(50, 25) > 0 }, 1000,
                  "Press must paint the live preview")
        compare(strokes.count, 0)

        mouseMove(overlay, 80, 50, 0, Qt.LeftButton)
        tryVerify(function() { return alphaAt(80, 50) > 0 }, 1000,
                  "Drag must extend the live preview")
        compare(strokes.count, 0)

        mouseRelease(overlay, 80, 50)
        compare(strokes.count, 1)
        tryVerify(function() {
            return alphaAt(50, 25) === 0 && alphaAt(80, 50) === 0
        }, 1000, "Release must clear the preview")
    }

    function test_viewportBackedDrawingIsBounded() {
        const canvas = preview()
        verify(canvas !== null)

        overlay.imageWidth = 8192
        overlay.imageHeight = 8192
        overlay.viewScale = 3
        overlay.visibleRect = Qt.rect(100, 80, 300, 200)

        compare(canvas.x, 100)
        compare(canvas.y, 80)
        verify(canvas.width <= 300.001)
        verify(canvas.height <= 200.001)
        verify(canvas.x + canvas.width <= overlay.width + 0.001)
        verify(canvas.y + canvas.height <= overlay.height + 0.001)
        // The raster backing never grows to the full zoomed image.
        verify(canvas.width < overlay.width)
        verify(canvas.height < overlay.height)

        // A viewport crossing the image corner is clipped to the image.
        overlay.visibleRect = Qt.rect(-50, -50, 300, 200)
        compare(canvas.x, 0)
        compare(canvas.y, 0)
        verify(canvas.width <= 250.001)
        verify(canvas.height <= 150.001)
    }

    function test_inactiveAndDisabledIgnoreInput_data() {
        return [{ tag: "inactive", active: false, input: true },
                { tag: "disabled", active: true, input: false }]
    }

    function test_inactiveAndDisabledIgnoreInput(data) {
        overlay.active = data.active
        overlay.inputEnabled = data.input

        mouseClick(overlay, 50, 25)
        compare(strokes.count, 0)
        compare(canvasPan.presses, 1)

        overlay.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(overlayCancelled.count, 0)
    }

    function test_middleButtonAndWheelPassThrough() {
        mouseDrag(overlay, 20, 10, 40, 30, Qt.MiddleButton)
        compare(canvasPan.presses, 1)
        compare(strokes.count, 0)

        mouseWheel(overlay, 50, 25, 0, 120, Qt.NoButton)
        compare(canvasPan.wheelEvents, 1)
        compare(strokes.count, 0)
    }

    function test_disablingDuringDragCancelsCommit() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton)
        overlay.inputEnabled = false
        mouseRelease(overlay, 80, 60)
        compare(strokes.count, 0)
        compare(overlayCancelled.count, 0)
        compare(overlay.drawing, false)
    }

    // ── Settings panel ──────────────────────────────────────────────────────

    function test_panelScrollsCleanlyAtCompactHeight() {
        panel.height = 320
        waitForRendering(panel)
        const scroller = panelChild("brush-scroll")
        verify(scroller !== null)
        verify(scroller.contentHeight > scroller.height,
               "brush panel should scroll at compact height")
        compare(scroller.contentWidth, scroller.width)

        const slider = panelChild("brush-diameter")
        const reset = panelChild("brush-reset")
        verify(slider.width <= scroller.width)
        verify(reset.width <= scroller.width)

        scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
        waitForRendering(panel)
        panel.diameter = 96
        mouseClick(reset)
        compare(panel.diameter, panel.defaultDiameter)
    }

    function test_panelDefaultsAndObjectNames() {
        compare(panel.diameter, 24)
        verify(Qt.colorEqual(panel.color, panel.blackColor))

        const slider = panelChild("brush-diameter")
        verify(slider !== null)
        compare(slider.from, 4)
        compare(slider.to, 512)
        compare(slider.value, 24)
        compare(panelChild("brush-diameter-value").text, "24 px")

        const names = ["brush-color-black", "brush-color-white",
                       "brush-color-warm-grey", "brush-color-peach",
                       "brush-color-red", "brush-color-blue",
                       "brush-hex-field", "brush-reset", "brush-hint"]
        for (let i = 0; i < names.length; ++i)
            verify(panelChild(names[i]) !== null, "missing " + names[i])

        compare(panelChild("brush-color-black").selected, true)
    }

    function test_panelSliderChangesDiameter() {
        const slider = panelChild("brush-diameter")
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.diameter, 25)
        keyClick(Qt.Key_Left)
        compare(panel.diameter, 24)

        mouseClick(slider, 0, slider.height / 2)
        compare(panel.diameter, 4)
        slider.forceActiveFocus()
        keyClick(Qt.Key_End)
        compare(panel.diameter, 512)

        // External changes follow without dragging the handle.
        panel.diameter = 96
        compare(slider.value, 96)
    }

    function test_panelColourSwatches() {
        const swatches = [
            { name: "brush-color-black", value: panel.blackColor },
            { name: "brush-color-white", value: panel.whiteColor },
            { name: "brush-color-warm-grey", value: panel.warmGreyColor },
            { name: "brush-color-peach", value: panel.peachColor },
            { name: "brush-color-red", value: panel.redColor },
            { name: "brush-color-blue", value: panel.blueColor }
        ]

        for (let i = 0; i < swatches.length; ++i) {
            const swatch = panelChild(swatches[i].name)
            verify(swatch !== null)
            mouseClick(swatch)
            verify(Qt.colorEqual(panel.color, swatches[i].value),
                   "wrong colour after clicking " + swatches[i].name)
            compare(swatch.selected, true)
        }

        compare(panelChild("brush-color-black").selected, false)
    }

    function test_panelHexFieldAcceptsAndRejects() {
        const hex = panelChild("brush-hex-field")
        verify(hex !== null)
        hex.forceActiveFocus()
        verify(hex.activeFocus, "hex field did not take focus")

        hex.text = "#4a6fa5"
        keyClick(Qt.Key_Return)
        verify(Qt.colorEqual(panel.color, "#4a6fa5"))
        compare(hex.text, "#4a6fa5")

        hex.text = "abc"
        keyClick(Qt.Key_Return)
        verify(Qt.colorEqual(panel.color, "#aabbcc"))
        compare(hex.text, "#aabbcc")

        hex.text = "not-a-colour"
        keyClick(Qt.Key_Return)
        verify(Qt.colorEqual(panel.color, "#aabbcc"))
        compare(hex.text, "#aabbcc")
    }

    function test_panelResetRestoresDefaults() {
        panel.diameter = 100
        panel.color = "#123456"
        mouseClick(panelChild("brush-reset"))
        compare(panel.diameter, 24)
        verify(Qt.colorEqual(panel.color, panel.blackColor))
    }

    function test_panelDisabledLocksControls() {
        panel.enabled = false
        const slider = panelChild("brush-diameter")
        const hex = panelChild("brush-hex-field")
        const reset = panelChild("brush-reset")
        const white = panelChild("brush-color-white")
        verify(!slider.enabled)
        verify(!hex.enabled)
        verify(!reset.enabled)
        verify(!white.enabled)

        mouseClick(white)
        verify(Qt.colorEqual(panel.color, panel.blackColor))
        mouseClick(reset)
        compare(panel.diameter, 24)

        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.diameter, 24)
    }
}
