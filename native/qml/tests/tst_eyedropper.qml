import QtQuick
import QtTest
import "../overlays"
import "../UI"

/*!
    Contract tests for EyedropperOverlay.

    The overlay is exercised directly (no EditorCanvas) with a fixed sampler,
    so colour plumbing, coordinate mapping, clamping, focus/keyboard handling
    and viewport-aware loupe placement are all deterministic.
*/
TestCase {
    id: testCase
    name: "EyedropperOverlay"
    when: windowShown
    visible: true
    width: 700
    height: 500

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

    EyedropperOverlay {
        id: overlay
        objectName: "eyedropper"
        x: 30; y: 24
        imageWidth: 1000
        imageHeight: 500
        viewScale: 0.25
    }

    SignalSpy { id: picked; target: overlay; signalName: "colorPicked" }
    SignalSpy { id: sampled; target: overlay; signalName: "sampled" }
    SignalSpy { id: cancelled; target: overlay; signalName: "cancelled" }

    function overlaysLoupe() {
        return findChild(overlay, "eyedropperLoupe")
    }

    function init() {
        overlay.active = false
        overlay.inputEnabled = true
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.25
        overlay.magnifierSize = 132
        overlay.sampleRadius = 0
        overlay.imageUrl = ""
        overlay.sampler = function(x, y) { return Qt.rgba(1, 0, 0, 1) }
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        overlay.active = true
        overlay.reset()
        picked.clear()
        sampled.clear()
        cancelled.clear()
        canvasPan.presses = 0
        canvasPan.wheelEvents = 0
    }

    function test_geometryAndMapping() {
        compare(overlay.width, 250)
        compare(overlay.height, 125)
        compare(overlay.scaleX, 0.25)
        compare(overlay.scaleY, 0.25)

        // Local display pixels → image pixels.
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

        // Image pixels → local display pixels.
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
    }

    function test_clickPicksSamplerColorAndSamples() {
        overlay.sampler = function(x, y) { return Qt.rgba(0.2, 0.4, 0.6, 1) }
        mouseClick(overlay, 50, 25) // → image (200, 100)

        compare(picked.count, 1)
        const c = picked.signalArguments[0][0]
        fuzzyCompare(c.r, 0.2, 0.01)
        fuzzyCompare(c.g, 0.4, 0.01)
        fuzzyCompare(c.b, 0.6, 0.01)
        verify(sampled.count >= 1)
        const args = sampled.signalArguments[sampled.count - 1]
        compare(args[1], 200)
        compare(args[2], 100)
        compare(overlay.hasSample, true)
        compare(overlay.samplePosition, Qt.point(200, 100))
        compare(overlay.hexText, "#336699")
        compare(overlay.rgbText, "rgb(51, 102, 153)")
    }

    function test_hoverSamplesContinuously() {
        overlay.sampler = function(x, y) {
            return x < 500 ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
        }
        mouseMove(overlay, 100, 50) // image (400, 200)
        verify(sampled.count >= 1)
        let args = sampled.signalArguments[sampled.count - 1]
        compare(args[1], 400)
        compare(args[2], 200)
        fuzzyCompare(args[0].r, 0, 0.01)
        compare(picked.count, 0)

        mouseMove(overlay, 150, 50) // image (600, 200)
        args = sampled.signalArguments[sampled.count - 1]
        compare(args[1], 600)
        compare(args[2], 200)
        fuzzyCompare(args[0].r, 1, 0.01)
        compare(picked.count, 0)
    }

    function test_outOfBoundsClampsAndNonFiniteIsIgnored() {
        compare(overlay.pickAt(-50, -10), true)
        compare(overlay.samplePosition, Qt.point(0, 0))
        compare(overlay.pickAt(99999, 99999), true)
        compare(overlay.samplePosition, Qt.point(999, 499))
        compare(picked.count, 2)

        compare(overlay.pickAt(NaN, 10), false)
        compare(overlay.pickAt(Infinity, 10), false)
        compare(overlay.pickAt(10, -Infinity), false)
        compare(picked.count, 2)

        // A throwing sampler is contained, never propagated.
        overlay.sampler = function() { throw new Error("boom") }
        compare(overlay.pickAt(10, 10), false)
        compare(overlay.hasSample, false)
        compare(picked.count, 2)
    }

    function test_escapeAndRightClickCancel() {
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(cancelled.count, 1)

        mouseClick(overlay, 50, 25, Qt.RightButton)
        compare(cancelled.count, 2)
        compare(picked.count, 0)
    }

    function test_inactiveAndDisabledIgnoreInput_data() {
        return [{ tag: "inactive", active: false, input: true },
                { tag: "disabled", active: true, input: false }]
    }
    function test_inactiveAndDisabledIgnoreInput(data) {
        overlay.active = data.active
        overlay.inputEnabled = data.input
        mouseClick(overlay, 50, 25)
        compare(picked.count, 0)
        compare(sampled.count, 0)
        compare(canvasPan.presses, 1)

        keyClick(Qt.Key_Escape)
        compare(cancelled.count, 0)
    }

    function test_middleButtonAndWheelPassThrough() {
        mouseDrag(overlay, 20, 10, 40, 30, Qt.MiddleButton)
        compare(canvasPan.presses, 1)
        compare(picked.count, 0)
        compare(sampled.count, 0)

        mouseWheel(overlay, 50, 25, 0, 120, Qt.NoButton)
        compare(canvasPan.wheelEvents, 1)
        compare(picked.count, 0)
    }

    function test_loupePositionStaysInsideViewport() {
        overlay.viewScale = 0.5
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        const loupe = overlaysLoupe()
        verify(loupe !== null)
        compare(loupe.width, overlay.magnifierSize)
        compare(loupe.height, overlay.magnifierSize + loupe.readoutHeight)

        let p = overlay.loupePosition(overlay.width - 2, overlay.height - 2)
        verify(p.x >= overlay.loupeMargin - 0.01)
        verify(p.y >= overlay.loupeMargin - 0.01)
        verify(p.x + loupe.width <= overlay.width - overlay.loupeMargin + 0.01)
        verify(p.y + loupe.height <= overlay.height - overlay.loupeMargin + 0.01)

        p = overlay.loupePosition(1, 1)
        verify(p.x >= overlay.loupeMargin - 0.01)
        verify(p.y >= overlay.loupeMargin - 0.01)

        // A panned, narrower viewport still contains the loupe.
        overlay.visibleRect = Qt.rect(40, 30, 260, 210)
        p = overlay.loupePosition(120, 100)
        verify(p.x >= 40 + overlay.loupeMargin - 0.01)
        verify(p.y >= 30 + overlay.loupeMargin - 0.01)
        verify(p.x + loupe.width <= 40 + 260 - overlay.loupeMargin + 0.01)
        verify(p.y + loupe.height <= 30 + 210 - overlay.loupeMargin + 0.01)
    }

    function test_loupeFollowsCursor() {
        overlay.viewScale = 0.5
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        const loupe = overlaysLoupe()
        mouseMove(overlay, 100, 40)
        const expected = overlay.loupePosition(100, 40)
        fuzzyCompare(loupe.x, expected.x, 0.01)
        fuzzyCompare(loupe.y, expected.y, 0.01)
        // Fade/scale-in runs on the Motion tokens; wait for it to settle.
        tryVerify(function() { return loupe.opacity > 0.9 }, 1000)
    }

    function test_loupePreviewSourceRectClampsAtEdges() {
        const loupe = overlaysLoupe()
        loupe.imageWidth = 1000
        loupe.imageHeight = 500
        loupe.sampleX = 0
        loupe.sampleY = 0
        compare(loupe.sourceRect.x, 0)
        compare(loupe.sourceRect.y, 0)
        // Crosshair sits on the sampled pixel, not necessarily centred.
        verify(loupe.crosshairX >= 0 && loupe.crosshairX <= loupe.previewSize)
        verify(loupe.crosshairY >= 0 && loupe.crosshairY <= loupe.previewSize)

        loupe.sampleX = 999
        loupe.sampleY = 499
        verify(loupe.sourceRect.x + loupe.sourceRect.width <= 1000.001)
        verify(loupe.sourceRect.y + loupe.sourceRect.height <= 500.001)
    }

    function test_hexAndRgbFormatting() {
        compare(overlay.hexString(Qt.rgba(237 / 255, 188 / 255, 157 / 255, 1)), "#EDBC9D")
        compare(overlay.hexString("#000000"), "#000000")
        compare(overlay.rgbString(Qt.rgba(237 / 255, 188 / 255, 157 / 255, 1)),
                "rgb(237, 188, 157)")
        compare(overlay.hexString(null), "—")
        compare(overlay.rgbString(undefined), "—")

        overlay.sampler = function() { return Qt.rgba(237 / 255, 188 / 255, 157 / 255, 1) }
        verify(overlay.pickAt(100, 100))
        compare(overlay.hexText, "#EDBC9D")
        compare(overlay.rgbText, "rgb(237, 188, 157)")
    }

    function test_arrowKeysMoveSampleAndEnterPicks() {
        verify(overlay.pickAt(500, 250))
        compare(overlay.samplePosition, Qt.point(500, 250))
        picked.clear()
        sampled.clear()

        overlay.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(overlay.samplePosition, Qt.point(501, 250))
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        compare(overlay.samplePosition, Qt.point(511, 250))
        keyClick(Qt.Key_Up, Qt.ShiftModifier)
        compare(overlay.samplePosition, Qt.point(511, 240))
        keyClick(Qt.Key_Down)
        compare(overlay.samplePosition, Qt.point(511, 241))
        verify(sampled.count >= 4)

        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
        const args = picked.signalArguments[0]
        fuzzyCompare(args[0].r, 1, 0.01)
    }

    function test_arrowKeysClampAtImageEdge() {
        verify(overlay.pickAt(999, 499))
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(overlay.samplePosition, Qt.point(999, 499))
        keyClick(Qt.Key_Down, Qt.ShiftModifier)
        compare(overlay.samplePosition, Qt.point(999, 499))
    }

    function test_nullSamplerShowsPlaceholderAndEmitsNothing() {
        overlay.sampler = null
        mouseMove(overlay, 50, 25)
        compare(sampled.count, 0)
        compare(overlay.hasSample, false)
        compare(overlay.hexText, "—")
        compare(overlay.rgbText, "—")
        compare(overlay.swatchColor, Theme.hover)
        compare(overlay.pickAt(10, 10), false)
        compare(picked.count, 0)
    }

    function test_sampleRadiusAveragesNeighbourhood() {
        overlay.sampleRadius = 1
        overlay.sampler = function(x, y) {
            return (x === 100 && y === 100) ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
        }
        verify(overlay.pickAt(100, 100))
        // One dark pixel out of the nine sampled.
        fuzzyCompare(overlay.currentColor.r, 8 / 9, 0.01)
        fuzzyCompare(overlay.currentColor.g, 8 / 9, 0.01)
        fuzzyCompare(overlay.currentColor.b, 8 / 9, 0.01)
    }

    function test_resetClearsSampleAndLoupe() {
        verify(overlay.pickAt(200, 100))
        compare(overlay.hasSample, true)
        overlay.reset()
        compare(overlay.hasSample, false)
        compare(overlay.hexText, "—")
        const loupe = overlaysLoupe()
        tryVerify(function() { return !loupe.visible || loupe.opacity < 0.01 }, 1000)
    }
}
