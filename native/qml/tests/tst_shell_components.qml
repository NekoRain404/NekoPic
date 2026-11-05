import QtQuick
import QtQuick.Controls
import QtTest
import ".."
import "../shell"

/*!
    Shell component contract tests.

    Main.qml is the composition root; these tests instantiate the extracted
    shell pieces directly and verify that every objectName the window tests
    rely on still lives on the component that owns the behaviour.
*/
TestCase {
    id: testCase
    name: "ShellComponents"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Component { id: toolRailComponent; ToolRail {} }
    Component { id: statusBarComponent; StatusBar {} }
    Component { id: topActionBarComponent; TopActionBar {} }
    Component { id: toolInfoPanelComponent; ToolInfoPanel {} }
    Component { id: spyComponent; SignalSpy {} }

    Action { id: openAction; text: "Open" }
    Action { id: undoAction; text: "Undo" }
    Action { id: redoAction; text: "Redo" }
    Action { id: rotateAction; text: "Rotate" }
    Action { id: cropAction; text: "Crop" }
    Action { id: saveAction; text: "Save" }
    Action { id: saveAsAction; text: "Save as" }
    Action { id: canvasSizeAction; text: "Canvas size" }

    function visualChild(item, name) {
        if (item.objectName === name)
            return item
        for (let i = 0; i < item.children.length; ++i) {
            const child = visualChild(item.children[i], name)
            if (child)
                return child
        }
        return null
    }

    function makeSpy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase,
                                     { target: target, signalName: signalName })
    }

    function test_toolRailKeepsToolAndSwatchObjectNames() {
        const rail = createTemporaryObject(toolRailComponent, testCase,
                                           { width: 74, height: 600 })
        verify(rail !== null)

        const tools = ["select", "pan", "adjust", "filters", "brush",
                       "text", "shapes", "mosaic", "eye", "crop"]
        for (let i = 0; i < tools.length; ++i)
            verify(visualChild(rail, "tool-" + tools[i]) !== null,
                   "missing tool-" + tools[i])

        verify(visualChild(rail, "foreground-swatch") !== null)
    }

    function test_toolRailReportsSelectionWithoutOwningState() {
        const rail = createTemporaryObject(toolRailComponent, testCase,
                                           { width: 74, height: 600,
                                             activeTool: "adjust", hasImage: true })
        verify(rail !== null)
        const spy = makeSpy(rail, "toolSelected")

        visualChild(rail, "tool-brush").clicked()

        compare(rail.activeTool, "adjust", "component must not mutate shell state")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "brush")
    }

    function test_statusBarKeepsObjectNamesAndText() {
        const bar = createTemporaryObject(statusBarComponent, testCase,
                                          { width: 900, hasImage: true,
                                            imageWidth: 640, imageHeight: 480,
                                            objectCount: 1, zoom: 1.0 })
        verify(bar !== null)

        const names = ["status-dimensions", "status-srgb", "status-object-count",
                       "status-zoom-out", "status-zoom-slider", "status-zoom-in",
                       "status-zoom-value", "status-zoom-actual", "status-zoom-fit",
                       "statusMessage"]
        for (let i = 0; i < names.length; ++i)
            verify(visualChild(bar, names[i]) !== null, "missing " + names[i])

        compare(visualChild(bar, "status-dimensions").text, "640 × 480 px")
        compare(visualChild(bar, "status-object-count").text, "1 object")
        compare(visualChild(bar, "statusMessage").text, "Local editing")
    }

    function test_statusBarReportsZoomGestures() {
        const bar = createTemporaryObject(statusBarComponent, testCase,
                                          { width: 900, hasImage: true, zoom: 1.0 })
        verify(bar !== null)
        const outSpy = makeSpy(bar, "zoomOutRequested")
        const inSpy = makeSpy(bar, "zoomInRequested")

        visualChild(bar, "status-zoom-out").clicked()
        visualChild(bar, "status-zoom-in").clicked()

        compare(outSpy.count, 1)
        compare(inSpy.count, 1)
    }

    function test_toolInfoPanelRendersToolGuidance() {
        const panel = createTemporaryObject(toolInfoPanelComponent, testCase, {
            width: 292,
            title: "Pan",
            hint: "Drag the canvas",
            iconName: "pan",
            shortcut: "H",
            shortcutLabel: "Keyboard shortcuts"
        })
        verify(panel !== null)
        compare(panel.title, "Pan")
        compare(panel.hint, "Drag the canvas")
        compare(panel.shortcut, "H")
        compare(panel.shortcutLabel, "Keyboard shortcuts")
    }

    function test_topActionBarKeepsActionObjectNames() {
        const bar = createTemporaryObject(topActionBarComponent, testCase, {
            width: 900,
            actions: ({
                open: openAction,
                undo: undoAction,
                redo: redoAction,
                rotate: rotateAction,
                crop: cropAction,
                save: saveAction,
                saveAs: saveAsAction,
                canvasSize: canvasSizeAction
            })
        })
        verify(bar !== null)

        verify(visualChild(bar, "action-transform") !== null)
        verify(visualChild(bar, "action-canvas") !== null)
        verify(visualChild(bar, "settingsButton") !== null)
        compare(visualChild(bar, "action-canvas").enabled, canvasSizeAction.enabled)
    }
}
