import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "MosaicPanelControls"
    when: windowShown
    visible: true
    width: 320; height: 600
    Loader {
        id: panelLoader
        width: 292; height: 580
        source: "../MosaicPanel.qml"
    }
    property var panel: panelLoader.item
    function initTestCase() {
        compare(panelLoader.status, Loader.Ready)
    }
    function init() {
        panel.enabled = true
        panel.brushMode = true
        panel.brushDiameter = 24
        panel.blockSize = 12
    }
    function test_modeAndImagePixelParameters() {
        mouseClick(findChild(panel, "mosaic-mode-rectangle"))
        verify(!panel.brushMode)
        mouseClick(findChild(panel, "mosaic-mode-brush"))
        verify(panel.brushMode)
        const diameter = findChild(panel, "mosaic-brush-diameter")
        diameter.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.brushDiameter, 25)
        const blockSize = findChild(panel, "mosaic-block-size")
        blockSize.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(panel.blockSize, 13)
    }
    function test_parametersStayWithinSupportedBounds() {
        const diameter = findChild(panel, "mosaic-brush-diameter")
        mouseClick(diameter, 0, diameter.height / 2)
        compare(panel.brushDiameter, 4)
        mouseClick(diameter, diameter.width - 1, diameter.height / 2)
        compare(panel.brushDiameter, 512)
        const blockSize = findChild(panel, "mosaic-block-size")
        mouseClick(blockSize, 0, blockSize.height / 2)
        compare(panel.blockSize, 2)
        mouseClick(blockSize, blockSize.width - 1, blockSize.height / 2)
        compare(panel.blockSize, 128)
    }
    function test_busyLockDisablesModeAndParameters() {
        panel.enabled = false
        const mode = findChild(panel, "mosaic-mode-rectangle")
        const diameter = findChild(panel, "mosaic-brush-diameter")
        const blockSize = findChild(panel, "mosaic-block-size")
        verify(!mode.enabled)
        verify(!diameter.enabled)
        verify(!blockSize.enabled)
        mouseClick(mode)
        verify(panel.brushMode)
        compare(panel.brushDiameter, 24)
        compare(panel.blockSize, 12)
    }
}
