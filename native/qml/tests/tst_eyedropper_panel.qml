import QtQuick
import QtTest
import "../panels"
import "../UI"

TestCase {
    id: testCase
    name: "EyedropperPanel"
    when: windowShown
    width: 340
    height: 620

    EyedropperPanel {
        id: panel
        x: 20
        y: 20
        width: 292
        height: 580
    }

    SignalSpy { id: copies; target: panel; signalName: "copyRequested" }

    function init() {
        Theme.dark = true
        Theme.reduceMotion = true
        panel.colorValue = "#eeb99a"
        panel.hasSample = false
        panel.samplePosition = Qt.point(0, 0)
        copies.clear()
    }

    function test_valuesAreDerivedFromSample() {
        panel.colorValue = "#ff0000"
        panel.hasSample = true
        compare(panel.hexText(), "#FF0000")
        compare(panel.rgbText(), "255, 0, 0")
        compare(panel.hslText(), "0°, 100%, 50%")

        panel.colorValue = "#336699"
        compare(panel.hexText(), "#336699")
        compare(panel.rgbText(), "51, 102, 153")

        panel.hasSample = false
        // The swatch is disabled by the UI; conversion helpers stay pure.
        compare(panel.hexText(), "#336699")
    }

    function test_copyEmitsHexOnlyWithSample() {
        panel.hasSample = false
        panel.copyHex()
        compare(copies.count, 0)

        panel.colorValue = "#123456"
        panel.hasSample = true
        panel.copyHex()
        compare(copies.count, 1)
        compare(copies.signalArguments[0][0], "#123456")
    }

    function test_positionAndLayoutStayInsidePanel() {
        panel.hasSample = true
        panel.samplePosition = Qt.point(123.4, 56.7)
        compare(panel.implicitWidth <= 340, true)
        verify(panel.height <= 620)
        compare(panel.width, 292)
    }
}
