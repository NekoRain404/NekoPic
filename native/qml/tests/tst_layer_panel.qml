import QtQuick
import QtTest
import "../objects"
import "../UI"

/*!
    Contract tests for LayerPanel.

    The panel is exercised with deterministic objectSummaries-style maps; it
    owns no document state, so every gesture is verified through its signals
    and through the externally supplied selectedIds property.
*/
TestCase {
    id: testCase
    name: "LayerPanel"
    when: windowShown
    visible: true
    width: 400
    height: 560

    LayerPanel {
        id: panel
        x: 20
        y: 20
        width: 292
        height: 500
    }

    SignalSpy { id: selections; target: panel; signalName: "selectionRequested" }
    SignalSpy { id: visibility; target: panel; signalName: "visibilityToggled" }
    SignalSpy { id: locks; target: panel; signalName: "lockToggled" }
    SignalSpy { id: orders; target: panel; signalName: "orderRequested" }
    SignalSpy { id: removes; target: panel; signalName: "removeRequested" }
    SignalSpy { id: aligns; target: panel; signalName: "alignRequested" }

    function initTestCase() {
        failOnWarning(/Binding loop/)
        failOnWarning(/TypeError/)
        failOnWarning(/ReferenceError/)
        failOnWarning(/is not defined/)
        failOnWarning(/Unable to assign/)
        failOnWarning(/Cannot assign/)
    }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
        panel.enabled = true
        panel.summaries = [
            { id: 3, kind: "text", name: "Top text",
              bounds: Qt.rect(10, 10, 50, 20), visible: true, locked: false },
            { id: 2, kind: "shape", name: "Rectangle",
              bounds: Qt.rect(80, 60, 40, 30), visible: true, locked: false },
            { id: 1, kind: "stroke", name: "Stroke",
              bounds: Qt.rect(120, 100, 60, 20), visible: false, locked: true }
        ]
        panel.selectedIds = []

        selections.clear()
        visibility.clear()
        locks.clear()
        orders.clear()
        removes.clear()
        aligns.clear()
    }

    function row(id) { return findChild(panel, "layerRow-" + id) }
    function rowClick(id) { return findChild(panel, "layerRowClick-" + id) }
    function control(name) { return findChild(panel, name) }
    function list() { return findChild(panel, "layerList") }

    function requireRows() {
        tryVerify(function() {
            return row(1) !== null && row(2) !== null && row(3) !== null
                && rowClick(1) !== null && rowClick(3).width > 0
        }, 2000)
    }

    function test_rowsRenderTopmostFirstWithTypeAndName() {
        requireRows()
        const view = list()
        verify(view !== null)
        compare(view.count, 3)

        // summaries are topmost-first: id 3 above id 2 above id 1.
        verify(row(3).y < row(2).y)
        verify(row(2).y < row(1).y)
        compare(row(3).modelData.id, 3)

        compare(control("layerName-3").text, "Top text")
        compare(control("layerTypeIcon-3").name, "text")
        compare(control("layerTypeIcon-2").name, "shapes")
        compare(control("layerTypeIcon-1").name, "brush")

        // Hidden and locked state is reflected without changing the name.
        verify(control("visibility-1").checked)
        verify(control("lock-1").checked)
        verify(!control("visibility-3").checked)
        verify(!control("lock-3").checked)
    }

    function test_arrayLikeSummariesFromController() {
        // Q_INVOKABLE QVariantList values reach QML as array-like objects:
        // indexed access and `length` work, but Array.isArray() is false.
        panel.summaries = {
            length: 1,
            0: { id: 9, kind: "text", name: "Controller text",
                 bounds: Qt.rect(10, 10, 50, 20), visible: true, locked: false }
        }
        compare(panel._summaryList().length, 1)
        compare(panel._summaryIds().length, 1)
        compare(panel._summaryIds()[0], 9)
    }

    function test_selectedIdsHighlightRows() {
        requireRows()
        panel.selectedIds = [2]
        compare(row(2).isSelected, true)
        compare(row(3).isSelected, false)
        compare(row(1).isSelected, false)
        compare(row(2).color, Theme.selection)

        panel.selectedIds = [3, 1]
        compare(row(3).isSelected, true)
        compare(row(1).isSelected, true)
        compare(row(2).isSelected, false)
    }

    function test_clickEmitsReplacementSelection() {
        requireRows()
        mouseClick(rowClick(2), 5, 5)
        compare(selections.count, 1)
        const ids = selections.signalArguments[0][0]
        compare(ids.length, 1)
        compare(ids[0], 2)

        // Plain click collapses a multi-selection to the clicked row.
        panel.selectedIds = [3, 1]
        mouseClick(rowClick(1), 5, 5)
        compare(selections.count, 2)
        compare(selections.signalArguments[1][0].length, 1)
        compare(selections.signalArguments[1][0][0], 1)
    }

    function test_shiftClickTogglesMembership() {
        requireRows()
        panel.selectedIds = [3]

        mouseClick(rowClick(2), 5, 5, Qt.LeftButton, Qt.ShiftModifier)
        compare(selections.count, 1)
        let ids = selections.signalArguments[0][0]
        compare(ids.length, 2)
        compare(ids[0], 3)
        compare(ids[1], 2)

        // Shift-clicking a member removes it.
        panel.selectedIds = [3, 2]
        mouseClick(rowClick(3), 5, 5, Qt.LeftButton, Qt.ShiftModifier)
        compare(selections.count, 2)
        ids = selections.signalArguments[1][0]
        compare(ids.length, 1)
        compare(ids[0], 2)
    }

    function test_visibilityAndLockToggleSignals() {
        requireRows()
        mouseClick(control("visibility-3"), 10, 10)
        compare(visibility.count, 1)
        compare(visibility.signalArguments[0][0], 3)
        compare(visibility.signalArguments[0][1], false)

        mouseClick(control("visibility-1"), 10, 10)
        compare(visibility.count, 2)
        compare(visibility.signalArguments[1][0], 1)
        compare(visibility.signalArguments[1][1], true)

        mouseClick(control("lock-2"), 10, 10)
        compare(locks.count, 1)
        compare(locks.signalArguments[0][0], 2)
        compare(locks.signalArguments[0][1], true)

        mouseClick(control("lock-1"), 10, 10)
        compare(locks.count, 2)
        compare(locks.signalArguments[1][0], 1)
        compare(locks.signalArguments[1][1], false)
    }

    function test_reorderButtonsEmitActions() {
        requireRows()
        const expected = [
            { name: "front-2", id: 2, action: "front" },
            { name: "up-2", id: 2, action: "up" },
            { name: "down-2", id: 2, action: "down" },
            { name: "back-2", id: 2, action: "back" }
        ]
        for (let i = 0; i < expected.length; ++i) {
            mouseClick(control(expected[i].name), 8, 8)
            compare(orders.count, i + 1)
            compare(orders.signalArguments[i][0], expected[i].id)
            compare(orders.signalArguments[i][1], expected[i].action)
        }
    }

    function test_alignButtonsEmitQtAlignmentFlags() {
        requireRows()
        panel.selectedIds = [3, 1]

        const expected = [
            { name: "align-left", flag: Qt.AlignLeft },
            { name: "align-hcenter", flag: Qt.AlignHCenter },
            { name: "align-right", flag: Qt.AlignRight },
            { name: "align-top", flag: Qt.AlignTop },
            { name: "align-vcenter", flag: Qt.AlignVCenter },
            { name: "align-bottom", flag: Qt.AlignBottom }
        ]
        for (let i = 0; i < expected.length; ++i) {
            mouseClick(control(expected[i].name), 8, 8)
            compare(aligns.count, i + 1)
            const ids = aligns.signalArguments[i][0]
            compare(ids.length, 2)
            compare(ids[0], 3)
            compare(ids[1], 1)
            compare(aligns.signalArguments[i][1], expected[i].flag)
        }

        // Alignment is disabled without a selection.
        panel.selectedIds = []
        verify(!control("align-left").enabled)
        verify(!control("deleteSelected").enabled)
    }

    function test_deleteButtonAndKeyRemoveSelection() {
        requireRows()
        panel.selectedIds = [2, 1]

        mouseClick(control("deleteSelected"), 10, 10)
        compare(removes.count, 1)
        compare(removes.signalArguments[0][0].length, 2)
        compare(removes.signalArguments[0][0][0], 2)
        compare(removes.signalArguments[0][0][1], 1)

        // Keyboard Delete works while the panel has focus.
        panel.forceActiveFocus()
        tryVerify(function() { return panel.activeFocus }, 1000)
        keyClick(Qt.Key_Delete)
        compare(removes.count, 2)
        compare(removes.signalArguments[1][0].length, 2)
    }

    function test_emptyStateAndDisabledPanel() {
        panel.summaries = []
        panel.selectedIds = []
        compare(list().visible, false)
        compare(control("layerEmptyState").visible, true)
        compare(control("layerCount").text, "0")
        compare(control("deleteSelected").enabled, false)

        panel.summaries = [
            { id: 5, kind: "shape", name: "Ellipse",
              bounds: Qt.rect(0, 0, 10, 10), visible: true, locked: false }
        ]
        tryVerify(function() { return row(5) !== null }, 2000)
        panel.enabled = false
        verify(!control("visibility-5").enabled)
        verify(!control("lock-5").enabled)
        verify(!control("front-5").enabled)

        // A disabled panel emits nothing.
        const before = removes.count
        panel.selectedIds = [5]
        compare(panel.removeSelected(), false)
        compare(removes.count, before)
    }
}
