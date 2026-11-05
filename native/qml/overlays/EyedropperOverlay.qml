import QtQuick
import "../UI"

/*!
    EyedropperOverlay — colour picker overlay with a magnifier loupe.

    Place this over the displayed image rectangle (anchored to the picture,
    like CropOverlay / MosaicOverlay). Local display pixels map to image
    pixels through the actual display size, so it stays correct for any zoom:

        imageX = localX * imageWidth / width
        imageY = localY * imageHeight / height

    `visibleRect` is the viewport in this item's local coordinates. It only
    constrains where the loupe may sit; the loupe never leaves the viewport
    and never draws outside the image rectangle.

    Interaction (active && inputEnabled):
      • hover / drag  sample continuously (emits `sampled`)
      • left press    pick and emit `colorPicked`
      • Esc           cancel and emit `cancelled`
      • right press   cancel and emit `cancelled`
      • arrows        move the sample by 1 image px (Shift = 10)
      • Enter/Return  pick the current sample
      • middle / wheel are deliberately left unaccepted and reach the canvas
        pan / zoom handlers underneath.

    A null `sampler` is safe: the loupe shows a neutral placeholder and no
    colour signal is ever emitted. Validation rejects NaN / Inf and sampler
    exceptions.

    `sampleRadius` (default 0) selects a single pixel; 1 averages the 3×3
    neighbourhood, and so on.
*/
Item {
    id: root

    property bool active: false
    property bool inputEnabled: true
    property int imageWidth: 0
    property int imageHeight: 0
    /*! Display scale used by the parent; width/height remain authoritative. */
    property real viewScale: 1
    /*! Viewport in this item's local display coordinates. */
    property rect visibleRect: Qt.rect(0, 0, width, height)
    /*! Image shown inside the loupe. Empty gives a neutral placeholder. */
    property url imageUrl
    /*! function(imageX, imageY) -> color. May be null. */
    property var sampler: null
    property real magnifierSize: 132
    /*! Neighbourhood radius passed to the sampler; 0 = single pixel. */
    property int sampleRadius: 0

    signal colorPicked(color value)
    signal cancelled()
    signal sampled(color value, real imageX, real imageY)

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
    /*! Last successfully read colour. */
    readonly property bool hasSample: _hasColor
    readonly property color currentColor: _sampleColor
    /*! Neutral ink used while no sampler is bound. */
    readonly property color swatchColor: _hasColor ? _sampleColor : Theme.hover
    /*! Sample position in image pixels, clamped to the image. */
    property point samplePosition: Qt.point(0, 0)
    readonly property string hexText: _hasColor ? hexString(_sampleColor) : "—"
    readonly property string rgbText: _hasColor ? rgbString(_sampleColor) : "—"

    /*! Viewport intersected with the image rectangle, in local coordinates. */
    readonly property rect viewportRect: {
        const v = visibleRect
        const left = Math.max(0, Math.min(width, v.x))
        const top = Math.max(0, Math.min(height, v.y))
        const right = Math.max(left, Math.min(width, v.x + v.width))
        const bottom = Math.max(top, Math.min(height, v.y + v.height))
        return Qt.rect(left, top, right - left, bottom - top)
    }
    readonly property real loupeMargin: Theme.spacingMd
    readonly property real loupeWidth: loupe.width
    readonly property real loupeHeight: loupe.height
    readonly property real cursorOffset: Theme.spacingLg + Theme.spacingXs
    readonly property point loupePoint: loupePosition(_cursorDisplay.x, _cursorDisplay.y)

    property bool _positioned: false
    property bool _hasColor: false
    property color _sampleColor: "transparent"
    property point _cursorDisplay: Qt.point(0, 0)

    function _clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    /*! Display coordinates (local px) → image pixels, clamped to the image. */
    function pointAt(x, y) {
        if (!(scaleX > 0) || !(scaleY > 0))
            return Qt.point(0, 0)
        return Qt.point(_clamp(x / scaleX, 0, imageWidth),
                        _clamp(y / scaleY, 0, imageHeight))
    }

    /*! Image pixels → local display pixels. */
    function displayPoint(imageX, imageY) {
        return Qt.point(imageX * scaleX, imageY * scaleY)
    }

    function _normalizeColor(value) {
        if (value === undefined || value === null)
            return null
        const c = typeof value === "string" ? Qt.color(value) : value
        if (typeof c !== "object" || c === null)
            return null
        if (!isFinite(c.r) || !isFinite(c.g) || !isFinite(c.b))
            return null
        return Qt.rgba(_clamp(c.r, 0, 1), _clamp(c.g, 0, 1), _clamp(c.b, 0, 1),
                       isFinite(c.a) ? _clamp(c.a, 0, 1) : 1)
    }

    function _readSampledColor(imageX, imageY) {
        if (typeof sampler !== "function")
            return null
        try {
            if (sampleRadius <= 0)
                return _normalizeColor(sampler(imageX, imageY))
            const radius = Math.max(0, Math.floor(sampleRadius))
            const cx = Math.round(imageX)
            const cy = Math.round(imageY)
            let r = 0, g = 0, b = 0, a = 0, count = 0
            for (let dy = -radius; dy <= radius; ++dy) {
                for (let dx = -radius; dx <= radius; ++dx) {
                    const px = _clamp(cx + dx, 0, Math.max(0, imageWidth - 1))
                    const py = _clamp(cy + dy, 0, Math.max(0, imageHeight - 1))
                    const c = _normalizeColor(sampler(px, py))
                    if (c === null)
                        continue
                    r += c.r; g += c.g; b += c.b; a += c.a; ++count
                }
            }
            return count > 0 ? Qt.rgba(r / count, g / count, b / count, a / count) : null
        } catch (error) {
            return null
        }
    }

    /*! Reads and stores a sample. Returns true only for a valid colour. */
    function _sampleAt(imageX, imageY, emitSample) {
        if (!usable || !isFinite(imageX) || !isFinite(imageY))
            return false
        const x = _clamp(imageX, 0, Math.max(0, imageWidth - 1))
        const y = _clamp(imageY, 0, Math.max(0, imageHeight - 1))
        _positioned = true
        samplePosition = Qt.point(x, y)
        const c = _readSampledColor(x, y)
        if (c === null) {
            _hasColor = false
            return false
        }
        _sampleColor = c
        _hasColor = true
        if (emitSample)
            root.sampled(c, x, y)
        return true
    }

    /*! Explicit pick used by clicks, Enter and tests. */
    function pickAt(imageX, imageY) {
        if (!usable || !isFinite(imageX) || !isFinite(imageY))
            return false
        const x = _clamp(imageX, 0, Math.max(0, imageWidth - 1))
        const y = _clamp(imageY, 0, Math.max(0, imageHeight - 1))
        _cursorDisplay = displayPoint(x, y)
        const picked = _sampleAt(x, y, true)
        if (picked)
            root.colorPicked(_sampleColor)
        return picked
    }

    function _pickCurrent() {
        const x = _positioned ? samplePosition.x : Math.max(0, (imageWidth - 1) / 2)
        const y = _positioned ? samplePosition.y : Math.max(0, (imageHeight - 1) / 2)
        pickAt(x, y)
    }

    /*! Clears the sample and hides the loupe until the next interaction. */
    function reset() {
        _positioned = false
        _hasColor = false
        _sampleColor = "transparent"
        const x = imageWidth > 0 ? (imageWidth - 1) / 2 : 0
        const y = imageHeight > 0 ? (imageHeight - 1) / 2 : 0
        samplePosition = Qt.point(x, y)
        _cursorDisplay = displayPoint(x, y)
    }

    /*! Cancels the current sampling session. */
    function cancel() {
        if (!active || !inputEnabled)
            return
        reset()
        root.cancelled()
    }

    /*!
        Computes a loupe position for a cursor anchor, keeping the loupe
        inside `viewportRect` with `loupeMargin` of breathing room. The loupe
        flips to the other side of the cursor before clamping.
    */
    function loupePosition(anchorX, anchorY) {
        const vp = viewportRect
        const w = Math.max(0, loupeWidth)
        const h = Math.max(0, loupeHeight)
        const m = loupeMargin
        const gap = cursorOffset
        let x = anchorX + gap
        let y = anchorY + gap
        if (x + w > vp.x + vp.width - m)
            x = anchorX - w - gap
        if (y + h > vp.y + vp.height - m)
            y = anchorY - h - gap
        const minX = vp.x + m
        const maxX = vp.x + vp.width - w - m
        x = maxX >= minX ? _clamp(x, minX, maxX) : vp.x + Math.max(0, (vp.width - w) / 2)
        const minY = vp.y + m
        const maxY = vp.y + vp.height - h - m
        y = maxY >= minY ? _clamp(y, minY, maxY) : vp.y + Math.max(0, (vp.height - h) / 2)
        return Qt.point(x, y)
    }

    /*! "#RRGGBB" for any colour; an em dash when the value is invalid. */
    function hexString(value) {
        const c = _normalizeColor(value)
        if (c === null)
            return "—"
        const pair = function(channel) {
            const v = Math.round(_clamp(channel, 0, 1) * 255)
            return (v < 16 ? "0" : "") + v.toString(16).toUpperCase()
        }
        return "#" + pair(c.r) + pair(c.g) + pair(c.b)
    }

    /*! "rgb(r, g, b)" for any colour; an em dash when the value is invalid. */
    function rgbString(value) {
        const c = _normalizeColor(value)
        if (c === null)
            return "—"
        const channel = function(v) { return Math.round(_clamp(v, 0, 1) * 255) }
        return "rgb(" + channel(c.r) + ", " + channel(c.g) + ", " + channel(c.b) + ")"
    }

    function _updateFromDisplay(localX, localY) {
        if (!usable || !isFinite(localX) || !isFinite(localY))
            return
        // Samples outside the displayed image are ignored rather than clamped.
        if (localX < 0 || localY < 0 || localX > width || localY > height)
            return
        const p = pointAt(localX, localY)
        _cursorDisplay = Qt.point(localX, localY)
        _sampleAt(p.x, p.y, true)
    }

    /*! Focus ring is reserved for keyboard users; sampling is silent. */
    property bool _keyboardFocus: false
    property bool _mouseFocusRequest: false

    function takeMouseFocus() {
        _keyboardFocus = false
        _mouseFocusRequest = true
        forceActiveFocus(Qt.MouseFocusReason)
        Qt.callLater(function() { _mouseFocusRequest = false })
    }

    onActiveFocusChanged: {
        if (activeFocus && !_mouseFocusRequest)
            _keyboardFocus = true
        _mouseFocusRequest = false
    }

    onActiveChanged: {
        reset()
        if (active) {
            _keyboardFocus = false
            _mouseFocusRequest = true
            forceActiveFocus(Qt.OtherFocusReason)
            Qt.callLater(function() { _mouseFocusRequest = false })
        }
    }
    onUsableChanged: if (!usable) reset()
    onImageWidthChanged: if (active) reset()
    onImageHeightChanged: if (active) reset()

    Keys.onEscapePressed: function(event) {
        root._keyboardFocus = true
        if (usable) {
            cancel()
            event.accepted = true
        }
    }
    Keys.onReturnPressed: function(event) {
        root._keyboardFocus = true
        if (usable) {
            _pickCurrent()
            event.accepted = true
        }
    }
    Keys.onEnterPressed: function(event) {
        root._keyboardFocus = true
        if (usable) {
            _pickCurrent()
            event.accepted = true
        }
    }
    Keys.onPressed: function(event) {
        root._keyboardFocus = true
        if (!usable)
            return
        let dx = 0, dy = 0
        switch (event.key) {
        case Qt.Key_Left: dx = -1; break
        case Qt.Key_Right: dx = 1; break
        case Qt.Key_Up: dy = -1; break
        case Qt.Key_Down: dy = 1; break
        default: return
        }
        const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        const base = _positioned ? samplePosition
                                 : Qt.point(Math.max(0, (imageWidth - 1) / 2),
                                            Math.max(0, (imageHeight - 1) / 2))
        const x = _clamp(base.x + dx * step, 0, Math.max(0, imageWidth - 1))
        const y = _clamp(base.y + dy * step, 0, Math.max(0, imageHeight - 1))
        _cursorDisplay = displayPoint(x, y)
        _sampleAt(x, y, true)
        event.accepted = true
    }

    Loupe {
        id: loupe
        objectName: "eyedropperLoupe"
        size: root.magnifierSize
        margin: root.loupeMargin
        source: root.imageUrl
        imageWidth: root.imageWidth
        imageHeight: root.imageHeight
        sampleX: root.samplePosition.x
        sampleY: root.samplePosition.y
        color: root.currentColor
        hasSample: root.hasSample
        hexText: root.hexText
        rgbText: root.rgbText
        x: root.loupePoint.x
        y: root.loupePoint.y
        opacity: root.active && root._positioned ? 1 : 0
        scale: root.active && root._positioned ? 1 : 0.94
        transformOrigin: Item.Center
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.standardEasing
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.standardEasing
            }
        }
    }

    Rectangle {
        objectName: "eyedropperFocusRing"
        anchors.fill: parent
        anchors.margins: 1
        radius: Theme.radiusXs
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.usable && root._keyboardFocus
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.usable
        // Middle button is intentionally absent so canvas panning wins.
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.CrossCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onPressed: function(mouse) {
            if (!root.usable)
                return
            root.takeMouseFocus()
            if (mouse.button === Qt.RightButton) {
                root.cancel()
                mouse.accepted = true
                return
            }
            root._updateFromDisplay(mouse.x, mouse.y)
            const p = root.pointAt(mouse.x, mouse.y)
            root.pickAt(p.x, p.y)
            mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
            root._updateFromDisplay(mouse.x, mouse.y)
        }
    }
}
