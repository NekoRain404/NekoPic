import QtQuick
import QtTest
import "../overlays"
import "../dialogs"
import "../UI"

/*!
    Contract tests for the text tool UI.

    The placement overlay is exercised directly (no EditorCanvas) with fixed
    image dimensions and zoom, so mapping, clamping, pass-through and drawing
    bounds are deterministic. The dialog is instantiated from its normal QML
    component and driven with real mouse/key events.
*/
TestCase {
    id: testCase
    name: "TextTool"
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

    TextPlacementOverlay {
        id: overlay
        objectName: "textPlacementOverlay"
        x: 30
        y: 24
        imageWidth: 1000
        imageHeight: 500
        viewScale: 0.25
    }

    SignalSpy { id: pointSelected; target: overlay; signalName: "pointSelected" }
    SignalSpy { id: overlayCancelled; target: overlay; signalName: "cancelled" }

    Component { id: textDialogComponent; TextDialog {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true

        overlay.active = false
        overlay.inputEnabled = true
        overlay.imageWidth = 1000
        overlay.imageHeight = 500
        overlay.viewScale = 0.25
        overlay.visibleRect = Qt.rect(0, 0, overlay.width, overlay.height)
        overlay.active = true

        pointSelected.clear()
        overlayCancelled.clear()
        canvasPan.presses = 0
        canvasPan.wheelEvents = 0
    }

    function cleanup() {
        overlay.active = false
    }

    function makeDialog(props) {
        return createTemporaryObject(textDialogComponent, testCase, props || {})
    }

    function child(root, name) {
        let found = findChild(root, name)
        if (found === null && root && root.contentItem)
            found = findChild(root.contentItem, name)
        return found
    }

    function openDialog(dialog) {
        dialog.open()
        tryVerify(function() { return dialog.opened }, 3000)
    }

    // ── Placement overlay ───────────────────────────────────────────────────

    function test_placementMappingUnderZoomAndPan() {
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

        p = overlay.displayPoint(1000, 500)
        compare(p.x, 250)
        compare(p.y, 125)
    }

    function test_clickEmitsImageAnchor() {
        mouseClick(overlay, 50, 25)
        compare(pointSelected.count, 1)
        let args = pointSelected.signalArguments[0]
        compare(args[0], 200)
        compare(args[1], 100)
        compare(canvasPan.presses, 0)

        mouseClick(overlay, 0, 0)
        compare(pointSelected.count, 2)
        args = pointSelected.signalArguments[1]
        compare(args[0], 0)
        compare(args[1], 0)

        // Edges clamp to the far image edge.
        const p = overlay.pointAt(overlay.width, overlay.height)
        compare(p.x, 1000)
        compare(p.y, 500)
    }

    function test_crosshairFollowsCursor() {
        mouseMove(overlay, 40, 30)
        compare(overlay.cursorPosition.x, 40)
        compare(overlay.cursorPosition.y, 30)
        verify(overlay.cursorVisible)

        mouseMove(overlay, 120, 90)
        compare(overlay.cursorPosition.x, 120)
        compare(overlay.cursorPosition.y, 90)
        compare(pointSelected.count, 0)
    }

    function test_escapeCancels() {
        overlay.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(overlayCancelled.count, 1)
        compare(pointSelected.count, 0)
    }

    function test_inactiveAndDisabledIgnoreInput_data() {
        return [{ tag: "inactive", active: false, input: true },
                { tag: "disabled", active: true, input: false }]
    }

    function test_inactiveAndDisabledIgnoreInput(data) {
        overlay.active = data.active
        overlay.inputEnabled = data.input

        mouseClick(overlay, 50, 25)
        compare(pointSelected.count, 0)
        compare(canvasPan.presses, 1)

        keyClick(Qt.Key_Escape)
        compare(overlayCancelled.count, 0)
    }

    function test_middleButtonAndWheelPassThrough() {
        mouseDrag(overlay, 20, 10, 40, 30, Qt.MiddleButton)
        compare(canvasPan.presses, 1)
        compare(pointSelected.count, 0)

        mouseWheel(overlay, 50, 25, 0, 120, Qt.NoButton)
        compare(canvasPan.wheelEvents, 1)
        compare(pointSelected.count, 0)
    }

    function test_viewportBackedDrawing() {
        const preview = findChild(overlay, "textPlacementPreview")
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

    // ── Dialog ──────────────────────────────────────────────────────────────

    function test_dialogDefaultsAndTextValidation() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500,
                                    anchorX: 250.4, anchorY: 120.6 })
        verify(dialog !== null)
        compare(dialog.imageWidth, 1000)
        compare(dialog.imageHeight, 500)
        compare(dialog.anchorX, 250.4)
        compare(dialog.anchorY, 120.6)
        compare(dialog.text, "")
        compare(dialog.busy, false)
        compare(dialog.fontSize, 32)
        compare(dialog.alignment, Qt.AlignCenter)

        const accept = child(dialog, "text-dialog-accept")
        verify(accept !== null)
        compare(accept.enabled, false)

        dialog.text = "Hello"
        compare(accept.enabled, true)

        dialog.text = "   \n\t "
        compare(accept.enabled, false)

        dialog.text = "  Hi there  "
        compare(accept.enabled, true)
    }

    function test_fontSizeClamps() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        compare(dialog.minFontSize, 4)
        compare(dialog.maxFontSize, 512)

        dialog.text = "Hello"

        dialog.fontSize = 900
        compare(dialog.fontSize, 512)
        dialog.fontSize = 0
        compare(dialog.fontSize, 4)
        dialog.fontSize = -12
        compare(dialog.fontSize, 4)
        dialog.fontSize = 48
        compare(dialog.fontSize, 48)

        const slider = child(dialog, "text-dialog-font-size")
        verify(slider !== null)
        compare(slider.from, 4)
        compare(slider.to, 512)
        compare(slider.value, 48)

        const valueLabel = child(dialog, "text-dialog-font-size-value")
        verify(valueLabel.text.indexOf("48") >= 0)
        compare(dialog.canAccept, true)
    }

    function test_alignmentGridMapsToQtFlags() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)

        const expected = [
            Qt.AlignLeft | Qt.AlignTop,
            Qt.AlignHCenter | Qt.AlignTop,
            Qt.AlignRight | Qt.AlignTop,
            Qt.AlignLeft | Qt.AlignVCenter,
            Qt.AlignHCenter | Qt.AlignVCenter,
            Qt.AlignRight | Qt.AlignVCenter,
            Qt.AlignLeft | Qt.AlignBottom,
            Qt.AlignHCenter | Qt.AlignBottom,
            Qt.AlignRight | Qt.AlignBottom
        ]

        for (let i = 0; i < 9; ++i) {
            compare(dialog.alignmentForIndex(i), expected[i])
            compare(dialog.indexForAlignment(expected[i]), i)

            const cell = child(dialog, "text-align-" + i)
            verify(cell !== null)
            mouseClick(cell)
            compare(dialog.alignment, expected[i])
            compare(dialog.alignmentIndex, i)
        }

        compare(dialog.alignment, Qt.AlignRight | Qt.AlignBottom)

        let selectedCount = 0
        for (let i = 0; i < 9; ++i) {
            if (child(dialog, "text-align-" + i).selected)
                ++selectedCount
        }
        compare(selectedCount, 1)
    }

    function test_anchorOutsideImageDisablesAcceptAndSetAnchorClamps() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500,
                                    anchorX: 2000, anchorY: -40 })
        dialog.text = "Hello"
        compare(dialog.anchorValid, false)
        compare(dialog.canAccept, false)

        openDialog(dialog)

        const spy = createTemporaryObject(spyComponent, testCase,
                                          { target: dialog, signalName: "textRequested" })
        compare(dialog.requestCreate(), false)
        compare(spy.count, 0)
        compare(child(dialog, "text-dialog-error").visible, true)

        dialog.setAnchor(1400, -30)
        compare(dialog.anchorX, 1000)
        compare(dialog.anchorY, 0)
        compare(dialog.anchorValid, true)
        compare(dialog.canAccept, true)

        dialog.setAnchor(100, 250)
        compare(dialog.anchorX, 100)
        compare(dialog.anchorY, 250)
    }

    function test_colorSwatches() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)

        verify(Qt.colorEqual(dialog.textColor, dialog.whiteColor))
        const white = child(dialog, "text-color-white")
        const black = child(dialog, "text-color-black")
        const warm = child(dialog, "text-color-warm-grey")
        verify(white !== null && black !== null && warm !== null)
        compare(white.selected, true)

        mouseClick(black)
        verify(Qt.colorEqual(dialog.textColor, "#000000"))
        compare(black.selected, true)
        compare(white.selected, false)

        mouseClick(warm)
        verify(Qt.colorEqual(dialog.textColor, dialog.warmGreyColor))
        compare(warm.selected, true)
        compare(black.selected, false)

        mouseClick(child(dialog, "text-color-red"))
        verify(Qt.colorEqual(dialog.textColor, dialog.redColor))
    }

    function test_signalPayload() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500,
                                    anchorX: 120, anchorY: 240 })
        openDialog(dialog)

        const spy = createTemporaryObject(spyComponent, testCase,
                                          { target: dialog, signalName: "textRequested" })
        const rejected = createTemporaryObject(spyComponent, testCase,
                                               { target: dialog, signalName: "rejected" })
        verify(spy !== null && rejected !== null)

        dialog.text = "  Hello world  "
        dialog.fontSize = 64
        mouseClick(child(dialog, "text-color-black"))
        mouseClick(child(dialog, "text-align-8"))

        compare(dialog.canAccept, true)
        mouseClick(child(dialog, "text-dialog-accept"))

        compare(spy.count, 1)
        const args = spy.signalArguments[0]
        compare(args[0], "Hello world")
        compare(args[1], 120)
        compare(args[2], 240)
        compare(args[3], 64)
        verify(Qt.colorEqual(args[4], "#000000"))
        compare(args[5], Qt.AlignRight | Qt.AlignBottom)
        compare(rejected.count, 0)
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    function test_busyDisablesAccept() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)
        dialog.text = "Busy"

        const accept = child(dialog, "text-dialog-accept")
        const input = child(dialog, "text-dialog-text")
        compare(accept.enabled, true)

        dialog.busy = true
        compare(dialog.canAccept, false)
        compare(accept.enabled, false)
        compare(input.enabled, false)
        compare(child(dialog, "text-dialog-font-size").enabled, false)

        dialog.busy = false
        compare(accept.enabled, true)
    }

    function test_escapeRejects() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)
        const rejected = createTemporaryObject(spyComponent, testCase,
                                               { target: dialog, signalName: "rejected" })
        verify(rejected !== null)

        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !dialog.opened }, 3000)
        compare(rejected.count, 1)
    }

    function test_dialogFitsCompactWindow() {
        const dialog = makeDialog({ imageWidth: 4000, imageHeight: 3000,
                                    anchorX: 2000, anchorY: 1500 })
        openDialog(dialog)
        verify(dialog.width <= testCase.width)
        verify(dialog.height <= testCase.height)
        verify(dialog.width >= Theme.controlMinWidth)
    }
}
