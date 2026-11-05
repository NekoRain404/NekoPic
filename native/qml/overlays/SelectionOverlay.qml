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
      • moveObjectsRequested(ids, dx, dy) — one call per completed drag/key
        nudge for the whole selection. `ids` is a JS array of object ids and
        the delta is in document pixels; the controller commits one undo step.
      • removeObjectsRequested(ids) — Delete/Backspace for the whole selection.
      • selectionChanged(idOrIds) — legacy-compatible payload: a scalar id for
        zero/one selected object (0 clears), and an array of ids for a
        multi-selection. The array form is the authoritative new contract.
      • moveRequested(id, dx, dy) — legacy single-object alias. Emitted only
        when exactly one object is selected, in addition to
        moveObjectsRequested, so existing single-select wiring keeps working.
      • removeRequested(id) — legacy single-object alias, emitted only when
        exactly one object is selected.
      • doubleClicked(id) — double click on an object, or inside the selected
        object's box. The second click never starts a move gesture.
      • cancelled() — Esc; the selection is cleared first.

    Read-only:
      • selectedIds       — array of selected ids (authoritative).
      • selectedId        — primary/last selected id, 0 when empty. Kept for
                            legacy single-select consumers.
      • selectionBounds   — union of every selected object in local display
                            pixels; empty when nothing is selected.
      • selectedBounds    — alias of selectionBounds (single selection yields
                            exactly that object's box, as before).
      • dragging          — true while a move preview is in progress.
      • previewBounds     — ghost rectangle in local display pixels.
      • previewDelta      — ghost offset in document pixels.
      • hoveringObject    — hover hit-test result (used for the cursor).
      • hoveringSelected  — pointer is inside the shared selection box.

    Functions:
      • selectAt(imageX, imageY) — hit-test at document pixels, replace the
        selection with the hit (or clear on a miss). Returns the resulting id.
      • setSelection(id)         — programmatic single selection; 0 clears.
      • setSelectionIds(ids)     — programmatic multi-selection; empty clears.
      • clearSelection()         — clear and emit selectionChanged(0) if needed.
      • pointAt(x, y) / displayPoint(imageX, imageY) — coordinate mapping.
      • refresh()                — re-read objectBounds for the selection.

    # Interaction

      • left click          select the topmost object at the point, or clear
                            on a miss. Clicking inside the current selection
                            box keeps the selection and starts a group drag.
      • Shift + left click  toggle the object under the pointer in/out of the
                            selection. A toggling click never starts a drag.
      • left drag           pressing inside the shared selection box starts a
                            move preview; a ghost rectangle follows the
                            pointer and exactly one moveObjectsRequested is
                            emitted on release. Mouse moves never call the
                            controller.
      • double click        emits doubleClicked(id) for an object under the
                            pointer (or the selected one when the pointer is
                            inside its box). Any drag started by the second
                            press is cancelled, so a double click never moves.
      • Delete / Backspace  emit removeObjectsRequested(ids) once and clear.
      • Esc                 clear the selection and emit cancelled().
      • arrows              nudge the whole selection by 1 document pixel
                            (Shift = 10), one moveObjectsRequested per press.
      • middle / wheel      delays to the canvas pan / zoom handlers
                            underneath; this overlay never accepts either.

    # Clamping

    Drag/nudge deltas are clamped so the shared selection box stays inside
    [0, imageWidth] x [0, imageHeight]. If the selection is wider/taller than
    the image on an axis, that axis is locked (delta 0). Deltas are always
    reported in document pixels; the ghost is display-backed.

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
    `editor.moveObjects(ids, dx, dy)` / `editor.removeObjects(ids)` is exact.
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
    signal moveObjectsRequested(var ids, real dx, real dy)
    signal removeObjectsRequested(var ids)
    signal moveStarted(var ids)
    signal movePreview(var ids, real dx, real dy)
    signal moveFinished(var ids, real dx, real dy)
    signal moveCancelled()
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
    /*! Selected ids (authoritative multi-selection set), in selection order. */
    readonly property var selectedIds: _selectedIds
    /*!
        Primary selected id: the only id for a single selection, the most
        recently added id for a multi-selection, 0 when empty. Legacy alias.
    */
    readonly property var selectedId: _selectedIds.length === 0 ? 0
                                    : _selectedIds[_selectedIds.length - 1]
    /*! Union of the selected objects in local display pixels. */
    readonly property rect selectionBounds: _boundsRevision >= 0
                                            ? _computeSelectionBounds()
                                            : Qt.rect(0, 0, 0, 0)
    /*! Legacy alias of selectionBounds (identical for single selection). */
    readonly property rect selectedBounds: selectionBounds
    /*! True while a move gesture is previewing. */
    readonly property bool dragging: _dragging
    /*! Ghost rectangle in local display pixels; empty when not dragging. */
    readonly property rect previewBounds: _computePreviewBounds()
    /*! Ghost offset in document pixels. */
    readonly property point previewDelta: _dragDelta
    /*!
        True when the controller has produced the base/object crops for a live
        pixel drag. When false, the dashed ghost remains the fallback.
    */
    property bool movePreviewReady: false
    /*! Document-pixel offset of the live object crop, including the settle
        window after release while the controller commits. */
    readonly property point movePreviewOffset: _dragging ? _dragDelta : _settledDelta
    /*! True while a live crop should be drawn (drag or pending commit). */
    readonly property bool movePreviewActive: _dragging
            || _settledDelta.x !== 0 || _settledDelta.y !== 0
    /*! True when the pointer currently hovers a selectable object. */
    readonly property bool hoveringObject: _hoverObject
    /*! True when the pointer currently hovers the shared selection box. */
    readonly property bool hoveringSelected: _hoverSelected

    // ── Internal gesture state ──────────────────────────────────────────────
    property var _selectedIds: []
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
    // Kept after release until the controller's committed bounds arrive, so
    // the crop and selection box do not snap back for a frame.
    property point _settledDelta: Qt.point(0, 0)
    // Magnetic guides: document-space coordinates, -1 when inactive.
    property real _snapGuideX: -1
    property real _snapGuideY: -1
    property bool snapEnabled: true

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Object selection")
    Accessible.description: qsTr("Click to select an object. Shift-click to add or remove objects. "
                                 + "Drag to move the selection, press Delete to remove it, "
                                 + "or Escape to cancel.")
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

    function _sameIds(a, b) {
        if (a.length !== b.length)
            return false
        for (let i = 0; i < a.length; ++i) {
            if (a[i] !== b[i])
                return false
        }
        return true
    }

    function _normalizeIds(values) {
        const result = []
        if (values === undefined || values === null)
            return result
        const list = Array.isArray(values) ? values : [values]
        for (let i = 0; i < list.length; ++i) {
            const id = _normalizeId(list[i])
            if (id !== 0 && result.indexOf(id) < 0)
                result.push(id)
        }
        return result
    }

    function _isSelected(id) {
        return _selectedIds.indexOf(id) >= 0
    }

    // ── Derived rects ───────────────────────────────────────────────────────
    /*! Union of the raw document-pixel boxes of every selected object. */
    function _unionRawBounds(ids) {
        let result = _emptyRect()
        for (let i = 0; i < ids.length; ++i) {
            const b = _rawBounds(ids[i])
            if (!(b.width > 0) || !(b.height > 0))
                continue
            if (!(result.width > 0) || !(result.height > 0)) {
                result = b
                continue
            }
            const left = Math.min(result.x, b.x)
            const top = Math.min(result.y, b.y)
            const right = Math.max(result.x + result.width, b.x + b.width)
            const bottom = Math.max(result.y + result.height, b.y + b.height)
            result = Qt.rect(left, top, right - left, bottom - top)
        }
        return result
    }

    function _computeSelectionBounds() {
        if (!usable || _selectedIds.length === 0)
            return _emptyRect()
        const b = _lastRawBounds
        if (!(b.width > 0) || !(b.height > 0))
            return _emptyRect()
        // Once the live object crop is available, the box must follow the
        // pixels; before that (and after release until the commit lands) the
        // ghost/settled offset keeps it at the visual target.
        const dx = _dragging ? (movePreviewReady ? _dragDelta.x : 0) : _settledDelta.x
        const dy = _dragging ? (movePreviewReady ? _dragDelta.y : 0) : _settledDelta.y
        return Qt.rect((b.x + dx) * scaleX, (b.y + dy) * scaleY,
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

    /*! Ends the live-drag/settle overlay after the controller has committed
        (or cancelled) the move. Safe to call at any time. */
    function clearMovePreview() {
        if (_settledDelta.x === 0 && _settledDelta.y === 0) {
            _refreshBounds()
            return
        }
        _settledDelta = Qt.point(0, 0)
        _refreshBounds()
        preview.requestPaint()
    }

    function _refreshBounds() {
        const next = _unionRawBounds(_selectedIds)
        if (_rectEquals(next, _lastRawBounds))
            return
        // The live crop is only needed while the committed bounds are still
        // the old ones. Once the controller reports the new bounds, drop the
        // temporary offset so the box is not shifted twice.
        if (_settledDelta.x !== 0 || _settledDelta.y !== 0)
            _settledDelta = Qt.point(0, 0)
        _lastRawBounds = next
        _boundsRevision++
    }

    function _emitSelectionChanged() {
        if (_selectedIds.length > 1)
            root.selectionChanged(_selectedIds.slice())
        else
            root.selectionChanged(_selectedIds.length === 1 ? _selectedIds[0] : 0)
    }

    /*! Replaces the selection with `ids` (normalised, deduplicated). */
    function setSelectionIds(ids) {
        _setSelectionIds(_normalizeIds(ids))
    }

    function _setSelectionIds(next) {
        if (_sameIds(next, _selectedIds)) {
            _refreshBounds()
            preview.requestPaint()
            return
        }
        _cancelDrag()
        _settledDelta = Qt.point(0, 0)
        _selectedIds = next
        _lastRawBounds = _unionRawBounds(next)
        _boundsRevision++
        _hoverSelected = false
        preview.requestPaint()
        _emitSelectionChanged()
    }

    /*! Selects an object id; 0 (or an invalid id) clears the selection. */
    function setSelection(id) {
        const primary = _normalizeId(id)
        _setSelectionIds(primary === 0 ? [] : [primary])
    }

    /*!
        Hit-tests at document-pixel coordinates and replaces the selection with
        the result. Returns the resulting id (0 for a miss/disabled overlay).
    */
    function selectAt(imageX, imageY) {
        if (!usable || !isFinite(imageX) || !isFinite(imageY))
            return 0
        const x = _clamp(imageX, 0, imageWidth)
        const y = _clamp(imageY, 0, imageHeight)
        const hit = _hitTest(x, y)
        _setSelectionIds(hit === 0 ? [] : [hit])
        return hit
    }

    /*! Clears the selection and emits selectionChanged(0) when it changes. */
    function clearSelection() {
        _setSelectionIds([])
    }

    /*! Toggles one id in the current selection (Shift+click semantics). */
    function toggleSelection(id) {
        const target = _normalizeId(id)
        if (target === 0)
            return
        const next = _selectedIds.slice()
        const index = next.indexOf(target)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(target)
        _setSelectionIds(next)
    }

    // ── Gesture helpers ─────────────────────────────────────────────────────
    function _containsSelection(imageX, imageY) {
        const b = _lastRawBounds
        return _selectedIds.length > 0
                && b.width > 0 && b.height > 0
                && imageX >= b.x && imageX <= b.x + b.width
                && imageY >= b.y && imageY <= b.y + b.height
    }

    /*!
        Clamps a document-pixel delta so the whole selection box stays in the
        image. An axis whose selection is larger than the image is locked.
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
        _refreshBounds()
        const b = _lastRawBounds
        if (!(b.width > 0) || !(b.height > 0)) {
            _dragging = false
            return false
        }
        _settledDelta = Qt.point(0, 0)
        _snapGuideX = -1
        _snapGuideY = -1
        _dragStartBounds = b
        _dragDelta = Qt.point(0, 0)
        _dragging = true
        root.moveStarted(_selectedIds.slice())
        preview.requestPaint()
        return true
    }

    function _cancelDrag() {
        if (!_dragging && _dragDelta.x === 0 && _dragDelta.y === 0)
            return
        _dragging = false
        _dragDelta = Qt.point(0, 0)
        _dragStartBounds = _emptyRect()
        _snapGuideX = -1
        _snapGuideY = -1
        preview.requestPaint()
    }

    function _updateDrag(imageX, imageY) {
        const raw = Qt.point(imageX - _pressImage.x, imageY - _pressImage.y)
        const d = _snapDelta(_dragStartBounds, raw.x, raw.y)
        if (d.x === _dragDelta.x && d.y === _dragDelta.y)
            return
        _dragDelta = d
        root.movePreview(_selectedIds.slice(), d.x, d.y)
        preview.requestPaint()
    }

    /*!
        Magnetic guides for the image centre and edges. The threshold is
        expressed in display pixels so the feel stays constant at any zoom;
        the returned delta is still in document pixels. Alt is not required:
        a small pull is deliberate, like a ruler detent.
    */
    function _snapDelta(bounds, dx, dy) {
        _snapGuideX = -1
        _snapGuideY = -1
        if (!snapEnabled || !(bounds.width > 0) || !(bounds.height > 0))
            return _clampedDeltaFor(bounds, dx, dy)

        const thresholdX = 7 / Math.max(scaleX, 0.0001)
        const thresholdY = 7 / Math.max(scaleY, 0.0001)
        const centerX = bounds.x + bounds.width / 2
        const centerY = bounds.y + bounds.height / 2
        const candidatesX = [
            { target: imageWidth / 2, current: centerX + dx, guide: imageWidth / 2 },
            { target: 0, current: bounds.x + dx, guide: 0 },
            { target: imageWidth, current: bounds.x + bounds.width + dx, guide: imageWidth }
        ]
        const candidatesY = [
            { target: imageHeight / 2, current: centerY + dy, guide: imageHeight / 2 },
            { target: 0, current: bounds.y + dy, guide: 0 },
            { target: imageHeight, current: bounds.y + bounds.height + dy, guide: imageHeight }
        ]

        let bestX = thresholdX
        for (let i = 0; i < candidatesX.length; ++i) {
            const distance = Math.abs(candidatesX[i].current - candidatesX[i].target)
            if (distance < bestX) {
                bestX = distance
                dx += candidatesX[i].target - candidatesX[i].current
                _snapGuideX = candidatesX[i].guide
            }
        }
        let bestY = thresholdY
        for (let i = 0; i < candidatesY.length; ++i) {
            const distance = Math.abs(candidatesY[i].current - candidatesY[i].target)
            if (distance < bestY) {
                bestY = distance
                dy += candidatesY[i].target - candidatesY[i].current
                _snapGuideY = candidatesY[i].guide
            }
        }
        return _clampedDeltaFor(bounds, dx, dy)
    }

    function _emitMove(ids, dx, dy) {
        if (ids.length === 1)
            root.moveRequested(ids[0], dx, dy)
        root.moveObjectsRequested(ids, dx, dy)
    }

    function _finishDrag() {
        const ids = _selectedIds.slice()
        // Copy scalars before cancelling: Qt.point values read from a property
        // can alias the property object, and _cancelDrag() resets it.
        const dx = _dragDelta.x
        const dy = _dragDelta.y
        const moved = _dragging && ids.length > 0 && (dx !== 0 || dy !== 0)
        if (!moved) {
            _cancelDrag()
            root.moveCancelled()
            return
        }
        // Keep the live crop and selection box at the target until the
        // controller's committed bounds arrive (Main calls clearMovePreview()).
        _settledDelta = Qt.point(dx, dy)
        _cancelDrag()
        _emitMove(ids, dx, dy)
        root.moveFinished(ids, dx, dy)
        preview.requestPaint()
    }

    function _updateHover(imageX, imageY) {
        const inside = _containsSelection(imageX, imageY)
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
        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
        if (shift) {
            // Shift+click toggles membership and never drags.
            const toggled = _hitTest(p.x, p.y)
            if (toggled !== 0)
                toggleSelection(toggled)
            _updateHover(p.x, p.y)
            return true
        }
        if (_containsSelection(p.x, p.y)) {
            _startDrag()
        } else {
            const hit = _hitTest(p.x, p.y)
            _setSelectionIds(hit === 0 ? [] : [hit])
            if (hit !== 0)
                _startDrag()
        }
        _updateHover(p.x, p.y)
        return true
    }

    /*!
        Resolves the object a double click targets: the current single
        selection when the point is inside its box, otherwise the topmost
        object at the point.
    */
    function _doubleClickId(imageX, imageY) {
        if (_selectedIds.length === 1 && _containsSelection(imageX, imageY))
            return _selectedIds[0]
        const hit = _hitTest(imageX, imageY)
        if (hit !== 0)
            return hit
        if (_selectedIds.length > 1 && _containsSelection(imageX, imageY))
            return _selectedIds[_selectedIds.length - 1]
        return 0
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
        setSelection(id)
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

    function removeSelected() {
        if (!usable || _selectedIds.length === 0)
            return false
        const ids = _selectedIds.slice()
        _cancelDrag()
        _settledDelta = Qt.point(0, 0)
        clearSelection()
        if (ids.length === 1)
            root.removeRequested(ids[0])
        root.removeObjectsRequested(ids)
        return true
    }

    function _cancel() {
        if (!usable)
            return
        const wasMoving = _dragging || _settledDelta.x !== 0 || _settledDelta.y !== 0
        _cancelDrag()
        _settledDelta = Qt.point(0, 0)
        if (wasMoving)
            root.moveCancelled()
        clearSelection()
        root.cancelled()
    }

    function _nudge(dx, dy) {
        if (!usable || _selectedIds.length === 0)
            return
        _refreshBounds()
        const b = _lastRawBounds
        if (!(b.width > 0) || !(b.height > 0))
            return
        const d = _clampedDeltaFor(b, dx, dy)
        if (d.x === 0 && d.y === 0)
            return
        _emitMove(_selectedIds.slice(), d.x, d.y)
        _refreshBounds()
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────
    onActiveChanged: {
        if (active)
            forceActiveFocus(Qt.OtherFocusReason)
        else {
            const wasMoving = _dragging || _settledDelta.x !== 0 || _settledDelta.y !== 0
            _cancelDrag()
            _settledDelta = Qt.point(0, 0)
            if (wasMoving)
                root.moveCancelled()
        }
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
    onSelectionBoundsChanged: preview.requestPaint()
    onPreviewBoundsChanged: preview.requestPaint()
    onWidthChanged: preview.requestPaint()
    onHeightChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()
    onObjectAtChanged: _clearHover()
    onObjectBoundsChanged: _refreshBounds()
    onMovePreviewReadyChanged: preview.requestPaint()
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
            removeSelected()
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
    SelectionPreview {
        id: preview
        viewportWidth: root.width
        viewportHeight: root.height
        visibleRect: root.visibleRect
        usable: root.usable
        selectedIds: root._selectedIds
        rawBounds: function(id) { return root._rawBounds(id) }
        scaleX: root.scaleX
        scaleY: root.scaleY
        selectionBounds: root.selectionBounds
        dragging: root.dragging
        movePreviewReady: root.movePreviewReady
        previewBounds: root.previewBounds
        snapGuideX: root._snapGuideX
        snapGuideY: root._snapGuideY
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
    // poll keeps the selection box glued to the objects after a move, undo or
    // redo. objectBounds is an O(1) lookup and the timer only runs while the
    // selection is non-empty; the binding is bumped only when the union changes.
    Timer {
        id: boundsPoll
        interval: 60
        repeat: true
        running: root.usable && root._selectedIds.length > 0
        onTriggered: root._refreshBounds()
    }

    Connections {
        target: Theme
        function onDarkChanged() { preview.requestPaint() }
    }
}
