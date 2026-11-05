import QtQuick
import "../UI"

/*!
    PolygonOverlay — click-to-place polygon tool.

    Click adds a vertex in image pixels; moving shows a rubber-band edge.
    Enter (or clicking near the first vertex with >=3 points) closes the
    polygon and emits one polygonCommitted(points). Backspace removes the last
    vertex; Esc cancels. Middle button and wheel pass through to pan/zoom.
    Rendering is viewport-backed and never allocates an image-sized Canvas.
*/
Item {
    id: root

    property bool active: false
    property bool inputEnabled: true
    property int imageWidth: 0
    property int imageHeight: 0
    property real viewScale: 1
    property rect visibleRect: Qt.rect(0, 0, width, height)
    property color fillColor: Theme.accent
    property color strokeColor: Theme.textPrimary
    property real strokeWidth: 3
    property bool filled: true

    signal polygonCommitted(var points)
    signal cancelled()

    width: imageWidth * viewScale
    height: imageHeight * viewScale
    clip: true
    visible: active
    enabled: active && inputEnabled
    focus: active

    property var points: []
    property point cursor: Qt.point(0, 0)
    readonly property real scaleX: imageWidth > 0 ? width / imageWidth : 1
    readonly property real scaleY: imageHeight > 0 ? height / imageHeight : 1
    readonly property bool usable: active && inputEnabled && imageWidth > 0
                                   && imageHeight > 0 && width > 0 && height > 0

    function pointAt(x, y) {
        return Qt.point(Math.max(0, Math.min(imageWidth, x / Math.max(scaleX, 0.0001))),
                        Math.max(0, Math.min(imageHeight, y / Math.max(scaleY, 0.0001))))
    }
    function displayPoint(ix, iy) { return Qt.point(ix * scaleX, iy * scaleY) }
    function reset() { points = []; cursor = Qt.point(0, 0); preview.requestPaint() }
    function cancel() { reset(); cancelled() }
    function finish() {
        if (!usable || points.length < 3) return
        const copy = points.slice()
        reset()
        polygonCommitted(copy)
    }
    function removeLast() {
        if (points.length === 0) return
        const copy = points.slice(0, points.length - 1)
        points = copy
        preview.requestPaint()
    }
    function addPoint(point) {
        if (points.length >= 256) return
        const copy = points.slice()
        copy.push(point)
        points = copy
        preview.requestPaint()
    }
    function nearFirst(displayPoint) {
        if (points.length < 3) return false
        const first = root.displayPoint(points[0].x, points[0].y)
        return Math.hypot(first.x - displayPoint.x, first.y - displayPoint.y) <= 14
    }

    onActiveChanged: if (!active) reset()
    onPointsChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()

    Keys.onReturnPressed: function(event) { finish(); event.accepted = true }
    Keys.onEnterPressed: function(event) { finish(); event.accepted = true }
    Keys.onEscapePressed: function(event) { cancel(); event.accepted = true }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Backspace) {
            removeLast()
            event.accepted = true
        }
    }

    Canvas {
        id: preview
        objectName: "polygonPreview"
        x: Math.max(0, root.visibleRect.x)
        y: Math.max(0, root.visibleRect.y)
        width: Math.max(0, Math.min(root.width - x, root.visibleRect.width))
        height: Math.max(0, Math.min(root.height - y, root.visibleRect.height))
        visible: root.usable
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (root.points.length === 0) return
            const dx = -x, dy = -y
            ctx.beginPath()
            for (let i = 0; i < root.points.length; ++i) {
                const p = root.displayPoint(root.points[i].x, root.points[i].y)
                if (i === 0) ctx.moveTo(p.x + dx, p.y + dy)
                else ctx.lineTo(p.x + dx, p.y + dy)
            }
            if (root.points.length >= 3) {
                const first = root.displayPoint(root.points[0].x, root.points[0].y)
                ctx.lineTo(first.x + dx, first.y + dy)
                if (root.filled) {
                    ctx.fillStyle = Theme.alpha(root.fillColor, 0.25)
                    ctx.fill()
                }
            }
            const last = root.displayPoint(root.points[root.points.length - 1].x,
                                           root.points[root.points.length - 1].y)
            const cur = root.displayPoint(root.cursor.x, root.cursor.y)
            if (root.points.length > 0) {
                ctx.moveTo(last.x + dx, last.y + dy)
                ctx.lineTo(cur.x + dx, cur.y + dy)
            }
            ctx.strokeStyle = root.strokeColor
            ctx.lineWidth = Math.max(1, root.strokeWidth * root.scaleX * 0.5)
            ctx.lineJoin = "round"
            ctx.stroke()
            ctx.fillStyle = Theme.accent
            for (let i = 0; i < root.points.length; ++i) {
                const p = root.displayPoint(root.points[i].x, root.points[i].y)
                ctx.beginPath()
                ctx.arc(p.x + dx, p.y + dy, i === 0 ? 4 : 3, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.enabled
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.enabled
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        onPositionChanged: function(mouse) {
            root.cursor = root.pointAt(mouse.x, mouse.y)
            preview.requestPaint()
        }
        onClicked: function(mouse) {
            root.forceActiveFocus()
            if (root.nearFirst(Qt.point(mouse.x, mouse.y))) {
                root.finish()
                return
            }
            root.addPoint(root.pointAt(mouse.x, mouse.y))
        }
    }
}
