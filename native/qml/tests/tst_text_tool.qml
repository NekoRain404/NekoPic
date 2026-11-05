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
        testCase.width = 900
        testCase.height = 700

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

    /*! Brings a scrollable body control into view before clicking it. */
    function clickInDialog(dialog, item) {
        const scroller = child(dialog, "text-dialog-scroll")
        if (scroller && item) {
            const pos = item.mapToItem(scroller.contentItem, 0, 0)
            const maxY = Math.max(0, scroller.contentHeight - scroller.height)
            const target = pos.y - (scroller.height - item.height) / 2
            scroller.contentY = Math.max(0, Math.min(maxY, target))
            waitForRendering(scroller)
        }
        mouseClick(item)
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
            clickInDialog(dialog, cell)
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

        clickInDialog(dialog, black)
        verify(Qt.colorEqual(dialog.textColor, "#000000"))
        compare(black.selected, true)
        compare(white.selected, false)

        clickInDialog(dialog, warm)
        verify(Qt.colorEqual(dialog.textColor, dialog.warmGreyColor))
        compare(warm.selected, true)
        compare(black.selected, false)

        clickInDialog(dialog, child(dialog, "text-color-red"))
        verify(Qt.colorEqual(dialog.textColor, dialog.redColor))
    }

    // ── Styled text controls ───────────────────────────────────────────────

    function test_styledControlsExistAndDefaults() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)

        compare(dialog.fontFamily, "")
        compare(dialog.bold, false)
        compare(dialog.outlineEnabled, false)
        compare(dialog.outlineWidth, 2)
        compare(dialog.effectiveOutlineWidth, 0)
        compare(dialog.lineHeight, 1.0)
        compare(dialog.textPadding, 4)
        compare(dialog.fontWeight, 400)

        const familyBox = child(dialog, "text-dialog-font-family")
        verify(familyBox !== null)
        compare(familyBox.count, dialog.fontFamilyModel.length)
        compare(dialog.fontFamilyModel.length, dialog.fontFamilies.length + 1)
        compare(dialog.fontFamilyAt(0), "")

        verify(child(dialog, "text-dialog-font-fallback-note") !== null)
        verify(child(dialog, "text-dialog-bold") !== null)
        verify(child(dialog, "text-dialog-outline") !== null)
        verify(child(dialog, "text-dialog-outline-color-red") !== null)

        const lineHeight = child(dialog, "text-dialog-line-height")
        verify(lineHeight !== null)
        compare(lineHeight.from, 0.8)
        compare(lineHeight.to, 2.5)
        compare(lineHeight.value, 1.0)

        const padding = child(dialog, "text-dialog-padding")
        verify(padding !== null)
        compare(padding.from, 0)
        compare(padding.to, 64)
        compare(padding.value, 4)

        const outlineWidth = child(dialog, "text-dialog-outline-width")
        verify(outlineWidth !== null)
        compare(outlineWidth.from, 0)
        compare(outlineWidth.to, 64)
        compare(outlineWidth.enabled, false)

        clickInDialog(dialog, child(dialog, "text-dialog-outline"))
        compare(dialog.outlineEnabled, true)
        compare(outlineWidth.enabled, true)
        compare(dialog.effectiveOutlineWidth, 2)

        clickInDialog(dialog, child(dialog, "text-dialog-bold"))
        compare(dialog.bold, true)
        compare(dialog.fontWeight, 700)
    }

    function test_styledControlsClamp() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)

        dialog.lineHeight = 5
        compare(dialog.lineHeight, 2.5)
        dialog.lineHeight = 0.1
        compare(dialog.lineHeight, 0.8)
        dialog.lineHeight = 1.25
        compare(dialog.lineHeight, 1.25)
        compare(child(dialog, "text-dialog-line-height").value, 1.25)

        dialog.textPadding = -8
        compare(dialog.textPadding, 0)
        dialog.textPadding = 200
        compare(dialog.textPadding, 64)
        dialog.textPadding = 18
        compare(dialog.textPadding, 18)
        compare(child(dialog, "text-dialog-padding").value, 18)

        dialog.outlineWidth = 100
        compare(dialog.outlineWidth, 64)
        dialog.outlineWidth = -4
        compare(dialog.outlineWidth, 0)
        dialog.outlineWidth = 6
        compare(dialog.outlineWidth, 6)
        compare(child(dialog, "text-dialog-outline-width").value, 6)
    }

    function test_styledSignalPayload() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500,
                                    anchorX: 120, anchorY: 240 })
        openDialog(dialog)

        const styled = createTemporaryObject(spyComponent, testCase,
                                             { target: dialog, signalName: "styledTextRequested" })
        const legacy = createTemporaryObject(spyComponent, testCase,
                                             { target: dialog, signalName: "textRequested" })
        verify(styled !== null && legacy !== null)

        dialog.text = "  Styled world  "
        dialog.fontSize = 64
        dialog.bold = true
        if (dialog.fontFamilies.length > 0)
            dialog.fontFamily = dialog.fontFamilies[0]
        dialog.lineHeight = 1.6
        dialog.textPadding = 12
        clickInDialog(dialog, child(dialog, "text-dialog-outline"))
        dialog.outlineWidth = 6
        clickInDialog(dialog, child(dialog, "text-dialog-outline-color-red"))
        clickInDialog(dialog, child(dialog, "text-color-black"))
        clickInDialog(dialog, child(dialog, "text-align-8"))

        compare(dialog.canAccept, true)
        mouseClick(child(dialog, "text-dialog-accept"))

        compare(styled.count, 1)
        const args = styled.signalArguments[0]
        compare(args[0], "Styled world")
        compare(args[1], 120)
        compare(args[2], 240)
        if (dialog.fontFamilies.length > 0)
            compare(args[3], dialog.fontFamilies[0])
        else
            compare(args[3], "")
        compare(args[4], 700)
        compare(args[5], 64)
        verify(Qt.colorEqual(args[6], "#000000"))
        compare(args[7], Qt.AlignRight | Qt.AlignBottom)
        verify(Qt.colorEqual(args[8], dialog.redColor))
        compare(args[9], 6)
        verify(Math.abs(args[10] - 1.6) < 0.001)
        compare(args[11], 12)

        // The legacy signal still fires for the six-argument controller path.
        compare(legacy.count, 1)
        compare(legacy.signalArguments[0][0], "Styled world")
        compare(legacy.signalArguments[0][3], 64)
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
        clickInDialog(dialog, child(dialog, "text-color-black"))
        clickInDialog(dialog, child(dialog, "text-align-8"))

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
        compare(child(dialog, "text-dialog-font-family").enabled, false)
        compare(child(dialog, "text-dialog-line-height").enabled, false)
        compare(child(dialog, "text-dialog-padding").enabled, false)
        compare(child(dialog, "text-dialog-outline").enabled, false)
        compare(child(dialog, "text-dialog-bold").enabled, false)

        dialog.busy = false
        compare(accept.enabled, true)
    }

    // ── Edit mode ───────────────────────────────────────────────────────────

    function test_editModeDefaultsAndCreateContractUnchanged() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        compare(dialog.editMode, false)
        compare(dialog.editId, 0)
        compare(dialog.editIdValid, true)
        compare(child(dialog, "text-dialog-accept").text, "Add text")
    }

    function test_loadTextInfoFillsFieldsAndEnablesEditMode() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)

        const family = dialog.fontFamilies.length > 0 ? dialog.fontFamilies[0] : ""
        const loaded = dialog.loadTextInfo({
            id: 42,
            text: "Existing",
            x: 210,
            y: 140,
            fontFamily: family,
            fontWeight: 700,
            fontSize: 44,
            color: "#c0504d",
            alignment: Qt.AlignRight | Qt.AlignBottom,
            outlineColor: "#4a6fa5",
            outlineWidth: 5,
            lineHeight: 1.5,
            padding: 12
        })

        verify(loaded)
        compare(dialog.editMode, true)
        compare(dialog.editId, 42)
        compare(dialog.editIdValid, true)
        compare(dialog.text, "Existing")
        compare(dialog.anchorX, 210)
        compare(dialog.anchorY, 140)
        compare(dialog.fontFamily, family)
        compare(dialog.bold, true)
        compare(dialog.fontWeight, 700)
        compare(dialog.fontSize, 44)
        verify(Qt.colorEqual(dialog.textColor, "#c0504d"))
        compare(dialog.alignment, Qt.AlignRight | Qt.AlignBottom)
        compare(dialog.outlineEnabled, true)
        compare(dialog.outlineWidth, 5)
        verify(Qt.colorEqual(dialog.outlineColor, "#4a6fa5"))
        compare(dialog.lineHeight, 1.5)
        compare(dialog.textPadding, 12)
        compare(dialog.canAccept, true)
        compare(child(dialog, "text-dialog-accept").text, "Save")

        // Malformed payloads are ignored.
        compare(dialog.loadTextInfo(null), false)
        compare(dialog.loadTextInfo({}), false)
        compare(dialog.loadTextInfo({ text: "no anchors" }), false)
        compare(dialog.editId, 42)
    }

    function test_editModeAcceptEmitsUpdatePayloadOnly() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)
        const family = dialog.fontFamilies.length > 0 ? dialog.fontFamilies[0] : ""
        dialog.loadTextInfo({
            id: 77, text: "Before", x: 210, y: 140,
            fontFamily: family, fontWeight: 400, fontSize: 36,
            color: "#ffffff", alignment: Qt.AlignCenter,
            outlineColor: "#000000", outlineWidth: 0,
            lineHeight: 1.0, padding: 4
        })

        const updates = createTemporaryObject(spyComponent, testCase,
                                              { target: dialog, signalName: "textUpdateRequested" })
        const styled = createTemporaryObject(spyComponent, testCase,
                                             { target: dialog, signalName: "styledTextRequested" })
        const legacy = createTemporaryObject(spyComponent, testCase,
                                             { target: dialog, signalName: "textRequested" })
        verify(updates !== null && styled !== null && legacy !== null)

        dialog.text = "  Changed  "
        dialog.fontSize = 50
        dialog.bold = true
        clickInDialog(dialog, child(dialog, "text-color-black"))
        clickInDialog(dialog, child(dialog, "text-align-8"))
        clickInDialog(dialog, child(dialog, "text-dialog-outline"))
        dialog.outlineWidth = 6
        clickInDialog(dialog, child(dialog, "text-dialog-outline-color-red"))
        compare(dialog.canAccept, true)

        mouseClick(child(dialog, "text-dialog-accept"))

        compare(updates.count, 1)
        const info = updates.signalArguments[0][0]
        compare(info.id, 77)
        compare(info.text, "Changed")
        compare(info.x, 210)
        compare(info.y, 140)
        compare(info.fontFamily, family)
        compare(info.fontWeight, 700)
        compare(info.fontSize, 50)
        verify(Qt.colorEqual(info.color, "#000000"))
        compare(info.alignment, Qt.AlignRight | Qt.AlignBottom)
        verify(Qt.colorEqual(info.outlineColor, dialog.redColor))
        compare(info.outlineWidth, 6)
        verify(Math.abs(info.lineHeight - 1.0) < 0.001)
        compare(info.padding, 4)

        // Edit mode never emits the create signals.
        compare(styled.count, 0)
        compare(legacy.count, 0)
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    function test_editModeDisabledStates() {
        const dialog = makeDialog({ imageWidth: 1000, imageHeight: 500 })
        openDialog(dialog)
        const accept = child(dialog, "text-dialog-accept")

        // Edit mode without an id cannot be accepted.
        dialog.editMode = true
        dialog.text = "Needs an id"
        compare(dialog.editIdValid, false)
        compare(dialog.canAccept, false)
        compare(accept.enabled, false)
        compare(dialog.requestCreate(), false)
        compare(child(dialog, "text-dialog-error").visible, true)

        dialog.loadTextInfo({
            id: 5, text: "Editable", x: 20, y: 30,
            fontFamily: "", fontWeight: 400, fontSize: 32,
            color: "#ffffff", alignment: Qt.AlignCenter,
            outlineColor: "#000000", outlineWidth: 0,
            lineHeight: 1.0, padding: 4
        })
        compare(dialog.editIdValid, true)
        compare(dialog.canAccept, true)
        compare(accept.enabled, true)

        // Busy disables every control, like create mode.
        dialog.busy = true
        compare(dialog.canAccept, false)
        compare(accept.enabled, false)
        compare(child(dialog, "text-dialog-text").enabled, false)
        compare(child(dialog, "text-dialog-font-size").enabled, false)
        compare(accept.text, "Saving…")

        dialog.busy = false
        compare(accept.enabled, true)
        compare(accept.text, "Save")
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

        // The densest styling state (outline, bold, maximum spacing) still fits.
        dialog.text = "Styled"
        clickInDialog(dialog, child(dialog, "text-dialog-outline"))
        clickInDialog(dialog, child(dialog, "text-dialog-bold"))
        dialog.lineHeight = 2.5
        dialog.textPadding = 64
        verify(dialog.height <= testCase.height)
        compare(dialog.canAccept, true)
        compare(dialog.height, dialog.implicitHeight)
    }

    function test_dialogFits860x600AndScrolls() {
        testCase.width = 860
        testCase.height = 600

        const dialog = makeDialog({ imageWidth: 4000, imageHeight: 3000,
                                    anchorX: 2000, anchorY: 1500 })
        openDialog(dialog)

        verify(dialog.height <= testCase.height - Theme.spacing2xl)
        verify(dialog.y >= 0)
        verify(dialog.width <= testCase.width)

        const scroller = child(dialog, "text-dialog-scroll")
        verify(scroller !== null)
        verify(scroller.contentHeight > scroller.height,
               "text styles should scroll at 860×600")
        compare(scroller.contentWidth, scroller.width)

        // The error line and the action row are outside the scroller.
        dialog.text = ""
        compare(dialog.requestCreate(), false)
        waitForRendering(scroller)
        const error = child(dialog, "text-dialog-error")
        const accept = child(dialog, "text-dialog-accept")
        const errorBefore = error.mapToItem(dialog.contentItem, 0, 0).y
        const acceptBefore = accept.mapToItem(dialog.contentItem, 0, 0).y
        verify(error.visible)

        scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
        waitForRendering(scroller)
        fuzzyCompare(error.mapToItem(dialog.contentItem, 0, 0).y, errorBefore, 0.5)
        fuzzyCompare(accept.mapToItem(dialog.contentItem, 0, 0).y, acceptBefore, 0.5)
        verify(acceptBefore + accept.height <= dialog.height + 0.5,
               "fixed footer must stay inside the dialog")

        // Controls near the bottom are reachable and usable once scrolled.
        clickInDialog(dialog, child(dialog, "text-align-8"))
        compare(dialog.alignment, Qt.AlignRight | Qt.AlignBottom)
        dialog.close()
    }
}
