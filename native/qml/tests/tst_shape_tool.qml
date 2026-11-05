import QtQuick
import QtTest
import "../overlays"
import "../UI"

/*!
    Contract tests for the shape tool.

    ShapeOverlay is exercised directly (no EditorCanvas) with fixed image
    dimensions and zoom, so coordinate mapping, Shift constraints, payload
    normalisation, pass-through and viewport-backed drawing are deterministic.
    ShapePanel is instantiated from its normal QML component and driven with
    real mouse/key events.
*/
TestCase {
    id: testCase
    name: "ShapeTool"
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

    ShapeOverlay {
        id: overlay
        objectName: "shapeOverlay"
        x: 30
        y: 24
        imageWidth: 1000
        imageHeight: 500
        viewScale: 0.25
    }

    Loader {
        id: panelLoader
        // Keep the panel clear of the overlay's hit area.
        x: 480
        y: 20
        width: 292
        height: 640
        source: "../panels/ShapePanel.qml"
    }
    property var panel: panelLoader.item

    SignalSpy { id: commits; target: overlay; signalName: "shapeCommitted" }
    SignalSpy { id: cancels; target: overlay; signalName: "cancelled" }

    function initTestCase() {
        // Any binding loop or runtime binding error must fail the suite.
        failOnWarning(/Binding loop/)
        failOnWarning(/TypeError/)
        failOnWarning(/ReferenceError/)
        failOnWarning(/is not defined/)
        failOnWarning(/Unable to assign/)
        compare(panelLoader.status, Loader.Ready)
        verify(panel !== null)
    }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true

        overlay.active = false
        overlay.inputEnabled = true
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.25
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        overlay.shapeKind = "rectangle"
        overlay.fillColor = "#ffffff"
        overlay.strokeColor = "#000000"
        overlay.strokeWidth = 4
        overlay.cornerRadius = 0
        overlay.filled = true
        overlay.reset()
        overlay.active = true
        overlay.forceActiveFocus()

        commits.clear()
        cancels.clear()
        canvasPan.presses = 0
        canvasPan.wheelEvents = 0

        panel.enabled = true
        panel.shapeKind = "rectangle"
        panel.filled = true
        panel.fillColor = panel.whiteColor
        panel.strokeColor = panel.blackColor
        panel.strokeWidth = 4
        panel.cornerRadius = 0
        const fillToggle = findChild(panel, "shape-filled")
        if (fillToggle !== null)
            fillToggle.checked = true
    }

    function cleanup() {
        overlay.active = false
        overlay.reset()
        panel.enabled = true
    }

    function previewCanvas() {
        return findChild(overlay, "shapePreview")
    }

    // ── Coordinate mapping ──────────────────────────────────────────────────

    function test_focusRingOnlyForKeyboardFocus() {
        overlay.active = true
        const ring = findChild(overlay, "shapeFocusRing")
        verify(ring !== null)
        verify(overlay.activeFocus)

        // A mouse press grabs focus without a keyboard ring.
        mouseClick(overlay, 50, 50)
        compare(ring.visible, false)

        canvasPan.forceActiveFocus()
        verify(!overlay.activeFocus)
        overlay.forceActiveFocus(Qt.TabFocusReason)
        verify(overlay.activeFocus)
        compare(ring.visible, true)

        mouseClick(overlay, 100, 100)
        compare(ring.visible, false)
    }

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

        let d = overlay.displayPoint(200, 100)
        compare(d.x, 50)
        compare(d.y, 25)

        // Zoom changes the mapping through the actual display size.
        overlay.viewScale = 0.5
        compare(overlay.width, 500)
        compare(overlay.height, 250)
        p = overlay.pointAt(50, 25)
        compare(p.x, 100)
        compare(p.y, 50)

        // Panning only moves the viewport; the pixel↔image mapping is stable.
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

        let d = overlay.displayPoint(1000, 500)
        compare(d.x, 250)
        compare(d.y, 125)
    }

    // ── Payloads ────────────────────────────────────────────────────────────

    function test_rectanglePayload() {
        overlay.shapeKind = "rectangle"
        mousePress(overlay, 20, 10)
        compare(overlay.dragging, true)
        compare(overlay.anchorPoint, Qt.point(80, 40))
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton)
        compare(overlay.previewRect, Qt.rect(80, 40, 240, 200))
        mouseRelease(overlay, 80, 60)

        compare(commits.count, 1)
        const args = commits.signalArguments[0]
        compare(args[0], "rectangle")
        compare(args[1], Qt.rect(80, 40, 240, 200))
        compare(overlay.dragging, false)
        compare(overlay.previewRect, Qt.rect(0, 0, 0, 0))
    }

    function test_ellipsePayload() {
        overlay.shapeKind = "ellipse"
        mouseDrag(overlay, 20, 10, 60, 50)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][0], "ellipse")
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 240, 200))
    }

    function test_lineAndArrowPayload() {
        overlay.shapeKind = "line"
        mouseDrag(overlay, 20, 10, 60, 50)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][0], "line")
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 240, 200))

        commits.clear()
        overlay.shapeKind = "arrow"
        mouseDrag(overlay, 20, 10, 60, 50)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][0], "arrow")
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 240, 200))
    }

    function test_linePayloadUsesNormalisedDragDiagonal() {
        // Reverse drags still produce a positive rect whose topLeft→bottomRight
        // diagonal is the drawn segment (addShape's contract).
        overlay.shapeKind = "line"
        mousePress(overlay, 80, 60)
        mouseMove(overlay, 20, 10, 0, Qt.LeftButton)
        mouseRelease(overlay, 20, 10)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 240, 200))
    }

    function test_clickDoesNotCommit() {
        mouseClick(overlay, 60, 30)
        compare(commits.count, 0)
        compare(overlay.dragging, false)
    }

    function test_clampsAtImageEdge() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 250, 125, 0, Qt.LeftButton)
        mouseRelease(overlay, 250, 125)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 920, 460))
    }

    // ── Shift constraints ───────────────────────────────────────────────────

    function test_shiftSquare_data() {
        return [{ tag: "rectangle", kind: "rectangle" },
                { tag: "ellipse", kind: "ellipse" }]
    }

    function test_shiftSquare(data) {
        overlay.shapeKind = data.kind
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 30, 0, Qt.LeftButton, Qt.ShiftModifier)
        compare(overlay.shiftConstrained, true)
        compare(overlay.previewRect, Qt.rect(80, 40, 240, 240))
        mouseRelease(overlay, 80, 30, Qt.LeftButton, Qt.ShiftModifier)

        compare(commits.count, 1)
        compare(commits.signalArguments[0][0], data.kind)
        const area = commits.signalArguments[0][1]
        compare(area, Qt.rect(80, 40, 240, 240))
        compare(area.width, area.height)
    }

    function test_shiftSquareStaysInsideImageAtEdge() {
        overlay.shapeKind = "rectangle"
        mousePress(overlay, 240, 120) // image (960, 480)
        mouseMove(overlay, 20, 10, 0, Qt.LeftButton, Qt.ShiftModifier)
        const area = overlay.previewRect
        compare(area.width, area.height)
        verify(area.x >= 0 && area.y >= 0)
        verify(area.x + area.width <= overlay.imageWidth + 0.001)
        verify(area.y + area.height <= overlay.imageHeight + 0.001)
        compare(area, Qt.rect(480, 0, 480, 480))
        mouseRelease(overlay, 20, 10, Qt.LeftButton, Qt.ShiftModifier)
        compare(commits.count, 1)
    }

    function test_shiftSnapsLineTo45Degrees() {
        overlay.shapeKind = "line"
        mousePress(overlay, 20, 10) // image (80, 40)
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton, Qt.ShiftModifier)
        compare(overlay.shiftConstrained, true)
        const area = overlay.previewRect
        // Raw drag: 240 x 200 image px (39.8°) snaps to 45° at the same length.
        fuzzyCompare(area.width, area.height, 0.001)
        fuzzyCompare(area.width, 220.906, 0.05)
        mouseRelease(overlay, 80, 60, Qt.LeftButton, Qt.ShiftModifier)

        compare(commits.count, 1)
        const committed = commits.signalArguments[0][1]
        fuzzyCompare(committed.width, committed.height, 0.001)
        fuzzyCompare(committed.width, 220.906, 0.05)
    }

    function test_withoutShiftUsesFreeDiagonal() {
        overlay.shapeKind = "line"
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton)
        compare(overlay.shiftConstrained, false)
        compare(overlay.previewRect, Qt.rect(80, 40, 240, 200))
        mouseRelease(overlay, 80, 60)
        compare(commits.count, 1)
        compare(commits.signalArguments[0][1], Qt.rect(80, 40, 240, 200))
    }

    // ── Preview ─────────────────────────────────────────────────────────────

    function test_filledAndStrokeOnlyPreviews() {
        const preview = previewCanvas()
        verify(preview !== null)

        overlay.shapeKind = "rectangle"
        overlay.filled = true
        overlay.fillColor = "#ff0000"
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 200, 100, 0, Qt.LeftButton)
        compare(overlay.dragging, true)
        tryVerify(function() {
            return preview.getContext("2d").getImageData(110, 55, 1, 1).data[3] > 0
        }, 1000, "Filled preview must tint its interior")

        // Switching the fill off repaints as outline-only.
        overlay.filled = false
        tryVerify(function() {
            return preview.getContext("2d").getImageData(110, 55, 1, 1).data[3] === 0
        }, 1000, "Stroke-only preview must leave its interior clear")

        mouseRelease(overlay, 200, 100)
        compare(commits.count, 1)
        // The preview is cleared after a commit.
        tryVerify(function() {
            return preview.getContext("2d").getImageData(110, 55, 1, 1).data[3] === 0
        }, 1000, "Preview must clear after the drag ends")
    }

    function test_viewportBackedDrawing() {
        const preview = previewCanvas()
        verify(preview !== null)

        overlay.imageWidth = 8192
        overlay.imageHeight = 8192
        overlay.viewScale = 3
        overlay.visibleRect = Qt.rect(100, 80, 300, 200)

        compare(preview.x, 100)
        compare(preview.y, 80)
        verify(preview.width <= 300.001)
        verify(preview.height <= 200.001)
        verify(preview.x + preview.width <= overlay.width + 0.001)
        verify(preview.y + preview.height <= overlay.height + 0.001)
        // The raster backing never grows to the full zoomed image.
        verify(preview.width < overlay.width)
        verify(preview.height < overlay.height)
    }

    // ── Cancellation / input gating ─────────────────────────────────────────

    function test_escapeCancelsGesture() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton)
        keyClick(Qt.Key_Escape)
        compare(cancels.count, 1)
        compare(overlay.dragging, false)
        compare(overlay.previewRect, Qt.rect(0, 0, 0, 0))

        // A release after Esc must not commit the cancelled shape.
        mouseRelease(overlay, 80, 60)
        compare(commits.count, 0)
    }

    function test_escapeWithoutGestureCancelsTool() {
        keyClick(Qt.Key_Escape)
        compare(cancels.count, 1)
        compare(commits.count, 0)
    }

    function test_inactiveAndDisabledIgnoreInput_data() {
        return [{ tag: "inactive", active: false, input: true },
                { tag: "disabled", active: true, input: false }]
    }

    function test_inactiveAndDisabledIgnoreInput(data) {
        overlay.active = data.active
        overlay.inputEnabled = data.input

        mouseClick(overlay, 50, 25)
        compare(commits.count, 0)
        compare(canvasPan.presses, 1)

        keyClick(Qt.Key_Escape)
        compare(cancels.count, 0)
    }

    function test_middleButtonAndWheelPassThrough() {
        mouseDrag(overlay, 20, 10, 40, 30, Qt.MiddleButton)
        compare(canvasPan.presses, 1)
        compare(commits.count, 0)

        mouseWheel(overlay, 50, 25, 0, 120, Qt.NoButton)
        compare(canvasPan.wheelEvents, 1)
        compare(commits.count, 0)
    }

    function test_disablingDuringDragCancelsCommit() {
        mousePress(overlay, 20, 10)
        mouseMove(overlay, 80, 60, 0, Qt.LeftButton)
        overlay.inputEnabled = false
        mouseRelease(overlay, 80, 60)
        compare(commits.count, 0)
        compare(overlay.dragging, false)
    }

    // ── Panel ───────────────────────────────────────────────────────────────

    function test_panelDefaults() {
        compare(panel.shapeKind, "rectangle")
        compare(panel.filled, true)
        compare(panel.strokeWidth, 4)
        compare(panel.cornerRadius, 0)
        compare(panel.supportsFill, true)
        compare(panel.supportsCorner, true)

        const rectangle = findChild(panel, "shape-type-rectangle")
        const ellipse = findChild(panel, "shape-type-ellipse")
        const line = findChild(panel, "shape-type-line")
        const arrow = findChild(panel, "shape-type-arrow")
        verify(rectangle !== null && ellipse !== null && line !== null && arrow !== null)
        compare(rectangle.variant, "primary")
        compare(ellipse.variant, "secondary")

        const toggle = findChild(panel, "shape-filled")
        verify(toggle !== null)
        compare(toggle.checked, true)
        const strokeSlider = findChild(panel, "shape-stroke-width")
        verify(strokeSlider !== null)
        compare(strokeSlider.from, 0)
        compare(strokeSlider.to, 40)
        compare(strokeSlider.value, 4)
        const cornerSlider = findChild(panel, "shape-corner-radius")
        verify(cornerSlider !== null)
        compare(cornerSlider.from, 0)
        compare(cornerSlider.to, 64)
        compare(cornerSlider.enabled, true)
    }

    function test_panelShapeSelector() {
        const kinds = ["ellipse", "line", "arrow", "rectangle"]
        for (let i = 0; i < kinds.length; ++i) {
            const kind = kinds[i]
            const button = findChild(panel, "shape-type-" + kind)
            verify(button !== null)
            mouseClick(button)
            compare(panel.shapeKind, kind)
        }

        mouseClick(findChild(panel, "shape-type-line"))
        compare(panel.shapeKind, "line")
        compare(panel.supportsFill, false)
        compare(panel.supportsCorner, false)
        verify(!findChild(panel, "shape-filled").enabled)
        verify(!findChild(panel, "shape-fill-red").enabled)
        verify(!findChild(panel, "shape-corner-radius").enabled)
        verify(findChild(panel, "shape-stroke-blue").enabled)

        mouseClick(findChild(panel, "shape-type-ellipse"))
        compare(panel.shapeKind, "ellipse")
        compare(panel.supportsFill, true)
        compare(panel.supportsCorner, false)
        verify(findChild(panel, "shape-fill-red").enabled)
        verify(!findChild(panel, "shape-corner-radius").enabled)

        mouseClick(findChild(panel, "shape-type-rectangle"))
        verify(findChild(panel, "shape-corner-radius").enabled)
    }

    function test_panelFillToggleAndSwatches() {
        const toggle = findChild(panel, "shape-filled")
        verify(toggle !== null)
        compare(toggle.checked, true)

        mouseClick(toggle)
        compare(panel.filled, false)
        compare(toggle.checked, false)

        mouseClick(toggle)
        compare(panel.filled, true)
        compare(toggle.checked, true)

        const red = findChild(panel, "shape-fill-red")
        const white = findChild(panel, "shape-fill-white")
        verify(red !== null && white !== null)
        compare(white.selected, true)
        mouseClick(red)
        verify(Qt.colorEqual(panel.fillColor, panel.redColor))
        compare(red.selected, true)
        compare(white.selected, false)

        const blue = findChild(panel, "shape-stroke-blue")
        verify(blue !== null)
        mouseClick(blue)
        verify(Qt.colorEqual(panel.strokeColor, panel.blueColor))
        compare(blue.selected, true)
        compare(findChild(panel, "shape-stroke-black").selected, false)
    }

    function test_panelSliders() {
        const strokeSlider = findChild(panel, "shape-stroke-width")
        strokeSlider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.strokeWidth, 5)
        keyClick(Qt.Key_End)
        compare(panel.strokeWidth, 40)
        keyClick(Qt.Key_Home)
        compare(panel.strokeWidth, 0)
        verify(findChild(panel, "shape-stroke-width-value").text.indexOf("0") >= 0)

        const cornerSlider = findChild(panel, "shape-corner-radius")
        cornerSlider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.cornerRadius, 1)
        keyClick(Qt.Key_End)
        compare(panel.cornerRadius, 64)
        keyClick(Qt.Key_Home)
        compare(panel.cornerRadius, 0)
    }

    function test_panelDisabledBlocksControls() {
        panel.enabled = false

        const typeButton = findChild(panel, "shape-type-ellipse")
        const toggle = findChild(panel, "shape-filled")
        const fillSwatch = findChild(panel, "shape-fill-red")
        const strokeSwatch = findChild(panel, "shape-stroke-blue")
        const strokeSlider = findChild(panel, "shape-stroke-width")
        verify(!typeButton.enabled)
        verify(!toggle.enabled)
        verify(!fillSwatch.enabled)
        verify(!strokeSwatch.enabled)
        verify(!strokeSlider.enabled)

        mouseClick(typeButton)
        compare(panel.shapeKind, "rectangle")
        mouseClick(fillSwatch)
        verify(Qt.colorEqual(panel.fillColor, panel.whiteColor))
        compare(panel.strokeWidth, 4)
        compare(panel.cornerRadius, 0)
    }
}
