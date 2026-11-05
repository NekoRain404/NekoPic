import QtQuick
import QtTest
import "../UI"

/*!
    Theme palette contract. The editor exposes the original light/dark pair
    plus four curated palettes (midnight, warm, graphite, contrast). The
    fallback path must keep `Theme.dark` working for older components/tests.
*/
TestCase {
    id: testCase
    name: "ThemePalettes"
    when: windowShown

    function cleanup() {
        Theme.themeId = ""
        Theme.dark = true
        Theme.reduceMotion = false
    }

    function test_defaultPairStillWorks() {
        Theme.themeId = ""
        Theme.dark = true
        const darkBackground = Theme.background.toString()
        Theme.dark = false
        verify(Theme.background.toString() !== darkBackground)
        compare(Theme.textPrimary, "#303734")
    }

    function test_namedPalettesAreDistinct() {
        const ids = ["midnight", "warm", "graphite", "contrast"]
        const backgrounds = []
        const accents = []
        for (let i = 0; i < ids.length; ++i) {
            Theme.themeId = ids[i]
            verify(Theme._palette !== null, ids[i] + " must resolve")
            backgrounds.push(Theme.background.toString())
            accents.push(Theme.accent.toString())
            // Every palette keeps core chrome readable.
            verify(Theme.textPrimary !== Theme.background, ids[i])
            verify(Theme.panel !== Theme.background, ids[i])
            verify(Theme.border !== Theme.panel, ids[i])
        }
        compare(backgrounds.length, 4)
        verify(backgrounds[0] !== backgrounds[1])
        verify(backgrounds[1] !== backgrounds[2])
        verify(backgrounds[2] !== backgrounds[3])
        verify(accents[0] !== accents[3])
    }

    function test_paletteOptionsCoverNamedModes() {
        const ids = []
        for (let i = 0; i < Theme.themeOptions.length; ++i)
            ids.push(Theme.themeOptions[i].id)
        for (const expected of ["system", "light", "dark", "midnight",
                                "warm", "graphite", "contrast"])
            verify(ids.indexOf(expected) >= 0, expected)
    }

    function test_contrastColorStaysLegible() {
        compare(Theme.contrastColor(Theme.background), Theme.contrastPaper)
        compare(Theme.contrastColor(Qt.rgba(0.969, 0.969, 0.957, 1.0)), Theme.contrastInk)
    }
}
