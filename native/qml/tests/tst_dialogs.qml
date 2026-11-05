import QtQuick
import QtTest
import "../dialogs"
import "../UI"

/*!
    Dialog pack contract tests.

    Each dialog is instantiated from its normal QML component; interactions
    use real mouse/key events where practical. Popup content lives under
    contentItem, so `child()` falls back to that subtree.
*/
TestCase {
    id: testCase
    name: "Dialogs"
    when: windowShown
    visible: true
    width: 1100
    height: 900

    Component { id: exportComponent; ExportDialog {} }
    Component { id: resizeComponent; ResizeImageDialog {} }
    Component { id: canvasComponent; CanvasSizeDialog {} }
    Component { id: shortcutsComponent; ShortcutsDialog {} }
    Component { id: numberFieldComponent; NekoNumberField {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
        testCase.width = 1100
        testCase.height = 900
    }

    function make(component, props) {
        return createTemporaryObject(component, testCase, props || {})
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

    // ── Export ──────────────────────────────────────────────────────────────

    function test_exportDefaults() {
        const dialog = make(exportComponent)
        verify(dialog !== null)

        compare(dialog.formatId, "jpeg")
        compare(dialog.formatLabel, "")
        compare(dialog.fileName, "")
        compare(dialog.supportsQuality, true)
        compare(dialog.initialQuality, 90)
        compare(dialog.quality, 90)
        compare(dialog.busy, false)
        fuzzyCompare(dialog.backgroundColor.a, 1, 0.001)

        const accept = child(dialog, "export-accept")
        verify(accept !== null)
        compare(accept.enabled, false)

        dialog.fileName = "photo.jpg"
        compare(accept.enabled, true)

        verify(child(dialog, "export-format-label") !== null)
        verify(child(dialog, "export-metadata-note").text.length > 0)
        verify(child(dialog, "export-background-transparent") !== null)
        verify(child(dialog, "export-file-name") !== null)
        verify(child(dialog, "export-file-name-error") !== null)
        verify(child(dialog, "export-file-name-note").text.length > 0)
    }

    function test_exportFileNameValidation() {
        const dialog = make(exportComponent, {
            fileName: "photo.jpg", formatId: "jpeg", formatSuffix: "jpg"
        })
        openDialog(dialog)
        const accept = child(dialog, "export-accept")
        const input = child(dialog, "export-file-name")
        const error = child(dialog, "export-file-name-error")

        compare(input.text, "photo.jpg")
        compare(dialog.fileNameValid, true)
        compare(error.visible, false)
        compare(accept.enabled, true)

        // A mismatched extension is rejected before saving.
        dialog.fileName = "photo.png"
        compare(dialog.fileNameValid, false)
        compare(error.visible, true)
        compare(error.text.length > 0, true)
        compare(accept.enabled, false)

        // Extensions are case-insensitive and may be omitted entirely.
        dialog.fileName = "photo.JPG"
        compare(dialog.fileNameValid, true)
        dialog.fileName = "vacation"
        compare(dialog.fileNameValid, true)
        compare(error.visible, false)

        // Path separators would escape the Save As folder.
        dialog.fileName = "sub/photo.jpg"
        compare(dialog.fileNameValid, false)
        verify(error.text.indexOf("Save As") >= 0)
        dialog.fileName = "photo.jpg"
        dialog.fileName = ".."
        compare(dialog.fileNameValid, false)

        dialog.fileName = "   "
        compare(dialog.fileNameValid, false)
        compare(dialog.trimmedFileName, "")
        compare(accept.enabled, false)
    }

    function test_exportQualityClampsAndReports() {
        const dialog = make(exportComponent, { fileName: "clamp.jpg" })
        openDialog(dialog)

        dialog.quality = 250
        compare(dialog.quality, 100)
        compare(dialog.contentItem ? child(dialog, "export-quality-value").text : "", "100%")

        dialog.quality = -12
        compare(dialog.quality, 0)
        compare(child(dialog, "export-quality-value").text, "0%")

        dialog.quality = 37
        compare(dialog.quality, 37)
        const slider = child(dialog, "export-quality")
        verify(slider !== null)
        compare(slider.value, 37)
        compare(child(dialog, "export-quality-value").text, "37%")
    }

    function test_exportBackgroundStaysOpaque() {
        const dialog = make(exportComponent, {
            fileName: "opaque.jpg",
            initialBackground: Qt.rgba(0.2, 0.4, 0.6, 0.2)
        })
        openDialog(dialog)
        fuzzyCompare(dialog.backgroundColor.a, 1, 0.001)
        fuzzyCompare(dialog.backgroundColor.r, 0.2, 0.001)
        fuzzyCompare(dialog.backgroundColor.g, 0.4, 0.001)
        fuzzyCompare(dialog.backgroundColor.b, 0.6, 0.001)

        dialog.backgroundColor = Qt.rgba(1, 0.2, 0.1, 0)
        fuzzyCompare(dialog.backgroundColor.a, 1, 0.001)
    }

    function test_exportAcceptPayload() {
        const dialog = make(exportComponent, {
            fileName: "out.jpg",
            formatId: "jpeg",
            initialQuality: 82,
            initialBackground: "#000000"
        })
        openDialog(dialog)

        const spy = make(spyComponent, { target: dialog, signalName: "exportRequested" })
        const accept = child(dialog, "export-accept")
        verify(accept.enabled)

        mouseClick(accept)
        compare(spy.count, 1)
        const args = spy.signalArguments[0]
        compare(args[0], "jpeg")
        compare(args[1], 82)
        fuzzyCompare(args[2].a, 1, 0.001)
        fuzzyCompare(args[2].r, 0, 0.001)
        fuzzyCompare(args[2].g, 0, 0.001)
        fuzzyCompare(args[2].b, 0, 0.001)
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    function test_exportBusyDisablesAccept() {
        const dialog = make(exportComponent, { fileName: "busy.jpg" })
        openDialog(dialog)
        const accept = child(dialog, "export-accept")
        verify(accept.enabled)

        dialog.busy = true
        compare(accept.enabled, false)
        compare(child(dialog, "export-file-name").enabled, false)

        dialog.busy = false
        compare(accept.enabled, true)
    }

    function test_exportEscapeRejects() {
        const dialog = make(exportComponent, { fileName: "escape.jpg" })
        openDialog(dialog)
        const rejected = make(spyComponent, { target: dialog, signalName: "rejected" })

        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !dialog.opened }, 3000)
        compare(rejected.count, 1)
    }

    // ── Resize ──────────────────────────────────────────────────────────────

    function test_resizeDefaultsAndAspectLock() {
        const dialog = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        verify(dialog !== null)
        compare(dialog.lockAspect, true)

        const width = child(dialog, "resize-width")
        const height = child(dialog, "resize-height")
        verify(width !== null)
        verify(height !== null)
        compare(width.text, "4000")
        compare(height.text, "3000")
        compare(child(dialog, "resize-accept").enabled, true)

        const original = child(dialog, "resize-original")
        verify(original.text.indexOf("4000") >= 0)
        verify(original.text.indexOf("3000") >= 0)

        width.text = "2000"
        compare(width.text, "2000")
        compare(height.text, "1500")

        height.text = "600"
        compare(height.text, "600")
        compare(width.text, "800")
    }

    function test_resizeAspectLockOffKeepsOtherField() {
        const dialog = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        const lock = child(dialog, "resize-lock")
        const width = child(dialog, "resize-width")
        const height = child(dialog, "resize-height")

        lock.checked = false
        width.text = "2000"
        compare(height.text, "3000")
        height.text = "1000"
        compare(width.text, "2000")
    }

    function test_resizeValidation() {
        const dialog = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(dialog)
        const width = child(dialog, "resize-width")
        const height = child(dialog, "resize-height")
        const accept = child(dialog, "resize-accept")
        const error = child(dialog, "resize-error")

        width.text = "0"
        compare(accept.enabled, false)
        verify(error.visible)

        width.text = "40000"
        compare(accept.enabled, false)

        const lock = child(dialog, "resize-lock")
        lock.checked = false
        width.text = "20000"
        height.text = "20000"
        compare(width.text, "20000")
        compare(height.text, "20000")
        compare(accept.enabled, false)
        verify(error.visible)
        verify(error.text.length > 0)

        width.text = "1000"
        height.text = "1000"
        compare(accept.enabled, true)
    }

    function test_resizeSignalPayload() {
        const dialog = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(dialog)
        const width = child(dialog, "resize-width")
        width.text = "2000"
        compare(child(dialog, "resize-height").text, "1500")

        const spy = make(spyComponent, { target: dialog, signalName: "resizeRequested" })
        mouseClick(child(dialog, "resize-accept"))
        compare(spy.count, 1)
        const args = spy.signalArguments[0]
        compare(args[0], 2000)
        compare(args[1], 1500)
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    // ── Canvas size ─────────────────────────────────────────────────────────

    function test_canvasDefaultsAndAnchorMapping() {
        const dialog = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        verify(dialog !== null)
        compare(child(dialog, "canvas-width").text, "4000")
        compare(child(dialog, "canvas-height").text, "3000")
        compare(dialog.anchor, Qt.AlignHCenter | Qt.AlignVCenter)
        fuzzyCompare(dialog.backgroundColor.a, 0, 0.001)
        compare(child(dialog, "canvas-accept").enabled, true)

        openDialog(dialog)

        const topLeft = child(dialog, "canvas-anchor-top-left")
        verify(topLeft !== null)
        mouseClick(topLeft)
        compare(dialog.anchor, Qt.AlignLeft | Qt.AlignTop)

        const bottomRight = child(dialog, "canvas-anchor-bottom-right")
        mouseClick(bottomRight)
        compare(dialog.anchor, Qt.AlignRight | Qt.AlignBottom)

        const topCenter = child(dialog, "canvas-anchor-top")
        mouseClick(topCenter)
        compare(dialog.anchor, Qt.AlignHCenter | Qt.AlignTop)

        const ids = ["top-left", "top", "top-right", "left", "center", "right",
                     "bottom-left", "bottom", "bottom-right"]
        let selected = 0
        for (let i = 0; i < ids.length; ++i) {
            const button = child(dialog, "canvas-anchor-" + ids[i])
            verify(button !== null)
            if (button.variant === "primary")
                ++selected
        }
        compare(selected, 1)
    }

    function test_canvasBackgroundsAndValidation() {
        const dialog = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(dialog)
        const accept = child(dialog, "canvas-accept")

        mouseClick(child(dialog, "canvas-background-white"))
        fuzzyCompare(dialog.backgroundColor.a, 1, 0.001)
        fuzzyCompare(dialog.backgroundColor.r, 1, 0.001)

        mouseClick(child(dialog, "canvas-background-transparent"))
        fuzzyCompare(dialog.backgroundColor.a, 0, 0.001)
        compare(accept.enabled, true)

        const width = child(dialog, "canvas-width")
        const height = child(dialog, "canvas-height")
        width.text = "0"
        compare(accept.enabled, false)
        width.text = "40000"
        compare(accept.enabled, false)
        width.text = "20000"
        height.text = "20000"
        compare(accept.enabled, false)
        verify(child(dialog, "canvas-error").visible)

        width.text = "1000"
        height.text = "800"
        compare(accept.enabled, true)
    }

    function test_canvasSignalPayload() {
        const dialog = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(dialog)

        mouseClick(child(dialog, "canvas-anchor-bottom-right"))
        mouseClick(child(dialog, "canvas-background-transparent"))
        child(dialog, "canvas-width").text = "1200"
        child(dialog, "canvas-height").text = "900"

        const spy = make(spyComponent, { target: dialog, signalName: "canvasResizeRequested" })
        mouseClick(child(dialog, "canvas-accept"))
        compare(spy.count, 1)
        const args = spy.signalArguments[0]
        compare(args[0], 1200)
        compare(args[1], 900)
        compare(args[2], Qt.AlignRight | Qt.AlignBottom)
        fuzzyCompare(args[3].a, 0, 0.001)
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    // ── Compact-window fit and scrolling ────────────────────────────────────

    function test_resizeAndCanvasFitCompactWindow() {
        testCase.width = 860
        testCase.height = 600

        const resize = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(resize)
        const resizeScroller = child(resize, "resize-scroll")
        verify(resizeScroller !== null)
        verify(resize.height <= testCase.height - Theme.spacing2xl)
        verify(resize.y >= 0)
        const resizeAccept = child(resize, "resize-accept")
        const resizeAcceptPos = resizeAccept.mapToItem(resize.contentItem, 0, 0)
        verify(resizeAcceptPos.y + resizeAccept.height <= resize.height + 0.5,
               "resize footer must stay inside the dialog")
        compare(resizeScroller.contentWidth, resizeScroller.width)
        verify(resizeScroller.contentHeight <= resizeScroller.height + 0.5
               || resizeScroller.height > 0)
        resize.close()
        tryVerify(function() { return !resize.opened }, 3000)

        const canvas = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(canvas)
        const canvasScroller = child(canvas, "canvas-scroll")
        verify(canvasScroller !== null)
        verify(canvas.height <= testCase.height - Theme.spacing2xl)
        const canvasAccept = child(canvas, "canvas-accept")
        const canvasAcceptPos = canvasAccept.mapToItem(canvas.contentItem, 0, 0)
        verify(canvasAcceptPos.y + canvasAccept.height <= canvas.height + 0.5,
               "canvas footer must stay inside the dialog")
        verify(canvasScroller.contentHeight > canvasScroller.height,
               "canvas options should scroll at 860×600")

        // The anchor grid is reachable by scrolling, and clickable afterwards.
        const anchor = child(canvas, "canvas-anchor-bottom-right")
        const anchorPos = anchor.mapToItem(canvasScroller.contentItem, 0, 0)
        canvasScroller.contentY = Math.max(0, Math.min(
            canvasScroller.contentHeight - canvasScroller.height,
            anchorPos.y - canvasScroller.height + anchor.height + Theme.spacingMd))
        waitForRendering(canvasScroller)
        mouseClick(anchor)
        compare(canvas.anchor, Qt.AlignRight | Qt.AlignBottom)

        // Footer stays put while the body scrolls.
        const before = canvasAccept.mapToItem(canvas.contentItem, 0, 0).y
        canvasScroller.contentY = 0
        waitForRendering(canvasScroller)
        const after = canvasAccept.mapToItem(canvas.contentItem, 0, 0).y
        fuzzyCompare(before, after, 0.5)
        canvas.close()
    }

    function test_dialogsFitAt900x700() {
        testCase.width = 900
        testCase.height = 700

        const resize = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(resize)
        verify(resize.height <= testCase.height - Theme.spacing2xl)
        resize.close()

        const canvas = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(canvas)
        verify(canvas.height <= testCase.height - Theme.spacing2xl)
        canvas.close()
    }

    // ── Shortcuts ───────────────────────────────────────────────────────────

    function test_shortcutsAreGroupedAndAccurate() {
        const dialog = make(shortcutsComponent)
        verify(dialog !== null)
        compare(dialog.groups.length, 5)
        verify(dialog.entries.length > 0)

        for (let i = 0; i < dialog.groups.length; ++i)
            verify(dialog.groups[i].entries.length > 0)

        const shortcutSet = {}
        for (let i = 0; i < dialog.entries.length; ++i) {
            const entry = dialog.entries[i]
            verify(entry.action.length > 0)
            verify(entry.shortcut.length > 0)
            verify(shortcutSet[entry.shortcut] === undefined,
                   "duplicate shortcut: " + entry.shortcut)
            shortcutSet[entry.shortcut] = true
        }

        const required = ["Ctrl+O", "Ctrl+S", "Ctrl+Shift+S", "Ctrl+Z", "Ctrl+Shift+Z",
                          "Ctrl+Shift+C", "Ctrl+0", "Ctrl+1", "C", "Enter", "Esc"]
        for (let i = 0; i < required.length; ++i)
            verify(shortcutSet[required[i]] === true, "missing shortcut " + required[i])
    }

    function test_shortcutsDialogCloses() {
        const dialog = make(shortcutsComponent)
        openDialog(dialog)
        mouseClick(child(dialog, "shortcuts-close"))
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    // ── Shared number field ─────────────────────────────────────────────────

    function test_numberFieldValidationAndStepping() {
        const field = make(numberFieldComponent, {
            objectName: "number-field",
            minimum: 1,
            maximum: 32768,
            text: "100"
        })
        verify(field !== null)
        compare(field.valid, true)
        compare(field.numericValue, 100)

        field.text = "abc"
        compare(field.valid, false)
        field.text = "0"
        compare(field.valid, false)
        field.text = "40000"
        compare(field.valid, false)

        field.text = "100"
        const input = findChild(field, "number-field-input")
        verify(input !== null)
        input.forceActiveFocus()
        keyClick(Qt.Key_Up)
        compare(field.text, "101")
        keyClick(Qt.Key_Down)
        compare(field.text, "100")
    }

    // ── Stability ───────────────────────────────────────────────────────────

    function test_noBindingLoopWarnings() {
        failOnWarning(/binding loop/i)

        const exportDialog = make(exportComponent, { fileName: "loop.jpg" })
        openDialog(exportDialog)
        exportDialog.quality = 10
        exportDialog.quality = 90
        exportDialog.backgroundColor = "#8b8780"
        exportDialog.busy = true
        exportDialog.busy = false
        exportDialog.close()
        tryVerify(function() { return !exportDialog.opened }, 3000)

        const resizeDialog = make(resizeComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(resizeDialog)
        child(resizeDialog, "resize-width").text = "1234"
        child(resizeDialog, "resize-height").text = "567"
        child(resizeDialog, "resize-lock").checked = false
        child(resizeDialog, "resize-width").text = "2000"
        resizeDialog.close()
        tryVerify(function() { return !resizeDialog.opened }, 3000)

        const canvasDialog = make(canvasComponent, { imageWidth: 4000, imageHeight: 3000 })
        openDialog(canvasDialog)
        child(canvasDialog, "canvas-width").text = "5000"
        child(canvasDialog, "canvas-height").text = "4000"
        mouseClick(child(canvasDialog, "canvas-background-white"))
        mouseClick(child(canvasDialog, "canvas-anchor-bottom-right"))
        canvasDialog.close()
        tryVerify(function() { return !canvasDialog.opened }, 3000)

        const shortcutsDialog = make(shortcutsComponent)
        openDialog(shortcutsDialog)
        shortcutsDialog.close()
        tryVerify(function() { return !shortcutsDialog.opened }, 3000)
    }
}
