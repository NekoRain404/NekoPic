import QtQuick
import QtTest
import "../dialogs"
import "../UI"

/*!
    RecoveryDialog contract tests.

    The dialog is decoupled from RecoveryStore: these tests create it directly,
    assert the startup metadata and objectNames, and click the real footer
    buttons to verify accepted()/rejected() that the integrator maps to
    restore/discard.
*/
TestCase {
    id: testCase
    name: "RecoveryDialog"
    when: windowShown
    visible: true
    width: 1100
    height: 720

    Component { id: recoveryComponent; RecoveryDialog {} }
    Component { id: spyComponent; SignalSpy {} }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
    }

    function make(props) {
        return createTemporaryObject(recoveryComponent, testCase, props || {})
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

    function test_metadataAndObjectNames() {
        const dialog = make({
            objectName: "recoveryDialog",
            sourceName: "vacation.jpg",
            sourcePath: "/photos/vacation.jpg",
            capturedAtText: "2026-11-05 08:30",
            imageSizeText: "4000 × 3000 px",
            flattened: true
        })
        verify(dialog !== null)
        compare(dialog.objectName, "recoveryDialog")
        openDialog(dialog)

        compare(dialog.title.length > 0, true)
        compare(dialog.description.length > 0, true)
        compare(dialog.contentItem.Accessible.role, Accessible.Dialog)
        compare(dialog.contentItem.Accessible.name, dialog.accessibleName)

        const source = child(dialog, "recovery-source")
        const path = child(dialog, "recovery-source-path")
        const captured = child(dialog, "recovery-captured-at")
        const size = child(dialog, "recovery-image-size")
        const note = child(dialog, "recovery-flattened-note")
        verify(source !== null)
        compare(source.text, "vacation.jpg")
        compare(path.text, "/photos/vacation.jpg")
        verify(path.visible)
        verify(captured.text.indexOf("2026-11-05 08:30") >= 0)
        compare(size.text, "4000 × 3000 px")
        verify(note.visible)
        verify(note.text.indexOf("flattened") >= 0)
        // Must stay inside the compact 1100×720 window used by the app tests.
        verify(dialog.width <= testCase.width)
        verify(dialog.height <= testCase.height)

        const restore = child(dialog, "recovery-restore")
        const discard = child(dialog, "recovery-discard")
        verify(restore !== null)
        verify(discard !== null)
        compare(restore.text, "Restore")
        compare(discard.text, "Discard")
        compare(restore.Accessible.role, Accessible.Button)
        compare(restore.Accessible.name, "Restore")
        compare(discard.Accessible.role, Accessible.Button)
        compare(discard.Accessible.name, "Discard")

        dialog.close()
        tryVerify(function() { return !dialog.opened }, 3000)
    }

    function test_flattenedNoteHidesWhenNotFlattened() {
        const dialog = make({ flattened: false })
        openDialog(dialog)
        compare(child(dialog, "recovery-flattened-note").visible, false)
        dialog.close()
    }

    function test_emptyMetadataFallsBackToUntitled() {
        const dialog = make()
        openDialog(dialog)
        compare(child(dialog, "recovery-source").text, "Untitled")
        compare(child(dialog, "recovery-source-path").visible, false)
        compare(child(dialog, "recovery-captured-at").visible, false)
        compare(child(dialog, "recovery-image-size").visible, false)
        dialog.close()
    }

    function test_buttonsEmitRestoreAndDiscard() {
        const dialog = make()
        const accepted = createTemporaryObject(spyComponent, testCase, {
            target: dialog, signalName: "accepted"
        })
        const rejected = createTemporaryObject(spyComponent, testCase, {
            target: dialog, signalName: "rejected"
        })
        verify(accepted !== null)
        verify(rejected !== null)

        openDialog(dialog)
        mouseClick(child(dialog, "recovery-restore"))
        tryVerify(function() { return accepted.count === 1 }, 3000)
        tryVerify(function() { return !dialog.opened }, 3000)
        compare(rejected.count, 0)

        openDialog(dialog)
        mouseClick(child(dialog, "recovery-discard"))
        tryVerify(function() { return rejected.count === 1 }, 3000)
        tryVerify(function() { return !dialog.opened }, 3000)
        compare(accepted.count, 1)
    }
}
