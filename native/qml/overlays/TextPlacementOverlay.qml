import QtQuick
import "../UI"

/*!
    TextPlacementOverlay — click-to-place anchor picker for the text tool.

    Place this over the displayed image rectangle (anchored to the picture,
    like CropOverlay / MosaicOverlay / EyedropperOverlay). Local display
    pixels map to image pixels through the actual display size, so it stays
    correct for any zoom:

        imageX = localX * imageWidth / width
        imageY = localY * imageHeight / height

    `visibleRect` is the viewport in this item's local coordinates. Drawing is
    viewport-backed: the preview Canvas only covers the intersection of the
    viewport and the image, so a very large image at high zoom never
    allocates an image-sized raster.

    Interaction (active && inputEnabled):
      • hover         the crosshair follows the cursor
      • left press    emit `pointSelected` with the clamped image anchor
      • Esc           cancel and emit `cancelled`
      • middle / wheel are deliberately left unaccepted and reach the canvas
        pan / zoom handlers underneath.
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

    signal pointSelected(real imageX, real imageY)
    signal cancelled()

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

    /*! Crosshair position in local display pixels. */
    readonly property point cursorPosition: _cursorDisplay
    /*! True while the crosshair is drawn. */
    readonly property bool cursorVisible: usable && _positioned

    property point _cursorDisplay: Qt.point(0, 0)
    property bool _positioned: false
    /*! Focus ring is reserved for keyboard users; mouse placement is silent. */
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

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Text placement")
    Accessible.description: qsTr("Click the image to place text. Press Escape to cancel.")
    Accessible.focusable: true
    Accessible.focused: activeFocus

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

    function resetCursor() {
        _positioned = false
        _cursorDisplay = Qt.point(width / 2, height / 2)
        preview.requestPaint()
    }

    onActiveChanged: {
        resetCursor()
        if (active) {
            _keyboardFocus = false
            _mouseFocusRequest = true
            forceActiveFocus(Qt.OtherFocusReason)
            Qt.callLater(function() { _mouseFocusRequest = false })
        }
    }
    onUsableChanged: if (!usable) resetCursor()
    onWidthChanged: preview.requestPaint()
    onHeightChanged: preview.requestPaint()
    onVisibleRectChanged: preview.requestPaint()

    Keys.onEscapePressed: function(event) {
        root._keyboardFocus = true
        if (usable) {
            root.cancelled()
            event.accepted = true
        }
    }

    Canvas {
        id: preview
        objectName: "textPlacementPreview"
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
            if (!root.usable || !root.cursorVisible)
                return
            c.translate(-x, -y)

            const cx = Math.round(root._cursorDisplay.x) + 0.5
            const cy = Math.round(root._cursorDisplay.y) + 0.5

            // Dark halo keeps the crosshair legible on any photograph.
            c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
            c.lineWidth = 3
            c.beginPath()
            c.moveTo(0, cy); c.lineTo(root.width, cy)
            c.moveTo(cx, 0); c.lineTo(cx, root.height)
            c.stroke()

            c.strokeStyle = Theme.accent
            c.lineWidth = 1
            c.beginPath()
            c.moveTo(0, cy); c.lineTo(root.width, cy)
            c.moveTo(cx, 0); c.lineTo(cx, root.height)
            c.stroke()

            c.beginPath()
            c.arc(cx, cy, Theme.spacingSm, 0, Math.PI * 2)
            c.stroke()

            c.fillStyle = Theme.accent
            c.beginPath()
            c.arc(cx, cy, Theme.borderWidth * 1.5, 0, Math.PI * 2)
            c.fill()
        }
    }

    // Subtle focus indicator for keyboard users only.
    Rectangle {
        objectName: "textPlacementFocusRing"
        anchors.fill: preview
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
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.IBeamCursor
        onWheel: function(wheel) { wheel.accepted = false }
        onPositionChanged: function(mouse) {
            if (!root.usable)
                return
            root._cursorDisplay = Qt.point(mouse.x, mouse.y)
            root._positioned = true
            preview.requestPaint()
        }
        onExited: {
            root._positioned = false
            preview.requestPaint()
        }
        onPressed: function(mouse) {
            if (!root.usable)
                return
            root.takeMouseFocus()
            root._cursorDisplay = Qt.point(mouse.x, mouse.y)
            root._positioned = true
            preview.requestPaint()
            const p = root.pointAt(mouse.x, mouse.y)
            root.pointSelected(p.x, p.y)
            mouse.accepted = true
        }
    }

    Connections {
        target: Theme
        function onDarkChanged() { preview.requestPaint() }
    }
}
