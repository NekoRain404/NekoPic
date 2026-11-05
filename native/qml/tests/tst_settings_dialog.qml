import QtQuick
import QtTest
import "../dialogs"
import "../UI"

/*!
    SettingsDialog contract tests.

    The dialog is intentionally decoupled from SettingsManager: these tests
    create it directly, drive the real controls, and assert the emitted
    settingChanged()/localeSelected() payloads that the integrator persists.
*/
TestCase {
    id: testCase
    name: "SettingsDialog"
    when: windowShown
    visible: true
    width: 1000
    height: 800

    Component { id: settingsComponent; SettingsDialog {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
    }

    function make(props) {
        return createTemporaryObject(settingsComponent, testCase, props || {})
    }

    function makeSpy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase, { target: target, signalName: signalName })
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

    function settingValue(spy, key) {
        for (let i = 0; i < spy.count; ++i) {
            const args = spy.signalArguments[i]
            if (args[0] === key)
                return args[1]
        }
        return undefined
    }

    // Scroll the settings flickable so controls near the bottom can be
    // clicked in the offscreen test window.
    function scrollTo(dialog, item) {
        const scroller = child(dialog, "settings-scroll")
        verify(scroller !== null)
        wait(10)
        const point = item.mapToItem(scroller, 0, 0)
        const margin = Theme.spacingMd * 2
        const maximum = Math.max(0, scroller.contentHeight - scroller.height)
        if (point.y < margin) {
            scroller.contentY = Math.max(0, scroller.contentY - (margin - point.y))
        } else if (point.y + item.height > scroller.height - margin) {
            const delta = point.y + item.height - scroller.height + margin
            scroller.contentY = Math.min(maximum, scroller.contentY + delta)
        }
        wait(30)
    }

    // ── Structure ───────────────────────────────────────────────────────────

    function test_loadsWithDefaultsAndEverySection() {
        const dialog = make()
        verify(dialog !== null)

        compare(dialog.themeMode, "dark")
        compare(dialog.reduceMotion, false)
        compare(dialog.gpuPreviewEnabled, true)
        compare(dialog.exportQuality, -1)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        compare(dialog.localeId, "zh_CN")
        compare(dialog.confirmOnClose, true)
        compare(dialog.showCheckerboard, true)
        compare(dialog.localeOptions.length, 2)
        compare(dialog.localeOptions[0].id, "en")
        compare(dialog.localeOptions[1].id, "zh_CN")

        const sections = ["appearance", "editing", "export", "language", "about"]
        for (let i = 0; i < sections.length; ++i) {
            const header = child(dialog, "settings-section-" + sections[i])
            verify(header !== null, "missing section " + sections[i])
            verify(header.text.length > 0)
        }
        compare(child(dialog, "settings-section-appearance").text, "外观")
        compare(child(dialog, "settings-section-editing").text, "编辑")
        compare(child(dialog, "settings-section-export").text, "导出")
        compare(child(dialog, "settings-section-language").text, "语言")
        compare(child(dialog, "settings-section-about").text, "关于")

        const controls = [
            "settings-theme", "settings-reduce-motion", "settings-gpu-preview",
            "settings-checkerboard", "settings-confirm-on-close", "settings-quality",
            "settings-quality-default", "settings-quality-value",
            "settings-background-white", "settings-background-black",
            "settings-background-warm-grey", "settings-locale-en", "settings-locale-zh_CN",
            "settings-reset", "settings-about-version", "settings-about-qt"
        ]
        for (let i = 0; i < controls.length; ++i)
            verify(child(dialog, controls[i]) !== null, "missing control " + controls[i])

        const theme = child(dialog, "settings-theme")
        compare(theme.count, 3)
        compare(theme.currentIndex, 2)

        openDialog(dialog)
        verify(dialog.width <= 900)
        verify(dialog.height <= 700, "dialog height was " + dialog.height)
    }

    // ── Appearance ──────────────────────────────────────────────────────────

    function test_themeSelectionEmits() {
        const dialog = make()
        openDialog(dialog)
        const spy = makeSpy(dialog, "settingChanged")
        const theme = child(dialog, "settings-theme")

        theme.activate(1)
        compare(dialog.themeMode, "light")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "themeMode")
        compare(spy.signalArguments[0][1], "light")

        theme.activate(0)
        compare(dialog.themeMode, "system")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][1], "system")

        theme.activate(2)
        compare(dialog.themeMode, "dark")
        compare(spy.count, 3)

        // Selecting the already-active segment does not emit again.
        theme.activate(2)
        compare(spy.count, 3)
    }

    function test_motionToggleEmits() {
        const dialog = make()
        openDialog(dialog)
        const spy = makeSpy(dialog, "settingChanged")
        const toggle = child(dialog, "settings-reduce-motion")

        compare(toggle.checked, false)
        mouseClick(toggle)
        compare(toggle.checked, true)
        compare(dialog.reduceMotion, true)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "reduceMotion")
        compare(spy.signalArguments[0][1], true)
    }

    // ── Editing ─────────────────────────────────────────────────────────────

    function test_editingTogglesEmit() {
        const dialog = make()
        openDialog(dialog)
        const spy = makeSpy(dialog, "settingChanged")
        const cases = [
            { name: "settings-gpu-preview", key: "gpuPreviewEnabled", property: "gpuPreviewEnabled" },
            { name: "settings-checkerboard", key: "showCheckerboard", property: "showCheckerboard" },
            { name: "settings-confirm-on-close", key: "confirmOnClose", property: "confirmOnClose" }
        ]

        for (let i = 0; i < cases.length; ++i) {
            const entry = cases[i]
            const toggle = child(dialog, entry.name)
            verify(toggle !== null)
            compare(toggle.checked, true)
            spy.clear()
            scrollTo(dialog, toggle)

            mouseClick(toggle)
            compare(toggle.checked, false)
            compare(dialog[entry.property], false)
            compare(spy.count, 1)
            compare(spy.signalArguments[0][0], entry.key)
            compare(spy.signalArguments[0][1], false)

            mouseClick(toggle)
            compare(dialog[entry.property], true)
            compare(spy.count, 2)
        }
    }

    // ── Export ──────────────────────────────────────────────────────────────

    function test_qualityClampsAndCodecDefaultOption() {
        const dialog = make({ localeId: "en" })
        openDialog(dialog)
        const slider = child(dialog, "settings-quality")
        const value = child(dialog, "settings-quality-value")
        const defaultToggle = child(dialog, "settings-quality-default")

        compare(defaultToggle.checked, true)
        compare(slider.enabled, false)
        compare(value.text, "Codec default")

        dialog.exportQuality = 250
        compare(dialog.exportQuality, 100)
        compare(slider.value, 100)
        compare(value.text, "100%")
        compare(defaultToggle.checked, false)
        compare(slider.enabled, true)

        dialog.exportQuality = -12
        compare(dialog.exportQuality, -1)
        compare(defaultToggle.checked, true)
        compare(slider.enabled, false)
        compare(value.text, "Codec default")

        dialog.exportQuality = 90
        compare(defaultToggle.checked, false)
        compare(slider.enabled, true)

        const spy = makeSpy(dialog, "settingChanged")
        slider.commit(37)
        compare(dialog.exportQuality, 37)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "exportQuality")
        compare(spy.signalArguments[0][1], 37)

        spy.clear()
        scrollTo(dialog, defaultToggle)
        mouseClick(defaultToggle)
        compare(dialog.exportQuality, -1)
        compare(defaultToggle.checked, true)
        compare(slider.enabled, false)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][1], -1)

        spy.clear()
        mouseClick(defaultToggle)
        compare(dialog.exportQuality, 37)
        compare(defaultToggle.checked, false)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][1], 37)
    }

    function test_backgroundSwatchesStayOpaque() {
        const dialog = make({ localeId: "en" })
        openDialog(dialog)
        const spy = makeSpy(dialog, "settingChanged")

        const blackSwatch = child(dialog, "settings-background-black")
        scrollTo(dialog, blackSwatch)
        mouseClick(blackSwatch)
        compare(dialog.jpegBackground.r, 0)
        compare(dialog.jpegBackground.g, 0)
        compare(dialog.jpegBackground.b, 0)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "jpegBackground")
        fuzzyCompare(spy.signalArguments[0][1].a, 1, 0.001)

        spy.clear()
        const warmSwatch = child(dialog, "settings-background-warm-grey")
        scrollTo(dialog, warmSwatch)
        mouseClick(warmSwatch)
        fuzzyCompare(dialog.jpegBackground.r, 139 / 255, 0.01)
        fuzzyCompare(dialog.jpegBackground.g, 135 / 255, 0.01)
        fuzzyCompare(dialog.jpegBackground.b, 128 / 255, 0.01)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        compare(spy.count, 1)

        // A transparent or invalid colour supplied by the parent is forced
        // opaque locally.
        dialog.jpegBackground = Qt.rgba(0.2, 0.4, 0.6, 0.2)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        fuzzyCompare(dialog.jpegBackground.r, 0.2, 0.001)
    }

    // ── Language ────────────────────────────────────────────────────────────

    function test_localeSelectionEmitsAndRelocalises() {
        const dialog = make()
        openDialog(dialog)
        const settingSpy = makeSpy(dialog, "settingChanged")
        const localeSpy = makeSpy(dialog, "localeSelected")
        const english = child(dialog, "settings-locale-en")

        compare(child(dialog, "settings-section-appearance").text, "外观")
        scrollTo(dialog, english)
        mouseClick(english)

        compare(dialog.localeId, "en")
        compare(localeSpy.count, 1)
        compare(localeSpy.signalArguments[0][0], "en")
        compare(settingValue(settingSpy, "locale"), "en")
        compare(child(dialog, "settings-section-appearance").text, "Appearance")

        const chinese = child(dialog, "settings-locale-zh_CN")
        scrollTo(dialog, chinese)
        mouseClick(chinese)
        compare(dialog.localeId, "zh_CN")
        compare(localeSpy.count, 2)
        compare(localeSpy.signalArguments[1][0], "zh_CN")
    }

    // ── Reset, busy and lifecycle ───────────────────────────────────────────

    function test_resetRestoresDefaultsAndEmitsEveryKey() {
        const dialog = make({ localeId: "en" })
        openDialog(dialog)
        dialog.themeMode = "light"
        dialog.reduceMotion = true
        dialog.gpuPreviewEnabled = false
        dialog.exportQuality = 55
        dialog.jpegBackground = "#000000"
        dialog.confirmOnClose = false
        dialog.showCheckerboard = false

        const spy = makeSpy(dialog, "settingChanged")
        const localeSpy = makeSpy(dialog, "localeSelected")

        mouseClick(child(dialog, "settings-reset"))

        compare(dialog.themeMode, "dark")
        compare(dialog.reduceMotion, false)
        compare(dialog.gpuPreviewEnabled, true)
        compare(dialog.exportQuality, -1)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        fuzzyCompare(dialog.jpegBackground.r, 1, 0.001)
        compare(dialog.confirmOnClose, true)
        compare(dialog.showCheckerboard, true)
        compare(dialog.localeId, "zh_CN")
        compare(child(dialog, "settings-theme").currentIndex, 2)
        compare(child(dialog, "settings-quality").value, 90)
        compare(child(dialog, "settings-quality-default").checked, true)

        const keys = ["themeMode", "reduceMotion", "gpuPreviewEnabled", "exportQuality",
                      "jpegBackground", "confirmOnClose", "showCheckerboard", "locale"]
        for (let i = 0; i < keys.length; ++i)
            verify(settingValue(spy, keys[i]) !== undefined, "missing reset signal " + keys[i])

        compare(localeSpy.count, 1)
        compare(localeSpy.signalArguments[0][0], "zh_CN")
    }

    function test_busyDisablesControls() {
        const dialog = make()
        openDialog(dialog)

        dialog.busy = true
        compare(child(dialog, "settings-theme").enabled, false)
        compare(child(dialog, "settings-reduce-motion").enabled, false)
        compare(child(dialog, "settings-gpu-preview").enabled, false)
        compare(child(dialog, "settings-checkerboard").enabled, false)
        compare(child(dialog, "settings-confirm-on-close").enabled, false)
        compare(child(dialog, "settings-quality").enabled, false)
        compare(child(dialog, "settings-quality-default").enabled, false)
        compare(child(dialog, "settings-background-white").enabled, false)
        compare(child(dialog, "settings-locale-en").enabled, false)
        compare(child(dialog, "settings-reset").enabled, false)

        dialog.busy = false
        compare(child(dialog, "settings-theme").enabled, true)
        compare(child(dialog, "settings-quality-default").enabled, true)
        compare(child(dialog, "settings-reset").enabled, true)
    }

    function test_escapeRejects() {
        const dialog = make()
        openDialog(dialog)
        const rejected = makeSpy(dialog, "rejected")

        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !dialog.opened }, 3000)
        compare(rejected.count, 1)
    }

    function test_noBindingLoopWarnings() {
        failOnWarning(/binding loop/i)

        const dialog = make()
        openDialog(dialog)
        dialog.themeMode = "light"
        dialog.localeId = "en"
        dialog.exportQuality = 100
        dialog.exportQuality = -1
        dialog.exportQuality = 42
        dialog.jpegBackground = "#8b8780"
        dialog.reduceMotion = true
        dialog.busy = true
        dialog.busy = false
        dialog.resetToDefaults()
        dialog.close()
        tryVerify(function() { return !dialog.opened }, 3000)
    }
}
