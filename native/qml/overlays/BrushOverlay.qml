import QtQuick

/*!
    BrushOverlay — freehand brush input and live preview for object strokes.

    Place this over the displayed image rectangle (anchored to the picture,
    like CropOverlay / MosaicOverlay / TextPlacementOverlay). Local display
    pixels map to document image pixels through the actual display size, so
    it stays correct for any zoom:

        imageX = localX * imageWidth / width
        imageY = localY * imageHeight / height

    `visibleRect` is the viewport in this item's local coordinates. Drawing is
    viewport-backed: the preview Canvas only covers the intersection of the
    viewport and the image, so a very large image at high zoom never allocates
    an image-sized raster.

    # Public contract

    Properties:
      • active, inputEnabled, imageWidth, imageHeight, viewScale, visibleRect
      • diameter — brush width in image pixels (the controller clamps 1–512)
      • color    — stroke ink; invalid values are the controller's concern

    Signals:
      • strokeCommitted(var points) — exactly once per completed gesture.
        Points are image-pixel centers, clamped to the image and sampled with
        a minimum-distance filter. The list never exceeds 4096 points.
      • cancelled() — Esc pressed while the overlay is usable.

    Functions:
      • pointAt(x, y) — display coordinates → clamped image pixels.
      • displayPoint(imageX, imageY) — image pixels → local display pixels.
      • reset() — drop the in-progress stroke without emitting anything.

    Read-only:
      • usable, drawing, sampleCount, sampleDistance.

    # Interaction (active && inputEnabled)

      • left drag   samples points and shows a semi-transparent round-capped
                    preview; release commits one stroke and clears the preview.
      • Esc         cancels the gesture without emitting strokeCommitted and
                    emits cancelled().
      • middle / wheel are deliberately left unaccepted and reach the canvas
        pan / zoom handlers underneath.

    A single click commits a one-point list (the controller renders it as a
    round dot). Points are always kept inside [0, imageWidth] x [0, imageHeight].

    # Sampling

    The distance filter is max(1 image px, diameter * 0.15), so large brushes
    do not produce dense point clouds. When the 4096 sample budget is reached,
    the existing points are decimated (every other sample) and the threshold
    doubles; the stroke tail is never dropped.
*/
Item {
    id: root

    // ── Public contract ─────────────────────────────────────────────────────
    property bool active: false
    property bool inputEnabled: true
    property int imageWidth: 0
    property int imageHeight: 0
    /*! Display scale used by the parent; width/height remain authoritative. */
    property real viewScale: 1
    /*! Viewport in this item's local display coordinates. */
    property rect visibleRect: Qt.rect(0, 0, width, height)
    /*! Brush diameter in image pixels. */
    property real diameter: 24
    /*! Brush ink. */
    property color color: "#000000"

    signal strokeCommitted(var points)
    signal cancelled()

    // ── Geometry / enablement ───────────────────────────────────────────────
    width: imageWidth * viewScale
    height: imageHeight * viewScale
    clip: true
    visible: active
    enabled: active && inputEnabled
    focus: active

    readonly property real scaleX: imageWidth > 0 ? width / imageWidth : 1
    readonly property real scaleY: imageHeight > 0 ? height / imageHeight : 1
    readonly property bool usable: active && inputEnabled && imageWidth > 0
                                   && imageHeight > 0 && width > 0 && height > 0
    /*! True while a left-button stroke is being sampled. */
    readonly property bool drawing: _drawing
    /*! Number of samples held by the in-progress stroke. */
    readonly property int sampleCount: _pointCount
    /*! Current minimum sample distance in image pixels. */
    readonly property real sampleDistance: _sampleDistance

    // ── Internal gesture state ──────────────────────────────────────────────
    property bool _drawing: false
    property var _points: []
    property int _pointCount: 0
    property real _sampleDistance: 1
    property point _cursor: Qt.point(0, 0)

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Brush")
    Accessible.description: qsTr("Drag on the image to paint a stroke. "
                                 + "Press Escape to cancel.")
    Accessible.focusable: true
    Accessible.focused: activeFocus

    // ── Coordinate mapping ──────────────────────────────────────────────────
    function _clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    /*! Display coordinates (local px) → image pixels, clamped to the image. */
    function pointAt(x, y) {
        if (!isFinite(x) || !isFinite(y))
            return Qt.point(0, 0)
        if (!(scaleX > 0) || !(scaleY > 0))
            return Qt.point(0, 0)
        return Qt.point(_clamp(x / scaleX, 0, imageWidth),
                        _clamp(y / scaleY, 0, imageHeight))
    }

    /*! Image pixels → local display pixels. */
    function displayPoint(imageX, imageY) {
        return Qt.point(imageX * scaleX, imageY * scaleY)
    }

    // ── Sampling ────────────────────────────────────────────────────────────
    function _minimumSampleDistance() {
        return Math.max(1, diameter * 0.15)
    }

    /*! Drops the in-progress stroke and clears the preview. Never emits. */
    function reset() {
        _drawing = false
        _points = []
        _pointCount = 0
        preview.requestPaint()
    }

    function _appendPoint(point, force) {
        // Qt.point value-type objects can alias a property; store a copy so
        // later cursor updates cannot mutate samples already in the path.
        const sample = Qt.point(point.x, point.y)
        if (_points.length === 0) {
            _points = [sample]
            _pointCount = 1
            return
        }
        const last = _points[_points.length - 1]
        const distance = Math.hypot(sample.x - last.x, sample.y - last.y)
        // A release on the press point is a click, not a second sample.
        if (distance === 0)
            return
        if (!force && distance < _sampleDistance)
            return
        if (_points.length >= 4096) {
            // Coarsen an exceptionally long stroke rather than drop its tail.
            const reduced = []
            for (let i = 0; i < _points.length; i += 2)
                reduced.push(_points[i])
            _points = reduced
            _pointCount = reduced.length
            _sampleDistance *= 2
        }
        _points.push(sample)
        _pointCount = _points.length
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────
    onUsableChanged: if (!usable) reset()
    onImageWidthChanged: reset()
    onImageHeightChanged: reset()
    onActiveChanged: {
        reset()
        if (active)
            forceActiveFocus(Qt.OtherFocusReason)
    }
    onWidthChanged: preview.requestPaint()
    onHeightChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()
    onDiameterChanged: preview.requestPaint()
    onColorChanged: preview.requestPaint()

    Keys.onEscapePressed: function(event) {
        if (!usable) {
            event.accepted = false
            return
        }
        reset()
        root.cancelled()
        event.accepted = true
    }

    // ── Viewport-backed live preview ────────────────────────────────────────
    Canvas {
        id: preview
        objectName: "brushPreview"
        // Keep the raster backing bounded to the visible intersection.
        x: Math.max(0, Math.min(root.width, root.visibleRect.x))
        y: Math.max(0, Math.min(root.height, root.visibleRect.y))
        width: Math.max(0, Math.min(root.width, root.visibleRect.x + root.visibleRect.width) - x)
        height: Math.max(0, Math.min(root.height, root.visibleRect.y + root.visibleRect.height) - y)
        visible: root.usable
        onXChanged: requestPaint()
        onYChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.usable || !root._drawing || root._points.length === 0)
                return
            ctx.translate(-x, -y)
            ctx.scale(root.width / root.imageWidth, root.height / root.imageHeight)
            const inkWidth = Math.max(1, root.diameter)
            ctx.strokeStyle = root.color
            ctx.fillStyle = root.color
            // Keep the surface visible over the photograph without hiding it.
            ctx.globalAlpha = 0.65
            ctx.lineWidth = inkWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(root._points[0].x, root._points[0].y)
            for (let i = 1; i < root._points.length; ++i)
                ctx.lineTo(root._points[i].x, root._points[i].y)
            if (root._points.length > 1) {
                ctx.stroke()
            } else {
                ctx.arc(root._points[0].x, root._points[0].y, inkWidth / 2,
                        0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    MouseArea {
        id: pointer
        objectName: "brushPointer"
        anchors.fill: parent
        enabled: root.usable
        // Middle button is intentionally absent so canvas panning wins.
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.BlankCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onPressed: function(mouse) {
            if (!root.usable)
                return
            root.forceActiveFocus(Qt.MouseFocusReason)
            const p = root.pointAt(mouse.x, mouse.y)
            root._sampleDistance = root._minimumSampleDistance()
            root._points = [Qt.point(p.x, p.y)]
            root._pointCount = 1
            root._cursor = Qt.point(p.x, p.y)
            root._drawing = true
            preview.requestPaint()
            mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
            if (!root.usable)
                return
            root._cursor = root.pointAt(mouse.x, mouse.y)
            if (root._drawing) {
                root._appendPoint(root._cursor, false)
                preview.requestPaint()
            }
        }
        onReleased: function(mouse) {
            if (!root.usable || !root._drawing) {
                root.reset()
                return
            }
            root._cursor = root.pointAt(mouse.x, mouse.y)
            root._appendPoint(root._cursor, true)
            // Copy before reset(): the array is stored in a var property.
            const points = root._points.slice()
            root.reset()
            root.strokeCommitted(points)
        }
        onCanceled: root.reset()
    }
}
