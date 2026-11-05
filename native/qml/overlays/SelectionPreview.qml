import QtQuick
import "../UI"

/*!
    SelectionPreview — the viewport-backed canvas behind SelectionOverlay.

    The painter receives explicit state from the gesture owner: selection
    bounds, drag ghost, snap guides and the visible viewport. Keeping the
    raster backing bounded to the visible intersection means a very large
    image at high zoom never allocates an image-sized surface.
*/
Canvas {
    id: preview
    objectName: "selectionPreview"

    property real viewportWidth: 0
    property real viewportHeight: 0
    property rect visibleRect: Qt.rect(0, 0, 0, 0)
    property bool usable: false
    property var selectedIds: []
    property var rawBounds: null
    property real scaleX: 1
    property real scaleY: 1
    property var selectionBounds: ({ x: 0, y: 0, width: 0, height: 0 })
    property bool dragging: false
    property bool movePreviewReady: false
    property var previewBounds: ({ x: 0, y: 0, width: 0, height: 0 })
    property real snapGuideX: -1
    property real snapGuideY: -1

    // Keep the raster backing bounded to the visible intersection.
    x: Math.max(0, Math.min(viewportWidth, visibleRect.x))
    y: Math.max(0, Math.min(viewportHeight, visibleRect.y))
    width: Math.max(0, Math.min(viewportWidth, visibleRect.x + visibleRect.width) - x)
    height: Math.max(0, Math.min(viewportHeight, visibleRect.y + visibleRect.height) - y)
    visible: usable && selectedIds.length > 0

    onXChanged: requestPaint()
    onYChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onUsableChanged: requestPaint()
    onSelectedIdsChanged: requestPaint()
    onScaleXChanged: requestPaint()
    onScaleYChanged: requestPaint()
    onSelectionBoundsChanged: requestPaint()
    onDraggingChanged: requestPaint()
    onMovePreviewReadyChanged: requestPaint()
    onPreviewBoundsChanged: requestPaint()
    onSnapGuideXChanged: requestPaint()
    onSnapGuideYChanged: requestPaint()
    onVisibleRectChanged: requestPaint()

    onPaint: {
        const c = getContext("2d")
        c.reset()
        if (!usable || selectedIds.length === 0)
            return
        c.translate(-x, -y)

        // Multi-selection: keep a subtle outline per object so the
        // individual members stay legible under the shared box.
        if (selectedIds.length > 1 && typeof rawBounds === "function") {
            c.strokeStyle = Theme.alpha(Theme.accent, 0.55)
            c.lineWidth = 1
            for (let i = 0; i < selectedIds.length; ++i) {
                const raw = rawBounds(selectedIds[i])
                if (!(raw.width > 0) || !(raw.height > 0))
                    continue
                const l = Math.round(raw.x * scaleX) + 0.5
                const t = Math.round(raw.y * scaleY) + 0.5
                const r = Math.round((raw.x + raw.width) * scaleX) - 0.5
                const btm = Math.round((raw.y + raw.height) * scaleY) - 0.5
                c.strokeRect(l, t, Math.max(0, r - l), Math.max(0, btm - t))
            }
        }

        const b = selectionBounds
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

        // Dashed ghost is the fallback until the live object crop is
        // ready; afterwards the box itself follows the moving pixels.
        if (dragging && !movePreviewReady) {
            const g = previewBounds
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

        // Magnetic guides: image centre or edge, only while a drag snaps.
        if (snapGuideX >= 0) {
            const gx = snapGuideX * scaleX
            c.beginPath()
            c.moveTo(gx, visibleRect.y)
            c.lineTo(gx, visibleRect.y + visibleRect.height)
            c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
            c.lineWidth = 3
            c.stroke()
            c.strokeStyle = Theme.accent
            c.lineWidth = 1
            if (typeof c.setLineDash === "function")
                c.setLineDash([3, 4])
            c.stroke()
            if (typeof c.setLineDash === "function")
                c.setLineDash([])
        }
        if (snapGuideY >= 0) {
            const gy = snapGuideY * scaleY
            c.beginPath()
            c.moveTo(visibleRect.x, gy)
            c.lineTo(visibleRect.x + visibleRect.width, gy)
            c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.45)
            c.lineWidth = 3
            c.stroke()
            c.strokeStyle = Theme.accent
            c.lineWidth = 1
            if (typeof c.setLineDash === "function")
                c.setLineDash([3, 4])
            c.stroke()
            if (typeof c.setLineDash === "function")
                c.setLineDash([])
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
