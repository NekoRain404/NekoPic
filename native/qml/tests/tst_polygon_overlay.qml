import QtQuick
import QtTest
import ".."
import "../overlays"

TestCase {
    id: testCase
    name: "PolygonOverlay"
    when: windowShown
    visible: true
    width: 640
    height: 480

    Item {
        id: host
        width: 400
        height: 300
        PolygonOverlay {
            id: polygon
            anchors.fill: parent
            active: true
            imageWidth: 400
            imageHeight: 300
            viewScale: 1
            visibleRect: Qt.rect(0, 0, width, height)
        }
    }
    SignalSpy { id: committed; target: polygon; signalName: "polygonCommitted" }
    SignalSpy { id: cancelledSpy; target: polygon; signalName: "cancelled" }

    function init() {
        polygon.points = []
        polygon.active = true
        committed.clear()
        cancelledSpy.clear()
    }

    function test_clickEnterEmitsPolygon() {
        mouseClick(polygon, 40, 40)
        mouseClick(polygon, 160, 40)
        mouseClick(polygon, 160, 140)
        compare(polygon.points.length, 3)
        polygon.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(committed.count, 1)
        const points = committed.signalArguments[0][0]
        compare(points.length, 3)
        compare(points[1].x, 160)
        compare(points[2].y, 140)
        compare(polygon.points.length, 0)
    }

    function test_backspaceAndEscape() {
        mouseClick(polygon, 20, 20)
        mouseClick(polygon, 120, 20)
        mouseClick(polygon, 120, 120)
        polygon.forceActiveFocus()
        keyClick(Qt.Key_Backspace)
        compare(polygon.points.length, 2)
        keyClick(Qt.Key_Escape)
        compare(cancelledSpy.count, 1)
        compare(polygon.points.length, 0)
    }

    function test_closeNearFirstVertex() {
        mouseClick(polygon, 30, 30)
        mouseClick(polygon, 130, 30)
        mouseClick(polygon, 130, 130)
        mouseClick(polygon, 32, 32)
        compare(committed.count, 1)
        compare(committed.signalArguments[0][0].length, 3)
    }

    function test_needsThreePoints() {
        mouseClick(polygon, 40, 40)
        mouseClick(polygon, 80, 40)
        polygon.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(committed.count, 0)
    }
}
