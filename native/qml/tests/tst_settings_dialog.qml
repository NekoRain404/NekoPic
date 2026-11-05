import QtQuick
import QtQuick.Controls
import QtTest
import "../dialogs"
import "../UI"

/*!
    SettingsDialog contract tests.

    The dialog is intentionally decoupled from SettingsManager: these tests
    create it directly, drive the real controls, and assert the emitted
    settingChanged()/localeSelected() payloads that the integrator persists.

    The page is a two-column preferences surface, so tests switch categories
    before clicking controls in the right-hand panel.
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

    function categoryButton(dialog, id) {
        return child(dialog, "settings-category-" + id)
    }

    function activateCategory(dialog, id) {
        const button = categoryButton(dialog, id)
        verify(button !== null, "missing category " + id)
        mouseClick(button)
        tryCompare(dialog, "currentCategory", id)
        wait(20)
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

    function visibleInScroller(dialog, item) {
        const scroller = child(dialog, "settings-scroll")
        scrollTo(dialog, item)
        const point = item.mapToItem(scroller, 0, 0)
        return point.y >= -0.5 && point.y + item.height <= scroller.height + 0.5
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
        compare(dialog.recoveryEnabled, true)
        compare(dialog.startupTool, "adjust")
        compare(dialog.currentCategory, "appearance")
        compare(dialog.localeOptions.length, 4)
        compare(dialog.localeOptions[0].id, "en")
        compare(dialog.localeOptions[1].id, "zh_CN")
        compare(dialog.localeOptions[2].id, "ja_JP")
        compare(dialog.localeOptions[3].id, "de_DE")
        compare(dialog.localeOptions[2].nativeName, "日本語")
        compare(dialog.localeOptions[3].nativeName, "Deutsch")
        compare(dialog.startupToolOptions.length, 10)
        compare(dialog.categories.length, 6)

        verify(child(dialog, "settings-page") !== null)
        verify(child(dialog, "settings-nav") !== null)

        // Two-column page geometry: a preferences surface, not a popup.
        verify(dialog.width >= 760 && dialog.width <= 840,
               "unexpected width " + dialog.width)
        verify(dialog.height <= 700, "dialog height was " + dialog.height)

        const categoryIds = ["appearance", "editing", "export", "language", "recovery", "about"]
        for (let i = 0; i < categoryIds.length; ++i) {
            const button = categoryButton(dialog, categoryIds[i])
            verify(button !== null, "missing category button " + categoryIds[i])
            verify(button.text.length > 0)
            verify(button.Accessible.name.length > 0)
        }
        compare(categoryButton(dialog, "appearance").text, "外观")
        compare(categoryButton(dialog, "recovery").text, "恢复与安全")

        const sections = ["appearance", "editing", "export", "language", "recovery", "about"]
        for (let i = 0; i < sections.length; ++i) {
            const header = child(dialog, "settings-section-" + sections[i])
            verify(header !== null, "missing section " + sections[i])
            verify(header.text.length > 0)
        }
        compare(child(dialog, "settings-section-appearance").text, "外观")
        compare(child(dialog, "settings-section-editing").text, "编辑")
        compare(child(dialog, "settings-section-export").text, "导出")
        compare(child(dialog, "settings-section-language").text, "语言")
        compare(child(dialog, "settings-section-recovery").text, "恢复与安全")
        compare(child(dialog, "settings-section-about").text, "关于")

        const controls = [
            "settings-theme", "settings-reduce-motion", "settings-gpu-preview",
            "settings-checkerboard", "settings-confirm-on-close", "settings-quality",
            "settings-quality-default", "settings-quality-value",
            "settings-background-white", "settings-background-black",
            "settings-background-warm-grey", "settings-locale-en", "settings-locale-zh_CN",
            "settings-locale-ja_JP", "settings-locale-de_DE",
            "settings-recovery-enabled", "settings-recovery-status",
            "settings-recovery-details", "settings-recovery-discard",
            "settings-startup-tool-adjust", "settings-startup-tool-brush",
            "settings-reset", "settings-shortcuts", "settings-about-version",
            "settings-about-qt", "settings-about-formats", "settings-done"
        ]
        for (let i = 0; i < controls.length; ++i)
            verify(child(dialog, controls[i]) !== null, "missing control " + controls[i])

        const theme = child(dialog, "settings-theme")
        compare(theme.count, 3)
        compare(theme.currentIndex, 2)

        openDialog(dialog)
        verify(dialog.opened)
    }

    // ── Category navigation ────────────────────────────────────────────────

    function test_categorySwitchingShowsOnePanelAndResetsScroll() {
        const dialog = make()
        openDialog(dialog)
        const scroller = child(dialog, "settings-scroll")

        compare(child(dialog, "settings-panel-appearance").visible, true)
        compare(child(dialog, "settings-panel-editing").visible, false)

        const ids = ["editing", "export", "language", "recovery", "about", "appearance"]
        for (let i = 0; i < ids.length; ++i) {
            const id = ids[i]
            scroller.contentY = 10
            activateCategory(dialog, id)
            compare(child(dialog, "settings-panel-" + id).visible, true)
            compare(scroller.contentY, 0, "scroll did not reset for " + id)
            for (let j = 0; j < ids.length; ++j) {
                if (ids[j] !== id)
                    compare(child(dialog, "settings-panel-" + ids[j]).visible, false)
            }
        }
    }

    function test_categoryRailKeyboardNavigation() {
        const dialog = make()
        openDialog(dialog)
        const appearance = categoryButton(dialog, "appearance")
        const editing = categoryButton(dialog, "editing")

        appearance.forceActiveFocus()
        tryVerify(function() { return appearance.activeFocus }, 1000)
        keyClick(Qt.Key_Down)
        tryVerify(function() { return editing.activeFocus }, 1000)
        keyClick(Qt.Key_Return)
        tryCompare(dialog, "currentCategory", "editing")

        keyClick(Qt.Key_Up)
        tryVerify(function() { return appearance.activeFocus }, 1000)
        keyClick(Qt.Key_Return)
        tryCompare(dialog, "currentCategory", "appearance")
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

    function test_editingTogglesAndStartupToolEmit() {
        const dialog = make()
        openDialog(dialog)
        activateCategory(dialog, "editing")
        const spy = makeSpy(dialog, "settingChanged")
        const cases = [
            { name: "settings-gpu-preview", key: "gpuPreviewEnabled", property: "gpuPreviewEnabled" },
            { name: "settings-checkerboard", key: "showCheckerboard", property: "showCheckerboard" }
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

        // Startup tool chips are exclusive and only emit on a real change.
        const brush = child(dialog, "settings-startup-tool-brush")
        verify(brush !== null && brush.visible)
        spy.clear()
        mouseClick(brush)
        compare(dialog.startupTool, "brush")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "startupTool")
        compare(spy.signalArguments[0][1], "brush")
        mouseClick(brush)
        compare(spy.count, 1)

        const adjust = child(dialog, "settings-startup-tool-adjust")
        mouseClick(adjust)
        compare(dialog.startupTool, "adjust")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][1], "adjust")

        // Unknown external values fall back to the documented default.
        dialog.startupTool = "neko"
        compare(dialog.startupTool, "adjust")
    }

    // ── Export ──────────────────────────────────────────────────────────────

    function test_qualityClampsAndCodecDefaultOption() {
        const dialog = make({ localeId: "en" })
        openDialog(dialog)
        activateCategory(dialog, "export")
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
        activateCategory(dialog, "export")
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
        activateCategory(dialog, "language")
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
        compare(categoryButton(dialog, "recovery").text, "Recovery & Safety")

        const chinese = child(dialog, "settings-locale-zh_CN")
        scrollTo(dialog, chinese)
        mouseClick(chinese)
        compare(dialog.localeId, "zh_CN")
        compare(localeSpy.count, 2)
        compare(localeSpy.signalArguments[1][0], "zh_CN")

        const japanese = child(dialog, "settings-locale-ja_JP")
        verify(japanese !== null, "missing Japanese language option")
        compare(japanese.text, "日本語")
        settingSpy.clear()
        scrollTo(dialog, japanese)
        mouseClick(japanese)
        compare(dialog.localeId, "ja_JP")
        compare(localeSpy.count, 3)
        compare(localeSpy.signalArguments[2][0], "ja_JP")
        compare(settingValue(settingSpy, "locale"), "ja_JP")

        const german = child(dialog, "settings-locale-de_DE")
        verify(german !== null, "missing German language option")
        compare(german.text, "Deutsch")
        settingSpy.clear()
        scrollTo(dialog, german)
        mouseClick(german)
        compare(dialog.localeId, "de_DE")
        compare(localeSpy.count, 4)
        compare(localeSpy.signalArguments[3][0], "de_DE")
        compare(settingValue(settingSpy, "locale"), "de_DE")
    }

    // ── Recovery and safety ────────────────────────────────────────────────

    function test_recoverySectionReportsStatusAndDiscard() {
        const dialog = make({
            recoveryAvailable: true,
            recoverySourceName: "shot.png",
            recoveryCapturedAt: "2026-11-05 08:30",
            recoveryImageSize: "640 × 480 px"
        })
        openDialog(dialog)
        activateCategory(dialog, "recovery")

        const status = child(dialog, "settings-recovery-status")
        const details = child(dialog, "settings-recovery-details")
        const discard = child(dialog, "settings-recovery-discard")
        compare(status.text, "发现可恢复的快照")
        verify(details.text.indexOf("shot.png") >= 0)
        verify(details.text.indexOf("640 × 480 px") >= 0)
        compare(discard.visible, true)

        const discardSpy = makeSpy(dialog, "recoveryDiscardRequested")
        scrollTo(dialog, discard)
        mouseClick(discard)
        compare(discardSpy.count, 1)

        const settingSpy = makeSpy(dialog, "settingChanged")
        const recovery = child(dialog, "settings-recovery-enabled")
        compare(recovery.checked, true)
        mouseClick(recovery)
        compare(recovery.checked, false)
        compare(dialog.recoveryEnabled, false)
        compare(spyValue(settingSpy, "recoveryEnabled"), false)

        const confirm = child(dialog, "settings-confirm-on-close")
        compare(confirm.checked, true)
        scrollTo(dialog, confirm)
        mouseClick(confirm)
        compare(dialog.confirmOnClose, false)
        compare(spyValue(settingSpy, "confirmOnClose"), false)
    }

    function test_recoverySectionWithoutSnapshotHidesDiscard() {
        const dialog = make()
        openDialog(dialog)
        activateCategory(dialog, "recovery")
        compare(child(dialog, "settings-recovery-status").text, "当前没有恢复快照")
        compare(child(dialog, "settings-recovery-details").visible, false)
        compare(child(dialog, "settings-recovery-discard").visible, false)
    }

    function spyValue(spy, key) {
        return settingValue(spy, key)
    }

    // ── About ───────────────────────────────────────────────────────────────

    function test_aboutShowsCapabilitiesAndShortcutsEntry() {
        const dialog = make({
            localeId: "en",
            formatCapabilities: { readableCount: 12, writableCount: 6 }
        })
        openDialog(dialog)
        activateCategory(dialog, "about")

        verify(child(dialog, "settings-about-version").text.indexOf("NekoPic") === 0)
        compare(child(dialog, "settings-about-formats").text,
                "Reads 12 formats · writes 6 formats")

        const spy = makeSpy(dialog, "shortcutsRequested")
        const shortcuts = child(dialog, "settings-shortcuts")
        scrollTo(dialog, shortcuts)
        mouseClick(shortcuts)
        compare(spy.count, 1)
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
        dialog.recoveryEnabled = false
        dialog.startupTool = "brush"

        const spy = makeSpy(dialog, "settingChanged")
        const localeSpy = makeSpy(dialog, "localeSelected")

        activateCategory(dialog, "recovery")
        const reset = child(dialog, "settings-reset")
        scrollTo(dialog, reset)
        mouseClick(reset)

        compare(dialog.themeMode, "dark")
        compare(dialog.reduceMotion, false)
        compare(dialog.gpuPreviewEnabled, true)
        compare(dialog.exportQuality, -1)
        fuzzyCompare(dialog.jpegBackground.a, 1, 0.001)
        fuzzyCompare(dialog.jpegBackground.r, 1, 0.001)
        compare(dialog.confirmOnClose, true)
        compare(dialog.showCheckerboard, true)
        compare(dialog.recoveryEnabled, true)
        compare(dialog.startupTool, "adjust")
        compare(dialog.localeId, "zh_CN")
        compare(child(dialog, "settings-theme").currentIndex, 2)
        compare(child(dialog, "settings-quality").value, 90)
        compare(child(dialog, "settings-quality-default").checked, true)

        const keys = ["themeMode", "reduceMotion", "gpuPreviewEnabled", "exportQuality",
                      "jpegBackground", "confirmOnClose", "showCheckerboard",
                      "recoveryEnabled", "startupTool", "locale"]
        for (let i = 0; i < keys.length; ++i)
            verify(settingValue(spy, keys[i]) !== undefined, "missing reset signal " + keys[i])

        compare(localeSpy.count, 1)
        compare(localeSpy.signalArguments[0][0], "zh_CN")
    }

    function test_busyDisablesControls() {
        const dialog = make({ recoveryAvailable: true })
        openDialog(dialog)

        dialog.busy = true
        compare(child(dialog, "settings-theme").enabled, false)
        compare(child(dialog, "settings-reduce-motion").enabled, false)

        activateCategory(dialog, "editing")
        compare(child(dialog, "settings-gpu-preview").enabled, false)
        compare(child(dialog, "settings-checkerboard").enabled, false)
        compare(child(dialog, "settings-startup-tool-adjust").enabled, false)

        activateCategory(dialog, "export")
        compare(child(dialog, "settings-quality").enabled, false)
        compare(child(dialog, "settings-quality-default").enabled, false)
        compare(child(dialog, "settings-background-white").enabled, false)

        activateCategory(dialog, "language")
        compare(child(dialog, "settings-locale-en").enabled, false)
        compare(child(dialog, "settings-locale-ja_JP").enabled, false)
        compare(child(dialog, "settings-locale-de_DE").enabled, false)

        activateCategory(dialog, "recovery")
        compare(child(dialog, "settings-recovery-enabled").enabled, false)
        compare(child(dialog, "settings-recovery-discard").enabled, false)
        compare(child(dialog, "settings-confirm-on-close").enabled, false)
        compare(child(dialog, "settings-reset").enabled, false)

        dialog.busy = false
        compare(child(dialog, "settings-theme").enabled, true)
        compare(child(dialog, "settings-quality-default").enabled, true)
        compare(child(dialog, "settings-recovery-enabled").enabled, true)
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
        dialog.recoveryEnabled = false
        dialog.startupTool = "text"
        dialog.currentCategory = "recovery"
        dialog.currentCategory = "about"
        dialog.busy = true
        dialog.busy = false
        dialog.resetToDefaults()
        dialog.close()
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    // ── Scrollbar and compact geometry ─────────────────────────────────────

    function test_scrollbarIsInvisibleButWheelStillScrolls() {
        testCase.width = 860
        testCase.height = 600
        const dialog = make()
        openDialog(dialog)
        activateCategory(dialog, "recovery")
        // Constrain the viewport so the wheel gesture has somewhere to go.
        dialog.height = 420
        wait(50)

        const scroller = child(dialog, "settings-scroll")
        const scrollbar = child(dialog, "settings-scrollbar")
        verify(scrollbar !== null)
        compare(scrollbar.policy, ScrollBar.AlwaysOff)
        compare(scrollbar.visible, false)

        verify(scroller.contentHeight > scroller.height,
               "recovery content should overflow in a compact window")
        compare(scroller.contentY, 0)
        mouseWheel(scroller, 40, 40, 0, -120, Qt.NoButton)
        tryVerify(function() { return scroller.contentY > 0 }, 2000)

        dialog.close()
        tryVerify(function() { return !dialog.opened }, 3000)
        testCase.width = 1000
        testCase.height = 800
    }

    function test_compactGeometryKeepsEveryCategoryReachable() {
        const sizes = [[1100, 720], [1440, 900], [860, 600]]
        const checks = {
            "appearance": ["settings-theme", "settings-reduce-motion"],
            "editing": ["settings-gpu-preview", "settings-checkerboard",
                        "settings-startup-tool-brush"],
            "export": ["settings-quality", "settings-quality-default",
                       "settings-background-black"],
            "language": ["settings-locale-en", "settings-locale-ja_JP",
                         "settings-locale-de_DE"],
            "recovery": ["settings-recovery-enabled", "settings-confirm-on-close",
                         "settings-reset"],
            "about": ["settings-shortcuts", "settings-about-formats"]
        }
        const categoryIds = ["appearance", "editing", "export", "language", "recovery", "about"]

        for (let s = 0; s < sizes.length; ++s) {
            testCase.width = sizes[s][0]
            testCase.height = sizes[s][1]
            const dialog = make()
            openDialog(dialog)

            verify(dialog.width >= 760 && dialog.width <= 840,
                   "width at " + sizes[s][0] + "x" + sizes[s][1] + " was " + dialog.width)
            verify(dialog.height <= sizes[s][1], "dialog is taller than the window")

            const scroller = child(dialog, "settings-scroll")
            const done = child(dialog, "settings-done")
            verify(scroller !== null && done !== null)
            const scrollerPoint = scroller.mapToItem(dialog.contentItem, 0, 0)
            const donePoint = done.mapToItem(dialog.contentItem, 0, 0)
            verify(scrollerPoint.y + scroller.height <= donePoint.y + 0.5,
                   "scroll body overlaps the fixed footer at "
                   + sizes[s][0] + "x" + sizes[s][1])
            verify(scroller.contentWidth <= scroller.width + 0.5,
                   "scroll body has horizontal overflow")

            for (let c = 0; c < categoryIds.length; ++c) {
                const id = categoryIds[c]
                activateCategory(dialog, id)
                const panel = child(dialog, "settings-panel-" + id)
                verify(panel.visible, "panel not visible: " + id)
                verify(panel.width <= scroller.width + 0.5,
                       "panel exceeds scroll width for " + id)
                const names = checks[id]
                for (let n = 0; n < names.length; ++n) {
                    const control = child(dialog, names[n])
                    verify(control !== null, "missing " + names[n])
                    verify(visibleInScroller(dialog, control),
                           names[n] + " is clipped at "
                           + sizes[s][0] + "x" + sizes[s][1])
                }
            }

            dialog.close()
            tryVerify(function() { return !dialog.opened }, 3000)
        }

        testCase.width = 1000
        testCase.height = 800
    }
}
