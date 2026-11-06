import QtQuick
import QtTest
import "../UI"

/*!
    Theme palette contract. The editor exposes the original light/dark pair
    plus eight curated palettes. The fallback path must keep `Theme.dark`
    working for older components/tests.
*/
TestCase {
    id: testCase
    name: "ThemePalettes"
    when: windowShown

    function cleanup() {
        Theme.themeId = ""
        Theme.dark = true
        Theme.reduceMotion = false
        Theme.fontScale = 1.0
    }

    function channelLuminance(channel) {
        return channel <= 0.03928 ? channel / 12.92
                                  : Math.pow((channel + 0.055) / 1.055, 2.4)
    }

    function luminance(color) {
        return 0.2126 * channelLuminance(color.r)
             + 0.7152 * channelLuminance(color.g)
             + 0.0722 * channelLuminance(color.b)
    }

    function contrastRatio(a, b) {
        const first = luminance(a)
        const second = luminance(b)
        return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
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
        const ids = ["midnight", "warm", "graphite", "contrast",
                     "nordic", "sakura", "forest", "solarized"]
        const backgrounds = []
        const accents = []
        for (let i = 0; i < ids.length; ++i) {
            Theme.themeId = ids[i]
            verify(Theme._palette !== null, ids[i] + " must resolve")
            backgrounds.push(Theme.background.toString())
            accents.push(Theme.accent.toString())
            // Every palette keeps core chrome readable and passes WCAG AA for
            // primary text plus AA-large for secondary text and accents.
            verify(contrastRatio(Theme.textPrimary, Theme.background) >= 4.5,
                   ids[i] + " primary text contrast")
            verify(contrastRatio(Theme.textSecondary, Theme.background) >= 3.0,
                   ids[i] + " secondary text contrast")
            verify(contrastRatio(Theme.accent, Theme.panel) >= 3.0,
                   ids[i] + " accent contrast")
            verify(Theme.panel !== Theme.background, ids[i])
            verify(Theme.border !== Theme.panel, ids[i])
        }
        compare(backgrounds.length, 8)
        for (let i = 1; i < backgrounds.length; ++i)
            verify(backgrounds[i - 1] !== backgrounds[i],
                   "backgrounds must be distinct at " + i)
        verify(accents[0] !== accents[3])
    }

    function test_paletteOptionsCoverNamedModes() {
        const ids = []
        for (let i = 0; i < Theme.themeOptions.length; ++i)
            ids.push(Theme.themeOptions[i].id)
        for (const expected of ["system", "light", "dark", "midnight",
                                "warm", "graphite", "contrast", "nordic",
                                "sakura", "forest", "solarized"])
            verify(ids.indexOf(expected) >= 0, expected)
        compare(Theme.themeOptions.length, 11)
    }

    function test_contrastColorStaysLegible() {
        compare(Theme.contrastColor(Theme.background), Theme.contrastPaper)
        compare(Theme.contrastColor(Qt.rgba(0.969, 0.969, 0.957, 1.0)), Theme.contrastInk)
    }

    function test_fontScaleUpdatesEveryTypeToken() {
        Theme.fontScale = 1.2
        compare(Theme.fontCaption, Math.round(10 * 1.2))
        compare(Theme.fontSmall, Math.round(11 * 1.2))
        compare(Theme.fontBody, Math.round(12 * 1.2))
        compare(Theme.fontTitle, Math.round(15 * 1.2))
        compare(Theme.fontHeadline, Math.round(19 * 1.2))
        compare(Theme.fontDisplay, Math.round(24 * 1.2))

        Theme.fontScale = 0.8
        compare(Theme.fontBody, Math.round(12 * 0.8))
        Theme.fontScale = 1.0
        compare(Theme.fontBody, 12)
    }
}
