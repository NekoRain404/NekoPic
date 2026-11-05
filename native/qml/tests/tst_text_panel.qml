import QtQuick
import QtTest
import "../panels"
import "../panels/FontCatalog.js" as FontCatalog
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
        verify(findChild(panel, "font-picker-button") !== null)

        compare(size.from, 12)
        compare(size.to, 160)
        compare(size.value, 48)
        compare(outline.checked, true)
        compare(font.currentLabel, panel.defaultFontFamily)
        verify(findChild(panel, "text-panel-font-note").text.length > 0)
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

    function test_systemFontCatalogIsExposedAndOrdered() {
        const panel = make()
        const system = Qt.fontFamilies()

        compare(panel.hasSystemFontCatalog, true)
        verify(panel.usesSystemFonts, "Qt.fontFamilies() should be available in Qt 6")
        compare(panel.systemFontFamilies.length, system.length)
        compare(panel.fontChoices[0].value, "")
        compare(panel.fontChoices[0].label, qsTr("System default"))
        compare(panel.fontCount, panel.fontChoices.length - 1)
        verify(panel.fontCount > 1)

        // Case-insensitive dedupe: every non-default value is unique.
        const seen = Object.create(null)
        const preferredKeys = Object.create(null)
        for (let p = 0; p < panel.preferredFontFamilies.length; ++p)
            preferredKeys[panel.preferredFontFamilies[p].toLowerCase()] = true

        let sawOrdinaryFamily = false
        for (let i = 1; i < panel.fontChoices.length; ++i) {
            const value = panel.fontChoices[i].value
            const key = value.toLowerCase()
            verify(!seen[key], "duplicate font family: " + value)
            seen[key] = true
            if (preferredKeys[key]) {
                verify(!sawOrdinaryFamily,
                       "preferred family must be listed before ordinary families: " + value)
            } else {
                sawOrdinaryFamily = true
            }
        }

        // Selected families outside the catalog stay visible.
        panel.fontFamily = "NekoPic Missing Font"
        const last = panel.fontModel[panel.fontModel.length - 1]
        compare(last.value, "NekoPic Missing Font")
        compare(findChild(panel, "text-panel-font").currentLabel, "NekoPic Missing Font")
    }

    function test_catalogBuilderDedupesAndFallsBack() {
        const built = FontCatalog.build(
            ["DejaVu Sans", "dejavu sans", "Noto Sans", "Noto Sans"],
            "System default")
        compare(built.length, 3)
        compare(built[0].value, "")
        compare(built[0].label, "System default")
        compare(built[1].value, "Noto Sans")
        compare(built[2].value, "DejaVu Sans")

        const fallback = FontCatalog.build(FontCatalog.curatedFamilies, "System default")
        compare(fallback.length, FontCatalog.curatedFamilies.length + 1)
        compare(fallback[1].value, "Noto Sans CJK SC")
        verify(fallback[2].label.indexOf("Serif CJK") >= 0)
    }

    function test_pickerFiltersWithSearch() {
        const panel = make()
        const picker = findChild(panel, "text-panel-font")
        const search = findChild(panel, "font-picker-search")
        const list = findChild(panel, "font-picker-list")
        const empty = findChild(panel, "font-picker-empty")
        verify(search !== null && list !== null && empty !== null)

        picker.openPicker()
        tryVerify(function() { return picker.popupVisible })
        verify(waitForRendering(panel))

        search.text = "noto"
        tryCompare(list, "count", picker.filteredModel.length)
        verify(picker.filteredModel.length > 0)
        for (let i = 0; i < picker.filteredModel.length; ++i)
            verify(picker.filteredModel[i].label.toLowerCase().indexOf("noto") >= 0)

        search.text = "zzzz-no-such-font-family"
        tryCompare(list, "count", 0)
        compare(picker.filteredModel.length, 0)
        verify(empty.opacity > 0)
        tryVerify(function() { return empty.height > 0 })
        verify(waitForRendering(panel))

        search.text = ""
        tryCompare(list, "count", panel.fontModel.length)
        compare(empty.opacity, 0)
        picker.closePicker()
    }

    function test_pickerSelectionEmitsStyleEdit() {
        const panel = make()
        const styles = createTemporaryObject(spyComponent, testCase,
                                             { target: panel, signalName: "styleEdited" })
        const picker = findChild(panel, "text-panel-font")
        const search = findChild(panel, "font-picker-search")
        const list = findChild(panel, "font-picker-list")

        picker.openPicker()
        tryVerify(function() { return picker.popupVisible })
        search.text = panel.fontModel[1].value
        tryCompare(list, "count", picker.filteredModel.length)
        verify(picker.filteredModel.length > 0)

        const expected = picker.filteredModel[0].value
        list.currentIndex = 0
        search.forceActiveFocus()
        keyClick(Qt.Key_Return)

        compare(panel.fontFamily, expected)
        compare(styles.count, 1)
        compare(styles.signalArguments[0][0], "font")
        compare(styles.signalArguments[0][1], expected)
        tryVerify(function() { return !picker.popupVisible })
        compare(picker.currentLabel, expected)
    }

    function test_pickerKeyboardOpenClose() {
        const panel = make()
        const picker = findChild(panel, "text-panel-font")
        const button = findChild(panel, "font-picker-button")
        const search = findChild(panel, "font-picker-search")
        verify(button !== null && search !== null)
        compare(button.Accessible.name, qsTranslate("FontPicker", "Font family"))
        compare(button.Accessible.role, Accessible.ComboBox)
        compare(search.Accessible.name, qsTranslate("FontPicker", "Search fonts"))

        button.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryVerify(function() { return picker.popupVisible })
        verify(waitForRendering(panel))
        search.forceActiveFocus()

        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !picker.popupVisible })

        // Return on the closed control opens the picker as well.
        button.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryVerify(function() { return picker.popupVisible })
        search.forceActiveFocus()

        // Up/Down move the highlight without closing the popup.
        keyClick(Qt.Key_Down)
        verify(picker.popupVisible)
        keyClick(Qt.Key_Up)
        verify(picker.popupVisible)

        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !picker.popupVisible })
    }

    function test_selectedFamilySurvivesModelRebuild() {
        const panel = make()
        const picker = findChild(panel, "text-panel-font")
        const search = findChild(panel, "font-picker-search")
        const list = findChild(panel, "font-picker-list")
        const custom = "NekoPic Rebuild Font"

        panel.fontFamily = custom
        compare(picker.currentLabel, custom)
        verify(panel.fontModel[panel.fontModel.length - 1].value === custom)

        picker.openPicker()
        tryVerify(function() { return picker.popupVisible })

        // Rebuilding the filtered model must not drop the selected family.
        search.text = "zzzz-no-match"
        tryCompare(list, "count", 0)
        compare(picker.currentLabel, custom)
        search.text = ""
        tryCompare(list, "count", panel.fontModel.length)
        compare(picker.currentLabel, custom)

        let found = false
        for (let i = 0; i < panel.fontModel.length; ++i) {
            if (panel.fontModel[i].value === custom)
                found = true
        }
        verify(found)
        picker.closePicker()
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

    function test_layoutAtEditorWindowSize() {
        // At 1100×720 the inspector is 292 px wide and full height.
        const panel = make({ width: 292, height: 720 })
        const scroller = findChild(panel, "text-panel-scroll")
        const picker = findChild(panel, "text-panel-font")
        verify(scroller !== null && picker !== null)
        compare(scroller.width, 292 - 2 * Theme.spacing2xl)
        verify(picker.width <= scroller.width)

        picker.openPicker()
        tryVerify(function() { return picker.popupVisible })
        verify(waitForRendering(panel))
        const popup = findChild(panel, "font-picker-popup")
        verify(popup !== null)
        verify(popup.width <= picker.width)
        verify(popup.height <= panel.height)
        picker.closePicker()
    }

    function test_editModeMarksExistingText() {
        const panel = make({ editId: 7, text: "Existing" })
        compare(panel.editMode, true)
        compare(panel.text, "Existing")
        verify(findChild(panel, "text-panel-text").text, "Existing")
    }
}
