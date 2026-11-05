import QtQuick
import QtTest
import "../panels"
import "../UI"

/*!
    TextPanel contract tests.

    The panel is a pure view: every user edit must surface through
    textEdited/styleEdited/resetRequested, while external property updates
    must not echo back. These tests also pin the H5 defaults and the
    860×600-friendly scrolling layout.
*/
TestCase {
    id: testCase
    name: "TextPanel"
    when: windowShown
    visible: true
    width: 860
    height: 600

    Component { id: panelComponent; TextPanel {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
    }

    function make(props) {
        const merged = { width: 292, height: 600 }
        const extra = props || {}
        for (const key in extra)
            merged[key] = extra[key]
        const panel = createTemporaryObject(panelComponent, testCase, merged)
        verify(panel !== null)
        return panel
    }

    function test_defaultsMatchH5() {
        const panel = make()
        compare(panel.text, "")
        compare(panel.fontFamily, "Noto Sans CJK SC")
        compare(panel.fontSize, 48)
        compare(panel.alignment, Qt.AlignLeft)
        compare(panel.outline, true)
        compare(panel.editMode, false)
        compare(panel.controlsEnabled, true)

        const text = findChild(panel, "text-panel-text")
        const font = findChild(panel, "text-panel-font")
        const size = findChild(panel, "text-panel-size")
        const align = findChild(panel, "text-panel-alignment")
        const outline = findChild(panel, "text-panel-outline")
        verify(text !== null)
        verify(font !== null)
        verify(size !== null)
        verify(align !== null)
        verify(outline !== null)

        compare(size.from, 12)
        compare(size.to, 160)
        compare(size.value, 48)
        compare(outline.checked, true)
        verify(findChild(panel, "text-panel-font-note").text.toLowerCase().indexOf("cjk") >= 0)
        verify(findChild(panel, "text-panel-scroll") !== null)
    }

    function test_textEditingSignalsAndExternalSync() {
        const panel = make()
        const edited = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "textEdited" })
        const editor = findChild(panel, "text-panel-text")

        editor.text = "Hello Neko"
        compare(edited.count, 1)
        compare(edited.signalArguments[0][0], "Hello Neko")
        compare(panel.text, "Hello Neko")

        // An external update must render without reporting a user edit.
        panel.text = "From the document"
        compare(editor.text, "From the document")
        compare(edited.count, 1)

        // Newlines survive the round trip.
        editor.text = "line one\nline two"
        compare(edited.count, 2)
        compare(panel.text, "line one\nline two")
    }

    function test_fontSelectionIsCjkFirstAndReports() {
        const panel = make()
        const styles = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "styleEdited" })
        const font = findChild(panel, "text-panel-font")

        verify(panel.fontModel.length >= 5)
        compare(panel.fontModel[0].value, "")
        compare(panel.fontModel[1].value, "Noto Sans CJK SC")
        verify(panel.fontModel[2].label.indexOf("Serif CJK") >= 0)

        font.currentIndex = 2
        font.activated(2)
        compare(panel.fontFamily, "Noto Serif CJK SC")
        compare(styles.count, 1)
        compare(styles.signalArguments[0][0], "font")
        compare(styles.signalArguments[0][1], "Noto Serif CJK SC")

        // An unknown document family is appended so the combo can show it.
        panel.fontFamily = "Some Installed Family"
        compare(panel.fontModel[panel.fontModel.length - 1].value, "Some Installed Family")
        tryCompare(font, "currentIndex", panel.fontModel.length - 1)
    }

    function test_sizeSliderRangeAndClamping() {
        const panel = make()
        const styles = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "styleEdited" })
        const slider = findChild(panel, "text-panel-size")
        const value = findChild(panel, "text-panel-size-value")

        slider.preview(96)
        compare(panel.fontSize, 96)
        compare(value.text, "96 px")
        compare(styles.count, 1)
        compare(styles.signalArguments[0][0], "size")
        compare(styles.signalArguments[0][1], 96)

        // The public property clamps to the documented 12–160 range.
        panel.fontSize = 500
        compare(panel.fontSize, 160)
        panel.fontSize = 1
        compare(panel.fontSize, 12)

        panel.fontSize = 64
        compare(slider.value, 64)
    }

    function test_alignmentSegmentsReportFlags() {
        const panel = make()
        const styles = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "styleEdited" })
        const align = findChild(panel, "text-panel-alignment")

        align.activated(1)
        compare(panel.alignment, Qt.AlignHCenter)
        compare(styles.signalArguments[0][0], "align")
        compare(styles.signalArguments[0][1], Qt.AlignHCenter)

        align.activated(2)
        compare(panel.alignment, Qt.AlignRight)

        panel.alignment = Qt.AlignLeft
        compare(align.currentIndex, 0)
    }

    function test_outlineAndColourControls() {
        const panel = make()
        const styles = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "styleEdited" })
        const outline = findChild(panel, "text-panel-outline")
        const peach = findChild(panel, "text-panel-color-peach")
        const red = findChild(panel, "text-panel-color-red")
        const hex = findChild(panel, "text-panel-hex")
        verify(peach !== null && red !== null && hex !== null)

        compare(peach.selected, true)
        const scroller = findChild(panel, "text-panel-scroll")
        scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
        waitForRendering(panel)
        mouseClick(red)
        compare(panel.color, "#e46a5d")
        compare(styles.signalArguments[styles.count - 1][0], "color")

        mouseClick(outline)
        compare(panel.outline, false)
        compare(styles.signalArguments[styles.count - 1][0], "outline")
        compare(styles.signalArguments[styles.count - 1][1], false)

        hex.text = "#61a3c7"
        hex.accepted()
        compare(panel.color, "#61a3c7")

        // Invalid values revert to the current colour and do not emit.
        const before = styles.count
        hex.text = "not-a-colour"
        hex.accepted()
        compare(styles.count, before)
        compare(hex.text.toLowerCase(), "#61a3c7")

        // Shorthand hex is normalised.
        hex.text = "#abc"
        hex.accepted()
        compare(panel.color, "#aabbcc")
    }

    function test_busyDisablesEveryControl() {
        const panel = make({ busy: true })
        compare(panel.controlsEnabled, false)
        compare(findChild(panel, "text-panel-text").enabled, false)
        compare(findChild(panel, "text-panel-font").enabled, false)
        compare(findChild(panel, "text-panel-size").enabled, false)
        compare(findChild(panel, "text-panel-alignment").enabled, false)
        compare(findChild(panel, "text-panel-outline").enabled, false)
        compare(findChild(panel, "text-panel-color-peach").enabled, false)
        compare(findChild(panel, "text-panel-hex").enabled, false)
        compare(findChild(panel, "text-panel-reset").enabled, false)

        panel.busy = false
        compare(findChild(panel, "text-panel-size").enabled, true)
        panel.enabled = false
        compare(findChild(panel, "text-panel-size").enabled, false)
    }

    function test_resetRestoresDefaultsAndSignals() {
        const panel = make({
            text: "Caption",
            fontFamily: "DejaVu Sans",
            fontSize: 120,
            alignment: Qt.AlignRight,
            outline: false,
            color: "#e46a5d"
        })
        const resets = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "resetRequested" })
        const reset = findChild(panel, "text-panel-reset")
        verify(reset.visible)

        const scroller = findChild(panel, "text-panel-scroll")
        scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
        waitForRendering(panel)
        mouseClick(reset)
        compare(resets.count, 1)
        compare(panel.text, "")
        compare(panel.fontFamily, panel.defaultFontFamily)
        compare(panel.fontSize, panel.defaultFontSize)
        compare(panel.alignment, Qt.AlignLeft)
        compare(panel.outline, true)
        compare(panel.color, panel.peachColor)
        compare(findChild(panel, "text-panel-text").text, "")
        compare(findChild(panel, "text-panel-outline").checked, true)
    }

    function test_scrollsAtCompactWindowHeight() {
        // The inspector column is roughly 520 px tall at 860×600.
        const panel = make({ width: 292, height: 520 })
        const scroller = findChild(panel, "text-panel-scroll")
        verify(scroller !== null)
        compare(scroller.width, 292 - 2 * Theme.spacing2xl)
        verify(scroller.contentHeight > scroller.height,
               "text panel should scroll at compact height")
        compare(scroller.contentWidth, scroller.width)

        // Every control stays inside the content column.
        const editor = findChild(panel, "text-panel-text")
        const reset = findChild(panel, "text-panel-reset")
        verify(editor.width <= scroller.width)
        verify(reset.width <= scroller.width)

        scroller.contentY = 100
        verify(scroller.contentY > 0)
        scroller.returnToBounds()
        verify(scroller.contentY <= scroller.contentHeight - scroller.height + 1)
    }

    function test_editModeMarksExistingText() {
        const panel = make({ editId: 7, text: "Existing" })
        compare(panel.editMode, true)
        compare(panel.text, "Existing")
        verify(findChild(panel, "text-panel-text").text, "Existing")
    }
}
