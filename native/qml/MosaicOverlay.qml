import QtQuick

// Place over the displayed image rectangle, excluding letterboxing and borders.
// Signals use image pixels: x = localX * imageWidth / width (and likewise y).
// Coordinates are clipped to [0, imageWidth] / [0, imageHeight]; rectangles
// describe continuous pixel edges, and stroke points are pixel-space centers.
// brushDiameter is in image pixels. viewScale supplies the default display size;
// actual width/height control mapping when the parent supplies rounded dimensions.
Item {
    id: root
    property bool active: false
    property bool brushMode: true
    property real brushDiameter: 24
    property int imageWidth: 0
    property int imageHeight: 0
    property real viewScale: 1
    property bool inputEnabled: true
    // Viewport in this item's display coordinates. Keep the raster backing
    // bounded to its visible intersection, even when the image item is huge.
    property rect visibleRect: Qt.rect(0, 0, width, height)
    signal rectangleCommitted(rect area)
    signal strokeCommitted(var points)

    width: imageWidth * viewScale
    height: imageHeight * viewScale
    clip: true

    readonly property bool usable: active && inputEnabled && imageWidth > 0
                                   && imageHeight > 0 && width > 0 && height > 0
    property bool _drawing: false
    property point _start: Qt.point(0, 0)
    property point _end: Qt.point(0, 0)
    property point _cursor: Qt.point(0, 0)
    property var _points: []
    property real _sampleDistance: 1

    function imagePoint(x, y) {
        return Qt.point(Math.max(0, Math.min(imageWidth, x * imageWidth / width)),
                        Math.max(0, Math.min(imageHeight, y * imageHeight / height)))
    }
    function cancelGesture() {
        _drawing = false
        _points = []
        mask.requestPaint()
    }
    function appendPoint(point, finalPoint) {
        const last = _points[_points.length - 1]
        const distance = Math.hypot(point.x - last.x, point.y - last.y)
        if (distance === 0 || (!finalPoint && distance < _sampleDistance))
            return
        if (_points.length >= 4096) {
            // Coarsen an exceptionally long stroke rather than drop its tail.
            const reduced = []
            for (let i = 0; i < _points.length; i += 2)
                reduced.push(_points[i])
            _points = reduced
            _sampleDistance *= 2
        }
        _points.push(point)
    }
    onUsableChanged: if (!usable) cancelGesture()
    onBrushModeChanged: cancelGesture()
    onImageWidthChanged: cancelGesture()
    onImageHeightChanged: cancelGesture()
    onWidthChanged: mask.requestPaint()
    onHeightChanged: mask.requestPaint()
    onBrushDiameterChanged: mask.requestPaint()
    Keys.onEscapePressed: function(event) {
        if (_drawing) {
            cancelGesture()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    Canvas {
        id: mask
        objectName: "mosaicPreview"
        x: Math.max(0, Math.min(root.width, root.visibleRect.x))
        y: Math.max(0, Math.min(root.height, root.visibleRect.y))
        width: Math.max(0, Math.min(root.width, root.visibleRect.x + root.visibleRect.width) - x)
        height: Math.max(0, Math.min(root.height, root.visibleRect.y + root.visibleRect.height) - y)
        visible: root.usable
        onXChanged: requestPaint()
        onYChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.usable)
                return
            ctx.translate(-x, -y)
            ctx.scale(root.width / root.imageWidth, root.height / root.imageHeight)
            const lineWidth = root.imageWidth / root.width
            if (root._drawing && root.brushMode && root._points.length) {
                ctx.strokeStyle = "#80edbc9d"
                ctx.fillStyle = "#80edbc9d"
                ctx.lineWidth = Math.max(1, root.brushDiameter)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(root._points[0].x, root._points[0].y)
                for (let i = 1; i < root._points.length; ++i)
                    ctx.lineTo(root._points[i].x, root._points[i].y)
                if (root._points.length > 1) {
                    ctx.stroke()
                } else {
                    ctx.arc(root._points[0].x, root._points[0].y,
                            Math.max(1, root.brushDiameter) / 2, 0, Math.PI * 2)
                    ctx.fill()
                }
            } else if (root._drawing) {
                const x = Math.min(root._start.x, root._end.x)
                const y = Math.min(root._start.y, root._end.y)
                const w = Math.abs(root._end.x - root._start.x)
                const h = Math.abs(root._end.y - root._start.y)
                ctx.fillStyle = "#40edbc9d"
                ctx.fillRect(x, y, w, h)
                ctx.strokeStyle = "#edbc9d"
                ctx.lineWidth = lineWidth
                ctx.strokeRect(x, y, w, h)
            }
            if (pointer.containsMouse && root.brushMode) {
                ctx.beginPath()
                ctx.arc(root._cursor.x, root._cursor.y,
                        Math.max(1, root.brushDiameter) / 2, 0, Math.PI * 2)
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = lineWidth
                ctx.stroke()
            }
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.usable
        // The canvas underneath owns middle-button pan and all wheel events.
        acceptedButtons: Qt.LeftButton
        hoverEnabled: root.active
        preventStealing: true
        cursorShape: root.brushMode ? Qt.BlankCursor : Qt.CrossCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onContainsMouseChanged: mask.requestPaint()
        onPressed: function(mouse) {
            root.forceActiveFocus(Qt.MouseFocusReason)
            root._start = root.imagePoint(mouse.x, mouse.y)
            root._end = root._start
            root._cursor = root._start
            root._points = [root._start]
            root._sampleDistance = Math.max(0.75, root.brushDiameter * 0.1)
            root._drawing = true
            mask.requestPaint()
        }
        onPositionChanged: function(mouse) {
            root._cursor = root.imagePoint(mouse.x, mouse.y)
            if (root._drawing) {
                root._end = root._cursor
                if (root.brushMode)
                    root.appendPoint(root._end, false)
            }
            mask.requestPaint()
        }
        onReleased: function(mouse) {
            if (!root._drawing)
                return
            root._end = root.imagePoint(mouse.x, mouse.y)
            if (root.brushMode) {
                root.appendPoint(root._end, true)
                const points = root._points.slice()
                root.cancelGesture()
                root.strokeCommitted(points)
            } else {
                const area = Qt.rect(Math.min(root._start.x, root._end.x),
                                     Math.min(root._start.y, root._end.y),
                                     Math.abs(root._end.x - root._start.x),
                                     Math.abs(root._end.y - root._start.y))
                // Require a deliberate drag of at least two display pixels
                // and at least one image pixel along each axis.
                const deliberate = area.width >= Math.max(1, 2 * root.imageWidth / root.width)
                                   && area.height >= Math.max(1, 2 * root.imageHeight / root.height)
                root.cancelGesture()
                if (deliberate)
                    root.rectangleCommitted(area)
            }
        }
        onCanceled: root.cancelGesture()
    }
}
