import QtQuick
import QtTest
import ".."

TestCase {
    name: "Window"
    QtObject {
        id: editor
        property string fileName: ""
        property url imageUrl: ""
        property bool busy: false
        property string errorMessage: ""
        property bool hasImage: false
        property int imageWidth: 0
        property int imageHeight: 0
        property bool dirty: false
        property bool adjustmentInteractive: false
        property string adjustmentCall: ""
        property var readableImagePatterns: ["*.png", "*.PNG"]
        signal errorChanged()
        function openImage(url) {}
        function saveImage() {}
        function saveAs(url, format) {}
        function clearError() {}
        function beginAdjustment(key) { adjustmentCall = "begin:" + key }
        function previewAdjustment(key, value) { adjustmentCall = "preview:" + key + ":" + value }
        function finishAdjustment(key, value) { adjustmentCall = "finish:" + key + ":" + value }
    }
    function test_initialState() {
        let component = Qt.createComponent("../Main.qml")
        compare(component.status, Component.Ready, component.errorString())
        let window = component.createObject(null)
        verify(window !== null, component.errorString())
        compare(window.title, "NekoPic")
        window.darkTheme = true
        verify(window.darkTheme)
        window.darkTheme = false
        verify(!window.darkTheme)
        window.destroy()
    }
    function test_adjustmentsConnected() {
        let component = Qt.createComponent("../Main.qml")
        let window = component.createObject(null)
        verify(window !== null, component.errorString())
        let inspector = findChild(window, "inspector")
        verify(inspector !== null)
        editor.hasImage = true
        verify(inspector.adjustmentsEnabled)
        inspector.adjustmentStarted("exposure")
        compare(editor.adjustmentCall, "begin:exposure")
        inspector.adjustmentPreview("exposure", 35)
        compare(editor.adjustmentCall, "preview:exposure:35")
        inspector.adjustmentFinished("exposure", 35)
        compare(editor.adjustmentCall, "finish:exposure:35")
        editor.hasImage = false
        window.destroy()
    }
}
