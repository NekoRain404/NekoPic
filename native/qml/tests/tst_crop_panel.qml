import QtQuick
import QtTest
import ".."

TestCase {
    name: "CropPanel"
    when: windowShown
    visible: true; width: 360; height: 650
    QtObject {
        id: theme
        property color panel: "#222426"; property color text: "#e9e9e6"
        property color muted: "#929794"; property color accent: "#edbc9d"
        property color raised: "#2b2d2f"; property color hover: "#343638"
        property color background: "#181a1b"; property color border: "#343638"
        property color accentInk: "#292420"
    }
    function test_ratiosOrientationAndActions() {
        const component = Qt.createComponent("../CropPanel.qml")
        compare(component.status, Component.Ready, component.errorString())
        const panel = createTemporaryObject(component, this, {theme: theme, width: 292, height: 600})
        verify(panel !== null)
        panel.imageAspectRatio = 2
        verify(waitForRendering(panel))
        const applies = createTemporaryObject(spyComponent, this, {target: panel, signalName: "applyRequested"})
        const cancels = createTemporaryObject(spyComponent, this, {target: panel, signalName: "cancelRequested"})
        const resets = createTemporaryObject(spyComponent, this, {target: panel, signalName: "resetRequested"})
        mouseClick(findChild(panel, "crop-ratio-square"))
        compare(panel.aspectRatio, 1)
        mouseClick(findChild(panel, "crop-ratio-original"))
        compare(panel.aspectRatio, 2)
        mouseClick(findChild(panel, "crop-swap"))
        compare(panel.aspectRatio, 0.5)
        const apply = findChild(panel, "crop-apply")
        verify(!apply.enabled)
        panel.canApply = true
        mouseClick(apply)
        compare(applies.count, 1)
        mouseClick(findChild(panel, "crop-reset"))
        compare(resets.count, 1)
        mouseClick(findChild(panel, "crop-cancel"))
        compare(cancels.count, 1)
    }
    Component { id: spyComponent; SignalSpy {} }
}
