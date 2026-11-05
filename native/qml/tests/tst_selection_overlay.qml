import QtQuick
import QtTest
import "../overlays"
import "../UI"

/*!
    Contract tests for SelectionOverlay.

    The overlay is exercised directly (no EditorCanvas) with deterministic
    object hooks, so coordinate mapping, hit-testing, drag previews, clamping,
    keyboard commands, pass-through and viewport-backed drawing are all
    independent of the document controller.
*/
TestCase {
    id: testCase
    name: "SelectionOverlay"
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

    // Deterministic object layer: document-pixel boxes, ordered bottom→top.
    Item {
        id: scene
        property var boxes: ({})
        property var order: []
        function hitAt(x, y) {
            for (let i = order.length - 1; i >= 0; --i) {
                const id = order[i]
                const b = boxes[id]
                if (b && x >= b.x && x <= b.x + b.width
                        && y >= b.y && y <= b.y + b.height)
                    return id
            }
            return 0
        }
        function boundsFor(id) {
            return boxes[id] || Qt.rect(0, 0, 0, 0)
        }
    }

    SelectionOverlay {
        id: overlay
        objectName: "selectionOverlay"
        x: 30
        y: 24
        imageWidth: 1000
        imageHeight: 500
        viewScale: 0.25
    }

    SignalSpy { id: moves; target: overlay; signalName: "moveRequested" }
    SignalSpy { id: removes; target: overlay; signalName: "removeRequested" }
    SignalSpy { id: selections; target: overlay; signalName: "selectionChanged" }
    SignalSpy { id: doubleClicks; target: overlay; signalName: "doubleClicked" }
    SignalSpy { id: cancels; target: overlay; signalName: "cancelled" }

    function initTestCase() {
        // Any binding loop or runtime binding error must fail the suite.
        failOnWarning(/Binding loop/)
        failOnWarning(/TypeError/)
        failOnWarning(/ReferenceError/)
        failOnWarning(/is not defined/)
        failOnWarning(/Unable to assign/)
    }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true

        scene.boxes = {
            7: Qt.rect(100, 50, 200, 100),
            9: Qt.rect(600, 300, 200, 100)
        }
        scene.order = [7, 9]

        overlay.objectAt = function(imageX, imageY) {
            return scene.hitAt(imageX, imageY)
        }
        overlay.objectBounds = function(id) { return scene.boundsFor(id) }

        overlay.active = false
        overlay.inputEnabled = true
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.25
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        overlay.clearSelection()
        overlay.active = true
        overlay.forceActiveFocus()

        moves.clear()
        removes.clear()
        selections.clear()
        doubleClicks.clear()
        cancels.clear()
        canvasPan.presses = 0
        canvasPan.wheelEvents = 0
    }

    function cleanup() {
        overlay.active = false
        overlay.clearSelection()
    }

    function previewCanvas() {
        return findChild(overlay, "selectionPreview")
    }

    // ── Mapping ─────────────────────────────────────────────────────────────

    function test_mappingUnderZoomAndPan() {
        compare(overlay.width, 250)
        compare(overlay.height, 125)
        compare(overlay.scaleX, 0.25)
        compare(overlay.scaleY, 0.25)

        // Local display pixels → document pixels.
        let p = overlay.pointAt(50, 25)
        compare(p.x, 200)
        compare(p.y, 100)
        p = overlay.pointAt(0, 0)
        compare(p.x, 0)
        compare(p.y, 0)
        // Edges map to the far image edge.
        p = overlay.pointAt(250, 125)
        compare(p.x, 1000)
        compare(p.y, 500)

        // Document pixels → local display pixels.
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

        // Panning only moves the viewport; the pixel↔image mapping is stable.
        overlay.visibleRect = Qt.rect(120, 40, 300, 200)
        p = overlay.pointAt(50, 25)
        compare(p.x, 100)
        compare(p.y, 50)

        // Non-finite input is ignored rather than poisoning the gesture.
        p = overlay.pointAt(NaN, 10)
        compare(p.x, 0)
        compare(p.y, 0)
        p = overlay.pointAt(10, Infinity)
        compare(p.x, 0)
        compare(p.y, 0)
    }

    // ── Selection ───────────────────────────────────────────────────────────

    function test_clickSelectsAndMissClears() {
        compare(overlay.selectedId, 0)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))

        mouseClick(overlay, 50, 25) // → image (200, 100), id 7
        compare(overlay.selectedId, 7)
        compare(overlay.selectedBounds, Qt.rect(25, 12.5, 50, 25))
        compare(selections.count, 1)
        compare(selections.signalArguments[0][0], 7)

        mouseClick(overlay, 175, 87) // → image (700, 348), id 9
        compare(overlay.selectedId, 9)
        compare(overlay.selectedBounds, Qt.rect(150, 75, 50, 25))
        compare(selections.count, 2)
        compare(selections.signalArguments[1][0], 9)

        mouseClick(overlay, 10, 10) // → image (40, 40), miss
        compare(overlay.selectedId, 0)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))
        compare(selections.count, 3)
        compare(selections.signalArguments[2][0], 0)

        // A second miss with nothing selected must not re-emit.
        mouseClick(overlay, 10, 10)
        compare(selections.count, 3)
    }

    function test_selectAtClampsAndSetSelectionApi() {
        compare(overlay.selectAt(200, 100), 7)
        compare(overlay.selectedId, 7)

        // Out-of-image coordinates clamp before the hit test.
        compare(overlay.selectAt(-100, -100), 0)
        compare(overlay.selectedId, 0)
        compare(overlay.selectAt(99999, 99999), 0)

        overlay.setSelection(9)
        compare(overlay.selectedId, 9)
        compare(overlay.selectedBounds, Qt.rect(150, 75, 50, 25))
        overlay.setSelection(7)
        compare(overlay.selectedId, 7)
        compare(overlay.selectedBounds, Qt.rect(25, 12.5, 50, 25))

        overlay.clearSelection()
        compare(overlay.selectedId, 0)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))
        const count = selections.count
        overlay.clearSelection()
        compare(selections.count, count)

        // Unknown ids may be selected programmatically (Delete still works)
        // but produce no drawable box.
        overlay.setSelection(123456)
        compare(overlay.selectedId, 123456)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))
    }

    function test_topmostObjectWinsHitTest() {
        scene.boxes = {
            4: Qt.rect(100, 50, 200, 100),
            5: Qt.rect(150, 75, 200, 100)
        }
        scene.order = [4, 5]
        compare(overlay.selectAt(200, 100), 5) // overlap → topmost
        compare(overlay.selectedId, 5)
        compare(overlay.selectAt(110, 60), 4) // only the lower box here
        compare(overlay.selectedId, 4)
    }

    // ── Drag preview / move commit ──────────────────────────────────────────

    function test_dragPreviewsThenEmitsOneMove() {
        overlay.selectAt(200, 100)
        compare(overlay.selectedId, 7)
        selections.clear()

        mousePress(overlay, 50, 25)
        compare(overlay.dragging, true)
        mouseMove(overlay, 55, 28)
        mouseMove(overlay, 70, 35)
        // Preview only: the controller must not see per-move calls.
        compare(moves.count, 0)
        compare(overlay.dragging, true)
        compare(overlay.previewDelta, Qt.point(80, 40))
        compare(overlay.previewBounds, Qt.rect(45, 22.5, 50, 25))
        // The committed box stays put until the controller confirms.
        compare(overlay.selectedBounds, Qt.rect(25, 12.5, 50, 25))

        mouseRelease(overlay, 70, 35)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][0], 7)
        compare(moves.signalArguments[0][1], 80)
        compare(moves.signalArguments[0][2], 40)
        compare(overlay.dragging, false)
        compare(overlay.previewBounds, Qt.rect(0, 0, 0, 0))
        compare(overlay.previewDelta, Qt.point(0, 0))
        // Selection survives the move.
        compare(overlay.selectedId, 7)
    }

    function test_dragFromUnselectedObjectSelectsAndMoves() {
        compare(overlay.selectedId, 0)
        mousePress(overlay, 175, 87) // id 9 at image (700, 348)
        compare(overlay.selectedId, 9)
        mouseMove(overlay, 165, 80) // image (660, 320)
        compare(moves.count, 0)
        compare(overlay.previewDelta, Qt.point(-40, -28))
        mouseRelease(overlay, 165, 80)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][0], 9)
        compare(moves.signalArguments[0][1], -40)
        compare(moves.signalArguments[0][2], -28)
    }

    function test_clickOnSelectedBoxWithoutMovementDoesNotMove() {
        overlay.selectAt(200, 100)
        mouseClick(overlay, 50, 25)
        compare(moves.count, 0)
        compare(overlay.selectedId, 7)
    }

    // ── Double click ────────────────────────────────────────────────────────

    function test_doubleClickOnSelectedObjectEmitsOnceAndDoesNotMove() {
        overlay.selectAt(200, 100)
        compare(overlay.selectedId, 7)
        selections.clear()

        mouseDoubleClickSequence(overlay, 50, 25) // inside the selected box
        compare(doubleClicks.count, 1)
        compare(doubleClicks.signalArguments[0][0], 7)
        // The second press must not start or commit a move.
        compare(moves.count, 0)
        compare(overlay.dragging, false)
        compare(overlay.previewDelta, Qt.point(0, 0))
        compare(overlay.selectedId, 7)
        compare(selections.count, 0)
    }

    function test_doubleClickDirectlyOnUnselectedObjectSelectsAndEmits() {
        compare(overlay.selectedId, 0)
        mouseDoubleClickSequence(overlay, 175, 87) // image (700, 348), id 9
        compare(doubleClicks.count, 1)
        compare(doubleClicks.signalArguments[0][0], 9)
        compare(overlay.selectedId, 9)
        compare(moves.count, 0)
        compare(overlay.dragging, false)
    }

    function test_doubleClickOnEmptySpaceEmitsNothing() {
        overlay.selectAt(200, 100)
        selections.clear()
        mouseDoubleClickSequence(overlay, 10, 10) // image (40, 40), no object
        compare(doubleClicks.count, 0)
        compare(moves.count, 0)
        // A miss still clears the selection, matching a normal click.
        compare(overlay.selectedId, 0)
    }

    function test_doubleClickAndDragKeepIndependentContracts() {
        overlay.selectAt(200, 100)
        mouseDoubleClickSequence(overlay, 50, 25)
        compare(doubleClicks.count, 1)

        // A subsequent single drag still moves exactly once.
        mousePress(overlay, 50, 25)
        compare(overlay.dragging, true)
        mouseMove(overlay, 60, 30)
        mouseRelease(overlay, 60, 30)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][1], 40)
        compare(moves.signalArguments[0][2], 20)
    }

    function test_dragClampsToImageEdges() {
        overlay.selectAt(200, 100)

        // Bottom-right: requested (760, -80) becomes (700, -50).
        mousePress(overlay, 50, 25)
        mouseMove(overlay, 240, 5) // image (960, 20)
        compare(overlay.previewDelta, Qt.point(700, -50))
        compare(overlay.previewBounds, Qt.rect(200, 0, 50, 25))
        mouseRelease(overlay, 240, 5)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][1], 700)
        compare(moves.signalArguments[0][2], -50)

        // Top-left: requested (-180, 380) becomes (-100, 350).
        mousePress(overlay, 50, 25)
        mouseMove(overlay, 5, 120) // image (20, 480)
        compare(overlay.previewDelta, Qt.point(-100, 350))
        compare(overlay.previewBounds, Qt.rect(0, 100, 50, 25))
        mouseRelease(overlay, 5, 120)
        compare(moves.count, 2)
        compare(moves.signalArguments[1][1], -100)
        compare(moves.signalArguments[1][2], 350)
    }

    function test_oversizedObjectLocksAxis() {
        scene.boxes = { 21: Qt.rect(-50, 50, 1200, 100) }
        scene.order = [21]
        overlay.setSelection(21)

        mousePress(overlay, 50, 25) // image (200, 100), inside the box
        mouseMove(overlay, 100, 40) // image (400, 160)
        // Wider than the image: x is locked; y still clamps to the image.
        compare(overlay.previewDelta, Qt.point(0, 60))
        // The locked axis keeps the object's existing (off-image) x.
        compare(overlay.previewBounds, Qt.rect(-12.5, 27.5, 300, 25))
        mouseRelease(overlay, 100, 40)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][0], 21)
        compare(moves.signalArguments[0][1], 0)
        compare(moves.signalArguments[0][2], 60)
    }

    function test_escapeDuringDragDiscardsMove() {
        overlay.selectAt(200, 100)
        mousePress(overlay, 50, 25)
        mouseMove(overlay, 70, 35)
        compare(overlay.dragging, true)
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(moves.count, 0)
        compare(cancels.count, 1)
        compare(overlay.selectedId, 0)
        compare(overlay.dragging, false)
        mouseRelease(overlay, 70, 35)
        compare(moves.count, 0)
    }

    // ── Keyboard commands ───────────────────────────────────────────────────

    function test_deleteAndBackspaceRemoveOnce() {
        overlay.selectAt(700, 348)
        compare(overlay.selectedId, 9)
        overlay.forceActiveFocus()

        keyClick(Qt.Key_Delete)
        compare(removes.count, 1)
        compare(removes.signalArguments[0][0], 9)
        compare(overlay.selectedId, 0)
        compare(selections.signalArguments[selections.count - 1][0], 0)

        // No selection: nothing more is emitted.
        keyClick(Qt.Key_Delete)
        compare(removes.count, 1)

        overlay.setSelection(7)
        keyClick(Qt.Key_Backspace)
        compare(removes.count, 2)
        compare(removes.signalArguments[1][0], 7)
        compare(overlay.selectedId, 0)
    }

    function test_escapeClearsAndCancels() {
        overlay.selectAt(200, 100)
        compare(overlay.selectedId, 7)
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(cancels.count, 1)
        compare(overlay.selectedId, 0)
        compare(selections.signalArguments[selections.count - 1][0], 0)

        // Escape with no selection still reports cancellation.
        keyClick(Qt.Key_Escape)
        compare(cancels.count, 2)
    }

    function test_arrowKeysNudgeSelection() {
        overlay.selectAt(200, 100)
        overlay.forceActiveFocus()

        keyClick(Qt.Key_Right)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][0], 7)
        compare(moves.signalArguments[0][1], 1)
        compare(moves.signalArguments[0][2], 0)

        keyClick(Qt.Key_Up, Qt.ShiftModifier)
        compare(moves.count, 2)
        compare(moves.signalArguments[1][1], 0)
        compare(moves.signalArguments[1][2], -10)
    }

    // ── Disabled / pass-through ─────────────────────────────────────────────

    function test_inactiveAndDisabledIgnoreInput_data() {
        return [{ tag: "inactive", active: false, input: true },
                { tag: "disabled", active: true, input: false }]
    }

    function test_inactiveAndDisabledIgnoreInput(data) {
        overlay.selectAt(200, 100)
        compare(overlay.selectedId, 7)
        const selectionCount = selections.count
        moves.clear()
        removes.clear()
        cancels.clear()

        overlay.active = data.active
        overlay.inputEnabled = data.input
        compare(overlay.visible, false)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))
        const preview = previewCanvas()
        compare(preview.visible, false)

        mouseClick(overlay, 175, 87) // id 9 position
        compare(overlay.selectedId, 7) // untouched by input
        compare(selections.count, selectionCount)
        compare(moves.count, 0)
        compare(canvasPan.presses, 1)

        keyClick(Qt.Key_Delete)
        keyClick(Qt.Key_Escape)
        compare(removes.count, 0)
        compare(cancels.count, 0)
    }

    function test_middleButtonAndWheelPassThrough() {
        overlay.selectAt(200, 100)
        mouseDrag(overlay, 50, 25, 20, 10, Qt.MiddleButton)
        compare(canvasPan.presses, 1)
        compare(overlay.dragging, false)
        compare(overlay.selectedId, 7)
        compare(moves.count, 0)

        mouseWheel(overlay, 50, 25, 0, 120, Qt.NoButton)
        compare(canvasPan.wheelEvents, 1)
        compare(moves.count, 0)
        compare(cancels.count, 0)
    }

    function test_nullHooksAreSafe() {
        overlay.clearSelection()
        overlay.objectAt = null
        overlay.objectBounds = null
        const count = selections.count

        mouseClick(overlay, 50, 25)
        compare(overlay.selectedId, 0)
        compare(selections.count, count)
        compare(moves.count, 0)

        overlay.setSelection(7)
        compare(overlay.selectedId, 7)
        compare(overlay.selectedBounds, Qt.rect(0, 0, 0, 0))

        // A throwing hook must be contained, never propagated.
        overlay.objectAt = function() { throw new Error("boom") }
        compare(overlay.selectAt(200, 100), 0)
        compare(overlay.selectedId, 0)
    }

    // ── Drawing / viewport backing / focus ─────────────────────────────────

    function test_previewCanvasIsViewportBacked() {
        const preview = previewCanvas()
        verify(preview !== null)
        compare(preview.x, 0)
        compare(preview.y, 0)
        compare(preview.width, overlay.width)
        compare(preview.height, overlay.height)

        // A panned viewport bounds the raster backing.
        overlay.visibleRect = Qt.rect(40, 20, 120, 60)
        compare(preview.x, 40)
        compare(preview.y, 20)
        compare(preview.width, 120)
        compare(preview.height, 60)

        // A huge image at high zoom still only rasterises the viewport.
        overlay.imageWidth = 100000
        overlay.imageHeight = 100000
        overlay.viewScale = 0.01
        compare(overlay.width, 1000)
        compare(overlay.height, 1000)
        overlay.visibleRect = Qt.rect(100, 120, 200, 150)
        compare(preview.x, 100)
        compare(preview.y, 120)
        compare(preview.width, 200)
        compare(preview.height, 150)
        verify(preview.width <= 200 && preview.height <= 150)
    }

    function test_focusContractAndRing() {
        overlay.clearSelection()
        compare(overlay.focus, true)
        overlay.forceActiveFocus()
        tryVerify(function() { return overlay.activeFocus }, 1000)

        const ring = findChild(overlay, "selectionFocusRing")
        verify(ring !== null)
        compare(ring.visible, true)

        overlay.active = false
        compare(ring.visible, false)
    }

    function test_hoverCursorTracksObjects() {
        overlay.clearSelection()
        const pointer = findChild(overlay, "selectionPointer")
        verify(pointer !== null)
        compare(overlay.hoveringObject, false)

        mouseMove(overlay, 50, 25) // over id 7
        compare(overlay.hoveringObject, true)
        compare(pointer.cursorShape, Qt.PointingHandCursor)

        mouseMove(overlay, 10, 10) // empty image area
        compare(overlay.hoveringObject, false)
        compare(pointer.cursorShape, Qt.ArrowCursor)

        // Once selected, the inside-box cursor is the open hand.
        overlay.selectAt(200, 100)
        mouseMove(overlay, 50, 25)
        compare(overlay.hoveringSelected, true)
        compare(pointer.cursorShape, Qt.OpenHandCursor)
    }
}
