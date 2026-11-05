import QtQuick
import QtTest
import "../shell"

TestCase {
    id: testCase
    name: "CommandPalette"
    when: windowShown
    visible: true
    width: 900
    height: 640

    property int openRuns: 0
    property int saveRuns: 0
    property int disabledRuns: 0

    Component {
        id: paletteComponent
        CommandPalette { }
    }

    function makePalette(commands) {
        const palette = createTemporaryObject(paletteComponent, testCase, {
            width: testCase.width,
            height: testCase.height
        })
        palette.commands = commands
        return palette
    }

    function commands() {
        return [
            { title: "Open image", detail: "File", shortcut: "Ctrl+O", run: function() { testCase.openRuns++ } },
            { title: "Save", detail: "File", shortcut: "Ctrl+S", run: function() { testCase.saveRuns++ } },
            { title: "Disabled action", detail: "File", enabled: false, run: function() { testCase.disabledRuns++ } }
        ]
    }

    function init() {
        openRuns = 0
        saveRuns = 0
        disabledRuns = 0
    }

    function test_filtersAndRunsWithEnter() {
        const palette = makePalette(commands())
        palette.open()
        compare(palette.opened, true)
        compare(palette.resultCount, 2)
        palette.query = "save"
        compare(palette.resultCount, 1)
        compare(palette.filtered[0].title, "Save")
        keyClick(Qt.Key_Return)
        compare(saveRuns, 1)
        compare(palette.opened, false)
    }

    function test_arrowNavigationAndEscape() {
        const palette = makePalette(commands())
        palette.open()
        compare(palette.currentIndex, 0)
        keyClick(Qt.Key_Down)
        compare(palette.currentIndex, 1)
        keyClick(Qt.Key_Up)
        compare(palette.currentIndex, 0)
        keyClick(Qt.Key_Escape)
        compare(palette.opened, false)
    }

    function test_clickRunsAndDisabledIsExcluded() {
        const palette = makePalette(commands())
        palette.open()
        palette.query = "disabled"
        compare(palette.resultCount, 0)
        palette.query = ""
        wait(0)
        compare(palette.resultCount, 2)
        const row = findChild(palette, "command-0")
        verify(row !== null)
        verify(row.width > 0 && row.height > 0)
        mouseClick(row, row.width / 2, row.height / 2)
        compare(openRuns, 1)
        compare(disabledRuns, 0)
    }

    function test_noMatchShowsEmpty() {
        const palette = makePalette(commands())
        palette.open()
        palette.query = "zzzz"
        compare(palette.resultCount, 0)
    }
}
