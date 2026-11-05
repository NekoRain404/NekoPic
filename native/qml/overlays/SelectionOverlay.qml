import QtQuick
import "../UI"

/*!
    SelectionOverlay — object selection and move gestures for the select tool.

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
      • objectAt:      function(imageX, imageY) -> object id (quint64), 0 miss
      • objectBounds:  function(id) -> document-pixel QRectF (empty if unknown)
      Both hook functions may be null: a null objectAt never hits, and a null
      objectBounds yields no visible box (so there is nothing to drag).

    Signals:
      • moveRequested(id, dx, dy) — one call per completed drag/key nudge.
        The delta is in document pixels; the controller commits one undo step.
      • removeRequested(id)     — Delete/Backspace on the selected object.
      • selectionChanged(id)    — id is 0 when the selection is cleared.
      • doubleClicked(id)       — double click on an object, or inside the
                                  selected object's box. The second click
                                  never starts a move gesture.
      • cancelled()             — Esc; the selection is cleared first.

    Read-only:
      • selectedId        — currently selected object id, 0 for none.
      • selectedBounds    — selection in local display pixels; empty when
                            nothing is selected or the overlay is inactive.
      • dragging          — true while a move preview is in progress.
      • previewBounds     — ghost rectangle in local display pixels.
      • previewDelta      — ghost offset in document pixels.
      • hoveringObject    — hover hit-test result (used for the cursor).

    Functions:
      • selectAt(imageX, imageY) — hit-test at document pixels, select/clear.
        Returns the resulting id (0 for a miss).
      • setSelection(id)         — programmatic selection; 0 clears.
      • clearSelection()         — clear and emit selectionChanged(0) if needed.
      • pointAt(x, y) / displayPoint(imageX, imageY) — coordinate mapping.
      • refresh()                — re-read objectBounds for the selection.

    # Interaction

      • left click     select the topmost object at the point, or clear on a
                       miss. Clicking the selected box keeps it selected.
      • left drag      pressing inside the selected box starts a move preview;
                       a ghost rectangle follows the pointer and exactly one
                       `moveRequested` is emitted on release. Mouse moves never
                       call the controller.
      • double click   emits doubleClicked(id) for an object under the pointer
                       (or the selected one when the pointer is inside its
                       box). Any drag started by the second press is cancelled,
                       so a double click never moves the object.
      • Delete / Backspace  emit removeRequested(selectedId) once and clear.
      • Esc                 clear the selection and emit cancelled().
      • arrows               nudge by 1 document pixel (Shift = 10), one
                             moveRequested per key press.
      • middle / wheel delays to the canvas pan / zoom handlers underneath;
        this overlay never accepts either.

    # Clamping

    The move delta is clamped so the whole selection box stays inside
    [0, imageWidth] x [0, imageHeight]. If an object is wider/taller than the
    image on an axis, that axis is locked (delta 0) because no position can
    satisfy the constraint. The move delta is always reported in document
    pixels; the ghost is display-backed.

    The selection box may be visually larger than the viewport; only the
    viewport intersection is rasterised.

    # Keyboard focus

    `focus: active`; the item takes focus on activation and on mouse press, and
    shows a focus ring around the preview viewport. Key handlers are inert
    unless `active && inputEnabled` and the image geometry is valid.

    # Notes

    QML's signal grammar has no `quint64` basic type, so id parameters are
    declared as `var`. DocumentController ids are small monotonic counters and
    arrive unchanged (as JS numbers), so connecting them to
    `editor.moveObject(id, dx, dy)` / `editor.removeObject(id)` is exact.
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
    /*! function(imageX, imageY) -> quint64 object id. May be null. */
    property var objectAt: null
    /*! function(id) -> document-pixel QRectF. May be null. */
    property var objectBounds: null

    signal moveRequested(var id, real dx, real dy)
    signal removeRequested(var id)
    signal selectionChanged(var id)
    signal doubleClicked(var id)
    signal cancelled()

    // ── Geometry / enablement ───────────────────────────────────────────────
    width: imageWidth * viewScale
    height: imageHeight * viewScale
    clip: true
    // The selection is UI state: hide it entirely whenever the tool is off or
    // input is disabled (for example while a document command is running).
    visible: active && inputEnabled
    enabled: active && inputEnabled
    focus: active

    readonly property real scaleX: imageWidth > 0 ? width / imageWidth : 1
    readonly property real scaleY: imageHeight > 0 ? height / imageHeight : 1
    readonly property bool usable: active && inputEnabled && imageWidth > 0
                                   && imageHeight > 0 && width > 0 && height > 0

    // ── Exposed state ───────────────────────────────────────────────────────
    /*! Selected object id (quint64), 0 when nothing is selected. */
    readonly property var selectedId: _selectedId
    /*! Selection rect in local display pixels; empty when not visible. */
    readonly property rect selectedBounds: _boundsRevision >= 0
                                           ? _computeSelectedBounds()
                                           : Qt.rect(0, 0, 0, 0)
    /*! True while a move gesture is previewing. */
    readonly property bool dragging: _dragging
    /*! Ghost rectangle in local display pixels; empty when not dragging. */
    readonly property rect previewBounds: _computePreviewBounds()
    /*! Ghost offset in document pixels. */
    readonly property point previewDelta: _dragDelta
    /*! True when the pointer currently hovers a selectable object. */
    readonly property bool hoveringObject: _hoverObject
    /*! True when the pointer currently hovers the selected object's box. */
    readonly property bool hoveringSelected: _hoverSelected

    // ── Internal gesture state ──────────────────────────────────────────────
    property var _selectedId: 0
    property rect _lastRawBounds: Qt.rect(0, 0, 0, 0)
    property int _boundsRevision: 0
    property bool _dragging: false
    // Set while a double-click is being handled so the second press never
    // starts a move preview, regardless of the platform's event order.
    property bool _suppressDragPress: false
    property bool _pressActive: false
    property bool _hoverObject: false
    property bool _hoverSelected: false
    property point _pressImage: Qt.point(0, 0)
    property point _dragDelta: Qt.point(0, 0)
    property rect _dragStartBounds: Qt.rect(0, 0, 0, 0)

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Object selection")
    Accessible.description: qsTr("Click to select an object. Drag to move it. "
                                 + "Press Delete to remove it or Escape to cancel.")
    Accessible.focusable: true
    Accessible.focused: activeFocus

    // ── Coordinate mapping ──────────────────────────────────────────────────
    function _clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    /*! Display coordinates (local px) → document pixels, clamped to image. */
    function pointAt(x, y) {
        if (!isFinite(x) || !isFinite(y))
            return Qt.point(0, 0)
        if (!(scaleX > 0) || !(scaleY > 0))
            return Qt.point(0, 0)
        return Qt.point(_clamp(x / scaleX, 0, imageWidth),
                        _clamp(y / scaleY, 0, imageHeight))
    }

    /*! Document pixels → local display pixels. */
    function displayPoint(imageX, imageY) {
        return Qt.point(imageX * scaleX, imageY * scaleY)
    }

    // ── Hook normalisation ──────────────────────────────────────────────────
    function _normalizeId(value) {
        if (value === undefined || value === null)
            return 0
        const id = Number(value)
        if (!isFinite(id) || id <= 0)
            return 0
        return Math.floor(id)
    }

    function _emptyRect() {
        return Qt.rect(0, 0, 0, 0)
    }

    function _normalizeBounds(value) {
        if (value === undefined || value === null)
            return _emptyRect()
        const x = Number(value.x)
        const y = Number(value.y)
        const w = Number(value.width)
        const h = Number(value.height)
        if (!isFinite(x) || !isFinite(y) || !isFinite(w) || !isFinite(h))
            return _emptyRect()
        if (!(w > 0) || !(h > 0))
            return _emptyRect()
        return Qt.rect(x, y, w, h)
    }

    function _rawBounds(id) {
        if (!id || typeof objectBounds !== "function")
            return _emptyRect()
        try {
            return _normalizeBounds(objectBounds(id))
        } catch (error) {
            return _emptyRect()
        }
    }

    function _hitTest(imageX, imageY) {
        if (typeof objectAt !== "function")
            return 0
        try {
            return _normalizeId(objectAt(imageX, imageY))
        } catch (error) {
            return 0
        }
    }

    function _rectEquals(a, b) {
        return Math.abs(a.x - b.x) < 1e-6
                && Math.abs(a.y - b.y) < 1e-6
                && Math.abs(a.width - b.width) < 1e-6
                && Math.abs(a.height - b.height) < 1e-6
    }

    // ── Derived rects ───────────────────────────────────────────────────────
    function _computeSelectedBounds() {
        if (!usable || _selectedId === 0)
            return _emptyRect()
        const b = _rawBounds(_selectedId)
        if (!(b.width > 0) || !(b.height > 0))
            return _emptyRect()
        return Qt.rect(b.x * scaleX, b.y * scaleY,
                       b.width * scaleX, b.height * scaleY)
    }

    function _computePreviewBounds() {
        if (!_dragging)
            return _emptyRect()
        const b = _dragStartBounds
        if (!(b.width > 0) || !(b.height > 0))
            return _emptyRect()
        return Qt.rect((b.x + _dragDelta.x) * scaleX,
                       (b.y + _dragDelta.y) * scaleY,
                       b.width * scaleX, b.height * scaleY)
    }

    // ── Selection API ───────────────────────────────────────────────────────
    /*! Re-reads objectBounds for the current selection. Cheap; O(1) lookup. */
    function refresh() {
        _refreshBounds()
    }

    function _refreshBounds() {
        const next = _selectedId === 0 ? _emptyRect() : _rawBounds(_selectedId)
        if (_rectEquals(next, _lastRawBounds))
            return
        _lastRawBounds = next
        _boundsRevision++
    }

    /*! Selects an object id; 0 (or an invalid id) clears the selection. */
    function setSelection(id) {
        _applySelection(_normalizeId(id))
    }

    /*!
        Hit-tests at document-pixel coordinates and selects the result.
        Returns the resulting id (0 for a miss/disabled overlay).
    */
    function selectAt(imageX, imageY) {
        if (!usable || !isFinite(imageX) || !isFinite(imageY))
            return 0
        const x = _clamp(imageX, 0, imageWidth)
        const y = _clamp(imageY, 0, imageHeight)
        const hit = _hitTest(x, y)
        _applySelection(hit)
        return hit
    }

    /*! Clears the selection and emits selectionChanged(0) when it changes. */
    function clearSelection() {
        _applySelection(0)
    }

    function _applySelection(id) {
        const next = _normalizeId(id)
        if (next === _selectedId) {
            _refreshBounds()
            preview.requestPaint()
            return
        }
        _cancelDrag()
        _selectedId = next
        _lastRawBounds = next === 0 ? _emptyRect() : _rawBounds(next)
        _boundsRevision++
        _hoverSelected = false
        preview.requestPaint()
        root.selectionChanged(next)
    }

    // ── Gesture helpers ─────────────────────────────────────────────────────
    function _selectedRawBounds() {
        return _selectedId === 0 ? _emptyRect() : _rawBounds(_selectedId)
    }

    function _containsSelected(imageX, imageY) {
        const b = _selectedRawBounds()
        return b.width > 0 && b.height > 0
                && imageX >= b.x && imageX <= b.x + b.width
                && imageY >= b.y && imageY <= b.y + b.height
    }

    /*!
        Clamps a document-pixel delta so the whole box stays in the image.
        An axis whose object is larger than the image is locked.
    */
    function _clampedDeltaFor(bounds, dx, dy) {
        let cx = dx
        let cy = dy
        if (bounds.width <= imageWidth)
            cx = _clamp(dx, -bounds.x, imageWidth - bounds.x - bounds.width)
        else
            cx = 0
        if (bounds.height <= imageHeight)
            cy = _clamp(dy, -bounds.y, imageHeight - bounds.y - bounds.height)
        else
            cy = 0
        // Normalise -0 so signals and comparisons stay tidy.
        if (cx === 0)
            cx = 0
        if (cy === 0)
            cy = 0
        return Qt.point(cx, cy)
    }

    function _startDrag() {
        const b = _selectedRawBounds()
        if (!(b.width > 0) || !(b.height > 0)) {
            _dragging = false
            return false
        }
        _dragStartBounds = b
        _dragDelta = Qt.point(0, 0)
        _dragging = true
        preview.requestPaint()
        return true
    }

    function _cancelDrag() {
        if (!_dragging && _dragDelta.x === 0 && _dragDelta.y === 0)
            return
        _dragging = false
        _dragDelta = Qt.point(0, 0)
        _dragStartBounds = _emptyRect()
        preview.requestPaint()
    }

    function _updateDrag(imageX, imageY) {
        const d = _clampedDeltaFor(_dragStartBounds,
                                   imageX - _pressImage.x,
                                   imageY - _pressImage.y)
        if (d.x === _dragDelta.x && d.y === _dragDelta.y)
            return
        _dragDelta = d
        preview.requestPaint()
    }

    function _finishDrag() {
        const id = _selectedId
        // Copy scalars before cancelling: Qt.point values read from a property
        // can alias the property object, and _cancelDrag() resets it.
        const dx = _dragDelta.x
        const dy = _dragDelta.y
        const moved = _dragging && id !== 0 && (dx !== 0 || dy !== 0)
        _cancelDrag()
        if (!moved)
            return
        root.moveRequested(id, dx, dy)
        // The controller commits asynchronously; refresh now (in case the
        // model updated synchronously) and let the poll timer pick up a
        // worker-backed commit shortly afterwards.
        _refreshBounds()
    }

    function _updateHover(imageX, imageY) {
        const inside = _selectedId !== 0 && _containsSelected(imageX, imageY)
        const overObject = inside ? false : _hitTest(imageX, imageY) !== 0
        if (inside !== _hoverSelected)
            _hoverSelected = inside
        if (overObject !== _hoverObject)
            _hoverObject = overObject
    }

    function _clearHover() {
        if (_hoverSelected)
            _hoverSelected = false
        if (_hoverObject)
            _hoverObject = false
    }

    function _press(mouse) {
        if (!usable)
            return false
        forceActiveFocus(Qt.MouseFocusReason)
        const p = pointAt(mouse.x, mouse.y)
        _pressImage = p
        if (_selectedId !== 0 && _containsSelected(p.x, p.y)) {
            _startDrag()
        } else {
            const hit = _hitTest(p.x, p.y)
            _applySelection(hit)
            if (hit !== 0)
                _startDrag()
        }
        _updateHover(p.x, p.y)
        return true
    }

    /*!
        Resolves the object a double click targets: the current selection when
        the point is inside its box, otherwise the topmost object at the point.
    */
    function _doubleClickId(imageX, imageY) {
        if (_selectedId !== 0 && _containsSelected(imageX, imageY))
            return _selectedId
        return _hitTest(imageX, imageY)
    }

    function _handleDoubleClick(mouse) {
        if (!usable)
            return 0
        const p = pointAt(mouse.x, mouse.y)
        const id = _doubleClickId(p.x, p.y)
        // The second press of the sequence may already have started a drag;
        // discard it so a double click is never reported as a move.
        _cancelDrag()
        if (id === 0)
            return 0
        _applySelection(id)
        root.doubleClicked(id)
        return id
    }

    function _release(mouse) {
        if (!usable) {
            _cancelDrag()
            return
        }
        if (!_dragging)
            return
        const p = pointAt(mouse.x, mouse.y)
        _updateDrag(p.x, p.y)
        _finishDrag()
    }

    function _removeSelected() {
        if (!usable || _selectedId === 0)
            return false
        const id = _selectedId
        _cancelDrag()
        clearSelection()
        root.removeRequested(id)
        return true
    }

    function _cancel() {
        if (!usable)
            return
        _cancelDrag()
        clearSelection()
        root.cancelled()
    }

    function _nudge(dx, dy) {
        if (!usable || _selectedId === 0)
            return
        const b = _selectedRawBounds()
        if (!(b.width > 0) || !(b.height > 0))
            return
        const d = _clampedDeltaFor(b, dx, dy)
        if (d.x === 0 && d.y === 0)
            return
        root.moveRequested(_selectedId, d.x, d.y)
        _refreshBounds()
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────
    onActiveChanged: {
        if (active)
            forceActiveFocus(Qt.OtherFocusReason)
        else
            _cancelDrag()
        _clearHover()
        preview.requestPaint()
    }
    onUsableChanged: {
        if (!usable) {
            _cancelDrag()
            _clearHover()
        }
        preview.requestPaint()
    }
    onSelectedIdChanged: preview.requestPaint()
    onSelectedBoundsChanged: preview.requestPaint()
    onPreviewBoundsChanged: preview.requestPaint()
    onWidthChanged: preview.requestPaint()
    onHeightChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()
    onObjectAtChanged: _clearHover()
    onObjectBoundsChanged: _refreshBounds()
    onImageWidthChanged: _refreshBounds()
    onImageHeightChanged: _refreshBounds()
    onViewScaleChanged: _refreshBounds()

    Keys.onEscapePressed: function(event) {
        if (usable) {
            _cancel()
            event.accepted = true
        }
    }

    Keys.onPressed: function(event) {
        if (!usable)
            return
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            _removeSelected()
            event.accepted = true
            return
        }
        let dx = 0
        let dy = 0
        switch (event.key) {
        case Qt.Key_Left: dx = -1; break
        case Qt.Key_Right: dx = 1; break
        case Qt.Key_Up: dy = -1; break
        case Qt.Key_Down: dy = 1; break
        default: return
        }
        const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        _nudge(dx * step, dy * step)
        event.accepted = true
    }

    // ── Viewport-backed drawing ─────────────────────────────────────────────
    Canvas {
        id: preview
        objectName: "selectionPreview"
        // Keep the raster backing bounded to the visible intersection.
        x: Math.max(0, Math.min(root.width, root.visibleRect.x))
        y: Math.max(0, Math.min(root.height, root.visibleRect.y))
        width: Math.max(0, Math.min(root.width, root.visibleRect.x + root.visibleRect.width) - x)
        height: Math.max(0, Math.min(root.height, root.visibleRect.y + root.visibleRect.height) - y)
        visible: root.usable && root._selectedId !== 0
        onXChanged: requestPaint()
        onYChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            if (!root.usable || root.selectedId === 0)
                return
            c.translate(-x, -y)

            const b = root.selectedBounds
            if (!(b.width > 0) || !(b.height > 0))
                return

            // Crisp 1px geometry on integer device-independent coordinates.
            const left = Math.round(b.x) + 0.5
            const top = Math.round(b.y) + 0.5
            const right = Math.round(b.x + b.width) - 0.5
            const bottom = Math.round(b.y + b.height) - 0.5
            const boxWidth = Math.max(0, right - left)
            const boxHeight = Math.max(0, bottom - top)

            // Dark halo keeps the accent box legible on any photograph.
            c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
            c.lineWidth = 3
            c.strokeRect(left, top, boxWidth, boxHeight)
            c.strokeStyle = Theme.accent
            c.lineWidth = 1
            c.strokeRect(left, top, boxWidth, boxHeight)

            // Dashed ghost follows the pointer during a move gesture.
            if (root.dragging) {
                const g = root.previewBounds
                if (g.width > 0 && g.height > 0) {
                    const gl = Math.round(g.x) + 0.5
                    const gt = Math.round(g.y) + 0.5
                    const gr = Math.round(g.x + g.width) - 0.5
                    const gb = Math.round(g.y + g.height) - 0.5
                    const gw = Math.max(0, gr - gl)
                    const gh = Math.max(0, gb - gt)
                    c.fillStyle = Theme.alpha(Theme.accent, 0.10)
                    c.fillRect(gl, gt, gw, gh)
                    c.strokeStyle = Theme.accent
                    c.lineWidth = 1
                    if (typeof c.setLineDash === "function")
                        c.setLineDash([5, 4])
                    c.strokeRect(gl, gt, gw, gh)
                    if (typeof c.setLineDash === "function")
                        c.setLineDash([])
                }
            }

            // Corner handles are visual only; resizing is a later command.
            const handleSize = 7
            const corners = [[b.x, b.y],
                             [b.x + b.width, b.y],
                             [b.x, b.y + b.height],
                             [b.x + b.width, b.y + b.height]]
            for (let i = 0; i < corners.length; ++i) {
                const hx = Math.round(corners[i][0] - handleSize / 2)
                const hy = Math.round(corners[i][1] - handleSize / 2)
                c.fillStyle = Theme.accent
                c.fillRect(hx, hy, handleSize, handleSize)
                c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.65)
                c.lineWidth = 1
                c.strokeRect(hx + 0.5, hy + 0.5, handleSize - 1, handleSize - 1)
            }
        }
    }

    // Visible focus indicator for keyboard users.
    Rectangle {
        id: focusRing
        objectName: "selectionFocusRing"
        anchors.fill: preview
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.usable
    }

    MouseArea {
        id: pointer
        objectName: "selectionPointer"
        anchors.fill: parent
        enabled: root.usable
        // Middle button is intentionally absent so canvas panning wins.
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor
                     : root.hoveringSelected ? Qt.OpenHandCursor
                     : root.hoveringObject ? Qt.PointingHandCursor
                     : Qt.ArrowCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onPositionChanged: function(mouse) {
            if (!root.usable)
                return
            const p = root.pointAt(mouse.x, mouse.y)
            if (root.dragging)
                root._updateDrag(p.x, p.y)
            else
                root._updateHover(p.x, p.y)
        }
        onExited: root._clearHover()
        onPressed: function(mouse) {
            if (root._suppressDragPress) {
                mouse.accepted = true
                return
            }
            root._pressActive = true
            if (root._press(mouse))
                mouse.accepted = true
        }
        onReleased: function(mouse) {
            root._pressActive = false
            root._suppressDragPress = false
            root._release(mouse)
        }
        onDoubleClicked: function(mouse) {
            // Only a double click that is still inside a press lifecycle can
            // leave a drag behind; mark that press for cancellation. When the
            // signal arrives after the release there is nothing to suppress.
            if (root._pressActive)
                root._suppressDragPress = true
            root._handleDoubleClick(mouse)
            mouse.accepted = true
        }
        onCanceled: function() {
            root._pressActive = false
            root._cancelDrag()
        }
    }

    // The object layer commits asynchronously (worker render), so a lightweight
    // poll keeps the selection box glued to the object after a move, undo or
    // redo. objectBounds is an O(1) lookup and the timer only runs while an
    // object is selected; the binding is bumped only when the rect changes.
    Timer {
        id: boundsPoll
        interval: 60
        repeat: true
        running: root.usable && root._selectedId !== 0
        onTriggered: root._refreshBounds()
    }

    Connections {
        target: Theme
        function onDarkChanged() { preview.requestPaint() }
    }
}
