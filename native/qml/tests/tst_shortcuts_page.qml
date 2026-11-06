import QtQuick
import QtQuick.Controls
import QtTest
import "../settings"
import "../UI"

/*!
    ShortcutsPage contract tests.

    The page is persistence-agnostic: it receives the override map, validates
    conflicts locally and reports changes. SettingsDialog/AppDialogs tests
    cover the integration with SettingsManager.
*/
TestCase {
    id: testCase
    name: "ShortcutsPage"
    when: windowShown
    visible: true
    width: 720
    height: 800

    Component { id: pageComponent; ShortcutsPage {} }
    Component { id: spyComponent; SignalSpy {} }

    function make(props) {
        return createTemporaryObject(pageComponent, testCase, props || {})
    }

    function makeSpy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase,
                                     { target: target, signalName: signalName })
    }

    function child(root, name) {
        if (!root)
            return null
        let found = findChild(root, name)
        if (found === null && root.contentItem)
            found = findChild(root.contentItem, name)
        return found
    }

    function editButton(page, key) {
        return child(page, "settings-shortcut-edit-" + key)
    }

    function openCapture(page, key) {
        const button = editButton(page, key)
        verify(button !== null, "missing edit button for " + key)
        mouseClick(button)
        const popup = child(page, "shortcut-capture")
        verify(popup !== null)
        tryVerify(function() { return popup.opened }, 1500)
        return popup
    }

    function test_catalogueIsGroupedAndShowsDefaults() {
        const page = make()
        verify(page !== null)
        compare(page.groups.length, 5)
        const groupIds = ["file", "edit", "view", "tools", "help"]
        for (let i = 0; i < groupIds.length; ++i)
            verify(child(page, "settings-shortcut-group-" + groupIds[i]) !== null,
                   "missing group " + groupIds[i])

        const keys = ["open", "save", "saveAs", "settings", "commandPalette",
                      "copy", "undo", "redo", "zoomIn", "zoomOut", "fit", "actual",
                      "brush", "shape", "pan", "select", "text", "eyedropper", "crop"]
        for (let i = 0; i < keys.length; ++i) {
            const value = child(page, "settings-shortcut-value-" + keys[i])
            verify(value !== null, "missing value for " + keys[i])
            compare(value.text, page.defaultFor(keys[i]))
        }
        compare(child(page, "settings-shortcut-value-open").text, "Ctrl+O")
        compare(child(page, "settings-shortcut-value-brush").text, "B")
        compare(page.customCount, 0)
        compare(child(page, "settings-shortcuts-reset-all").enabled, false)
    }

    function test_overrideMapDrivesRowsAndResetButtons() {
        const page = make({ shortcuts: ({ open: "Ctrl+Shift+O", brush: "N" }) })
        compare(child(page, "settings-shortcut-value-open").text, "Ctrl+Shift+O")
        compare(child(page, "settings-shortcut-value-brush").text, "N")
        compare(page.customCount, 2)
        verify(child(page, "settings-shortcut-reset-open").visible)
        verify(child(page, "settings-shortcut-reset-brush").visible)
        verify(!child(page, "settings-shortcut-reset-save").visible)
        compare(child(page, "settings-shortcuts-reset-all").enabled, true)
    }

    function test_captureEmitsPortableSequence() {
        const page = make()
        const spy = makeSpy(page, "shortcutChangeRequested")
        const popup = openCapture(page, "open")

        compare(child(page, "shortcut-capture-preview").text, "Ctrl+O")
        verify(page.captureKey(Qt.Key_B, Qt.ControlModifier))
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "open")
        compare(spy.signalArguments[0][1], "Ctrl+B")
        tryVerify(function() { return !popup.opened }, 1500)
    }

    function test_captureUsesSettingsManagerServiceWhenAvailable() {
        const service = Qt.createQmlObject(
            "import QtQuick; QtObject { function keySequence(key, modifiers) { return 'Alt+Z' } }",
            testCase, "service")
        const page = make({ shortcutService: service })
        const spy = makeSpy(page, "shortcutChangeRequested")
        openCapture(page, "save")
        verify(page.captureKey(Qt.Key_Z, Qt.AltModifier))
        compare(spy.count, 1)
        compare(spy.signalArguments[0][1], "Alt+Z")
    }

    function test_escapeCancelsAndDeleteClears() {
        const page = make({ shortcuts: ({ open: "Ctrl+Shift+O" }) })
        const spy = makeSpy(page, "shortcutChangeRequested")

        let popup = openCapture(page, "open")
        verify(page.captureKey(Qt.Key_Escape, Qt.NoModifier))
        tryVerify(function() { return !popup.opened }, 1500)
        compare(spy.count, 0)

        popup = openCapture(page, "open")
        verify(page.captureKey(Qt.Key_Delete, Qt.NoModifier))
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "open")
        compare(spy.signalArguments[0][1], "")
        tryVerify(function() { return !popup.opened }, 1500)
    }

    function test_duplicateCombinationShowsConflict() {
        const page = make({ shortcuts: ({ open: "Ctrl+S" }) })
        const spy = makeSpy(page, "shortcutChangeRequested")
        const popup = openCapture(page, "save")

        verify(page.captureKey(Qt.Key_S, Qt.ControlModifier))
        compare(spy.count, 0, "conflicting sequence must not emit")
        verify(page.errorText.length > 0)
        const error = child(page, "settings-shortcut-error")
        verify(error !== null && error.visible)
        verify(error.text.indexOf("Ctrl+S") >= 0)
        compare(popup.opened, true, "capture popup stays open on conflict")

        // A unique combination clears the error and persists.
        verify(page.captureKey(Qt.Key_F9, Qt.NoModifier))
        compare(page.errorText, "")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][1], "F9")
    }

    function test_resetOneAndResetAllEmit() {
        const page = make({ shortcuts: ({ open: "Ctrl+Shift+O", save: "Ctrl+Alt+S" }) })
        const one = makeSpy(page, "shortcutResetRequested")
        const all = makeSpy(page, "shortcutsResetRequested")

        const resetOpen = child(page, "settings-shortcut-reset-open")
        verify(resetOpen.visible)
        mouseClick(resetOpen)
        compare(one.count, 1)
        compare(one.signalArguments[0][0], "open")

        const resetAll = child(page, "settings-shortcuts-reset-all")
        verify(resetAll.enabled)
        mouseClick(resetAll)
        compare(all.count, 1)
    }

    function test_keySequenceFallbackMatchesPortableText() {
        const page = make()
        compare(page.keySequence(Qt.Key_O, Qt.ControlModifier), "Ctrl+O")
        compare(page.keySequence(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier),
                "Ctrl+Shift+S")
        compare(page.keySequence(Qt.Key_F1, Qt.NoModifier), "F1")
        compare(page.keySequence(Qt.Key_Comma, Qt.ControlModifier), "Ctrl+,")
    }

    function test_busyDisablesEditingAndReset() {
        const page = make({ busy: true, shortcuts: ({ open: "Ctrl+Shift+O" }) })
        compare(editButton(page, "open").enabled, false)
        compare(child(page, "settings-shortcut-reset-open").enabled, false)
        compare(child(page, "settings-shortcuts-reset-all").enabled, false)
    }
}
