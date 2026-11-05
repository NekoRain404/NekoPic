import QtQuick
import "../UI"

/*!
    ShapeOverlay — drag-to-draw gesture layer for the shape tool.

    Place this over the displayed image rectangle (anchored to the picture,
    like CropOverlay / MosaicOverlay / EyedropperOverlay). Local display
    pixels map to document/image pixels through the actual display size, so
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
      • shapeKind:    "rectangle" | "ellipse" | "line" | "arrow"
      • fillColor, strokeColor, strokeWidth, cornerRadius, filled
        These describe the shape the integrator will create; the preview uses
        `filled` and `fillColor` for closed shapes and `strokeWidth` for
        line/arrow thickness. Only the kind and geometry travel in the signal,
        so the integration passes the remaining properties to
        `editor.addShape(...)`.

    Signals:
      • shapeCommitted(string kind, rect area) — exactly one call per completed
        drag. `area` is in document image pixels and is normalised: for
        line/arrow its topLeft→bottomRight diagonal is the drawn segment,
        matching DocumentController::addShape's contract.
      • cancelled() — Esc.

    Read-only state:
      • dragging        — true while a gesture is in progress.
      • anchorPoint     — drag origin in image pixels.
      • currentPoint    — constrained drag end in image pixels.
      • previewRect     — normalised preview in image pixels; empty when idle.
      • shiftConstrained— true while the current drag honours Shift.

    Functions:
      • pointAt(x, y)  — display coordinates → clamped image pixels.
      • displayPoint(imageX, imageY) — image pixels → display pixels.
      • reset()        — discard the in-progress gesture and clear the preview.

    # Interaction

      • left drag      draw a preview (accent outline, translucent fill).
      • Shift          rectangle/ellipse become square; line/arrow snap to the
                       nearest 45° step (matching ShapeGeometry).
      • release        emit one shapeCommitted with the clamped image rect.
                       A drag shorter than two display pixels, or one that
                       produces a zero-width/height rect, is discarded because
                       addShape rejects degenerate rects.
      • Esc            discard the gesture and emit cancelled().
      • middle / wheel are deliberately left unaccepted and reach the canvas
                       pan / zoom handlers underneath.
      • inactive / disabled overlays ignore every pointer event.

    # Clamping

    Both drag endpoints are clamped to [0, imageWidth] x [0, imageHeight].
    The Shift square is shrunk at image edges so it stays square and inside
    the image; the 45° endpoint is clamped after snapping.

    # Notes

    The preview draws the normalised topLeft→bottomRight diagonal for
    line/arrow because `addShape` normalises its rect. An arrow therefore
    always points from the top-left corner of the drag bounds to the
    bottom-right corner.
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
    property string shapeKind: "rectangle"
    property color fillColor: Theme.accent
    property color strokeColor: Theme.textPrimary
    property real strokeWidth: 4
    property real cornerRadius: 0
    property bool filled: true

    signal shapeCommitted(string kind, rect area)
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

    // ── Exposed gesture state ───────────────────────────────────────────────
    readonly property bool dragging: _drawing
    readonly property point anchorPoint: _anchor
    readonly property point currentPoint: _current
    readonly property rect previewRect: _computePreviewRect()
    readonly property bool shiftConstrained: _shift

    // ── Internal gesture state ──────────────────────────────────────────────
    property point _anchor: Qt.point(0, 0)
    property point _current: Qt.point(0, 0)
    property bool _drawing: false
    property bool _shift: false

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Shape drawing")
    Accessible.description: qsTr("Drag on the image to draw a shape. "
                                 + "Hold Shift to constrain it. Press Escape to cancel.")
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

    /*! Falls back to rectangle for an unknown kind. */
    function normalizedKind() {
        return shapeKind === "ellipse" || shapeKind === "line" || shapeKind === "arrow"
                ? shapeKind : "rectangle"
    }

    function _emptyRect() {
        return Qt.rect(0, 0, 0, 0)
    }

    /*!
        Applies the Shift constraint (square or 45° snap) and clamps the
        endpoint to the image. `constrain` is false for an unconstrained drag.
    */
    function _constrainPoint(anchor, current, constrain) {
        const end = Qt.point(_clamp(current.x, 0, imageWidth),
                             _clamp(current.y, 0, imageHeight))
        if (!constrain)
            return end

        const kind = normalizedKind()
        if (kind === "rectangle" || kind === "ellipse") {
            const dx = end.x - anchor.x
            const dy = end.y - anchor.y
            const signX = dx < 0 ? -1 : 1
            const signY = dy < 0 ? -1 : 1
            // ShapeGeometry::squareFromDrag semantics: the longer drag axis
            // sets the side, then the square is shrunk to stay in the image.
            const maxSideX = signX > 0 ? imageWidth - anchor.x : anchor.x
            const maxSideY = signY > 0 ? imageHeight - anchor.y : anchor.y
            const side = Math.max(0, Math.min(Math.max(Math.abs(dx), Math.abs(dy)),
                                             maxSideX, maxSideY))
            return Qt.point(anchor.x + signX * side, anchor.y + signY * side)
        }

        // ShapeGeometry::snapToAngle(anchor, current, 45): keep the length,
        // rotate the vector to the nearest 45° step.
        const dx = end.x - anchor.x
        const dy = end.y - anchor.y
        const radius = Math.hypot(dx, dy)
        if (!(radius > 0))
            return end
        const step = Math.PI / 4
        const angle = Math.round(Math.atan2(dy, dx) / step) * step
        const snappedX = anchor.x + radius * Math.cos(angle)
        const snappedY = anchor.y + radius * Math.sin(angle)
        return Qt.point(_clamp(snappedX, 0, imageWidth),
                        _clamp(snappedY, 0, imageHeight))
    }

    function _computePreviewRect() {
        if (!_drawing)
            return _emptyRect()
        return Qt.rect(Math.min(_anchor.x, _current.x),
                       Math.min(_anchor.y, _current.y),
                       Math.abs(_current.x - _anchor.x),
                       Math.abs(_current.y - _anchor.y))
    }

    /*! Discards the in-progress gesture; does not emit cancelled(). */
    function reset() {
        _drawing = false
        _anchor = Qt.point(0, 0)
        _current = Qt.point(0, 0)
        _shift = false
        preview.requestPaint()
    }

    // ── Gesture handling ────────────────────────────────────────────────────
    function _press(mouse) {
        if (!usable)
            return false
        forceActiveFocus(Qt.MouseFocusReason)
        _anchor = pointAt(mouse.x, mouse.y)
        _shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
        _current = _constrainPoint(_anchor, _anchor, _shift)
        _drawing = true
        preview.requestPaint()
        return true
    }

    function _move(mouse) {
        if (!_drawing || !usable)
            return
        _shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
        _current = _constrainPoint(_anchor, pointAt(mouse.x, mouse.y), _shift)
        preview.requestPaint()
    }

    function _release(mouse) {
        if (!_drawing)
            return
        if (!usable) {
            reset()
            return
        }
        _shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
        _current = _constrainPoint(_anchor, pointAt(mouse.x, mouse.y), _shift)
        const kind = normalizedKind()
        const area = _computePreviewRect()
        // Copy the geometry before reset() clears the gesture state.
        const dragged = Math.hypot((_current.x - _anchor.x) * scaleX,
                                   (_current.y - _anchor.y) * scaleY)
        reset()
        // addShape rejects rects without a positive width and height, and a
        // sub-2px display drag is a click rather than a deliberate draw.
        if (dragged < 2 || !(area.width > 0) || !(area.height > 0))
            return
        root.shapeCommitted(kind, area)
    }

    function _cancel() {
        if (!usable)
            return
        reset()
        root.cancelled()
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────
    onActiveChanged: {
        reset()
        if (active)
            forceActiveFocus(Qt.OtherFocusReason)
    }
    onUsableChanged: if (!usable) reset()
    onWidthChanged: preview.requestPaint()
    onHeightChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()
    onViewScaleChanged: preview.requestPaint()
    onImageWidthChanged: preview.requestPaint()
    onImageHeightChanged: preview.requestPaint()
    onShapeKindChanged: preview.requestPaint()
    onFilledChanged: preview.requestPaint()
    onFillColorChanged: preview.requestPaint()
    onStrokeColorChanged: preview.requestPaint()
    onStrokeWidthChanged: preview.requestPaint()
    onCornerRadiusChanged: preview.requestPaint()

    Keys.onEscapePressed: function(event) {
        if (usable) {
            _cancel()
            event.accepted = true
        }
    }

    // ── Viewport-backed drawing ─────────────────────────────────────────────
    Canvas {
        id: preview
        objectName: "shapePreview"
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
            const c = getContext("2d")
            c.reset()
            if (!root.usable || !root.dragging)
                return
            c.translate(-x, -y)

            const kind = root.normalizedKind()
            const a = root.displayPoint(root.anchorPoint.x, root.anchorPoint.y)
            const b = root.displayPoint(root.currentPoint.x, root.currentPoint.y)

            const outline = function(drawPath) {
                drawPath()
                c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
                c.lineWidth = 3
                c.stroke()
                drawPath()
                c.strokeStyle = Theme.accent
                c.lineWidth = 1
                c.stroke()
            }

            if (kind === "rectangle" || kind === "ellipse") {
                const left = Math.min(a.x, b.x)
                const top = Math.min(a.y, b.y)
                const w = Math.abs(b.x - a.x)
                const h = Math.abs(b.y - a.y)
                if (!(w > 0) || !(h > 0))
                    return

                const displayScale = Math.min(root.scaleX, root.scaleY)
                const radius = kind === "rectangle"
                        ? Math.min(root.cornerRadius * displayScale,
                                   Math.min(w, h) / 2)
                        : 0

                const path = function() {
                    c.beginPath()
                    if (kind === "ellipse") {
                        c.ellipse(left, top, w, h)
                    } else if (radius > 0.01) {
                        c.moveTo(left + radius, top)
                        c.lineTo(left + w - radius, top)
                        c.arcTo(left + w, top, left + w, top + radius, radius)
                        c.lineTo(left + w, top + h - radius)
                        c.arcTo(left + w, top + h, left + w - radius, top + h, radius)
                        c.lineTo(left + radius, top + h)
                        c.arcTo(left, top + h, left, top + h - radius, radius)
                        c.lineTo(left, top + radius)
                        c.arcTo(left, top, left + radius, top, radius)
                        c.closePath()
                    } else {
                        c.rect(left, top, w, h)
                    }
                }

                if (root.filled) {
                    path()
                    c.fillStyle = Theme.alpha(root.fillColor, 0.30)
                    c.fill()
                }
                outline(path)
                return
            }

            // Line and arrow preview the normalised topLeft→bottomRight
            // diagonal that addShape will store, so the preview is truthful.
            const r = root.previewRect
            const start = root.displayPoint(r.x, r.y)
            const end = root.displayPoint(r.x + r.width, r.y + r.height)
            const dx = end.x - start.x
            const dy = end.y - start.y
            const length = Math.hypot(dx, dy)
            if (!(length > 0.01))
                return

            const displayScale = Math.min(root.scaleX, root.scaleY)
            const lineWidth = Math.max(1, Math.min(8, root.strokeWidth * displayScale))
            const line = function() {
                c.beginPath()
                c.moveTo(start.x, start.y)
                c.lineTo(end.x, end.y)
            }

            c.lineCap = "round"
            line()
            c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
            c.lineWidth = lineWidth + 2
            c.stroke()
            line()
            c.strokeStyle = Theme.accent
            c.lineWidth = lineWidth
            c.stroke()

            if (kind === "arrow") {
                const ux = dx / length
                const uy = dy / length
                const head = Math.min(length, Math.max(8, Math.min(24, length * 0.28)))
                const half = Math.max(head * 0.5, lineWidth * 1.2)
                const baseX = end.x - ux * head
                const baseY = end.y - uy * head
                c.beginPath()
                c.moveTo(end.x, end.y)
                c.lineTo(baseX - uy * half, baseY + ux * half)
                c.lineTo(baseX + uy * half, baseY - ux * half)
                c.closePath()
                c.fillStyle = Theme.accent
                c.fill()
            }
        }
    }

    // Visible focus indicator for keyboard users.
    Rectangle {
        objectName: "shapeFocusRing"
        anchors.fill: preview
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.usable
    }

    MouseArea {
        id: pointer
        objectName: "shapePointer"
        anchors.fill: parent
        enabled: root.usable
        // Middle button is intentionally absent so canvas panning wins.
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.CrossCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onPressed: function(mouse) {
            if (root._press(mouse))
                mouse.accepted = true
        }
        onPositionChanged: function(mouse) { root._move(mouse) }
        onReleased: function(mouse) { root._release(mouse) }
        onCanceled: root.reset()
    }

    Connections {
        target: Theme
        function onDarkChanged() { preview.requestPaint() }
    }
}
