import QtQuick

Item {
    id: root
    property bool active: false
    property bool inputEnabled: true
    property int imageWidth: 0
    property int imageHeight: 0
    property real aspectRatio: 0
    property rect selection: Qt.rect(0, 0, 0, 0)
    property rect visibleRect: Qt.rect(0, 0, width, height)
    readonly property real scaleX: imageWidth > 0 ? width / imageWidth : 1
    readonly property real scaleY: imageHeight > 0 ? height / imageHeight : 1
    signal applyRequested(rect area)
    signal cancelled()
    visible: active
    enabled: active && inputEnabled
    focus: active
    onActiveChanged: if (active) { resetSelection(); forceActiveFocus() }
    onImageWidthChanged: resetSelection()
    onImageHeightChanged: resetSelection()
    onAspectRatioChanged: resetSelection()
    onSelectionChanged: drawing.requestPaint()
    Keys.onReturnPressed: function(event) { commit(); event.accepted = true }
    Keys.onEnterPressed: function(event) { commit(); event.accepted = true }
    Keys.onEscapePressed: function(event) { cancelled(); event.accepted = true }

    function commit() {
        if (active && inputEnabled && selection.width >= 1 && selection.height >= 1)
            applyRequested(selection)
    }
    function resetSelection() {
        let w = imageWidth, h = imageHeight
        if (aspectRatio > 0 && w > 0 && h > 0) {
            w = Math.min(w, h * aspectRatio)
            h = w / aspectRatio
        }
        selection = Qt.rect((imageWidth - w) / 2, (imageHeight - h) / 2, w, h)
    }
    function pointAt(x, y) {
        return Qt.point(Math.max(0, Math.min(imageWidth, x / scaleX)),
                        Math.max(0, Math.min(imageHeight, y / scaleY)))
    }
    function hitTest(x, y) {
        const s = selection
        const left = s.x * scaleX, right = (s.x + s.width) * scaleX
        const top = s.y * scaleY, bottom = (s.y + s.height) * scaleY
        const tolerance = 9
        const nearL = Math.abs(x - left) <= tolerance, nearR = Math.abs(x - right) <= tolerance
        const nearT = Math.abs(y - top) <= tolerance, nearB = Math.abs(y - bottom) <= tolerance
        if ((nearL || nearR) && (nearT || nearB)) return (nearT ? "n" : "s") + (nearL ? "w" : "e")
        if (y >= top - tolerance && y <= bottom + tolerance) {
            if (nearL) return "w"
            if (nearR) return "e"
        }
        if (x >= left - tolerance && x <= right + tolerance) {
            if (nearT) return "n"
            if (nearB) return "s"
        }
        return x > left && x < right && y > top && y < bottom ? "move" : "create"
    }
    // Coordinates remain in source pixels while only the viewport gets a raster backing.
    function resizeFrom(anchor, moving) {
        const dx = moving.x - anchor.x, dy = moving.y - anchor.y
        const signX = dx < 0 ? -1 : 1, signY = dy < 0 ? -1 : 1
        let w = Math.abs(dx), h = Math.abs(dy)
        if (aspectRatio > 0) {
            w = Math.max(w, h * aspectRatio)
            w = Math.min(w, signX > 0 ? imageWidth - anchor.x : anchor.x,
                         (signY > 0 ? imageHeight - anchor.y : anchor.y) * aspectRatio)
            h = w / aspectRatio
        }
        selection = Qt.rect(signX > 0 ? anchor.x : anchor.x - w,
                            signY > 0 ? anchor.y : anchor.y - h, w, h)
    }
    Canvas {
        id: drawing
        objectName: "cropPreview"
        x: Math.max(0, root.visibleRect.x)
        y: Math.max(0, root.visibleRect.y)
        width: Math.max(0, Math.min(root.width, root.visibleRect.x + root.visibleRect.width) - x)
        height: Math.max(0, Math.min(root.height, root.visibleRect.y + root.visibleRect.height) - y)
        onXChanged: requestPaint()
        onYChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset()
            c.translate(-x, -y)
            const s = root.selection
            const l = s.x * root.scaleX, t = s.y * root.scaleY
            const w = s.width * root.scaleX, h = s.height * root.scaleY
            c.fillStyle = "#99000000"
            c.fillRect(0, 0, root.width, t)
            c.fillRect(0, t + h, root.width, root.height - t - h)
            c.fillRect(0, t, l, h)
            c.fillRect(l + w, t, root.width - l - w, h)
            c.strokeStyle = "#ffffff"; c.lineWidth = 1
            c.strokeRect(l, t, w, h)
            c.globalAlpha = 0.5; c.beginPath()
            for (let i = 1; i <= 2; ++i) {
                c.moveTo(l + w * i / 3, t); c.lineTo(l + w * i / 3, t + h)
                c.moveTo(l, t + h * i / 3); c.lineTo(l + w, t + h * i / 3)
            }
            c.stroke(); c.globalAlpha = 1; c.fillStyle = "#ffffff"
            const handles = [[l,t],[l+w/2,t],[l+w,t],[l,t+h/2],
                             [l+w,t+h/2],[l,t+h],[l+w/2,t+h],[l+w,t+h]]
            for (const p of handles) c.fillRect(p[0] - 3, p[1] - 3, 6, 6)
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        hoverEnabled: true
        cursorShape: !pressed ? Qt.CrossCursor : mode === "move" ? Qt.ClosedHandCursor : Qt.CrossCursor
        property string mode: ""
        property point start
        property rect initial
        onWheel: function(event) { event.accepted = false }
        onPressed: function(mouse) {
            root.forceActiveFocus()
            mode = root.hitTest(mouse.x, mouse.y)
            start = root.pointAt(mouse.x, mouse.y)
            initial = root.selection
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            const p = root.pointAt(mouse.x, mouse.y), s = initial
            if (mode === "move") {
                root.selection = Qt.rect(Math.max(0, Math.min(root.imageWidth - s.width, s.x + p.x - start.x)),
                                         Math.max(0, Math.min(root.imageHeight - s.height, s.y + p.y - start.y)), s.width, s.height)
            } else if (mode === "create") {
                root.resizeFrom(start, p)
            } else if (mode.length === 2) {
                root.resizeFrom(Qt.point(mode.indexOf("w") >= 0 ? s.x + s.width : s.x,
                                         mode.indexOf("n") >= 0 ? s.y + s.height : s.y), p)
            } else if (root.aspectRatio <= 0) {
                const l = mode === "w" ? Math.min(p.x, s.x + s.width - 1) : s.x
                const t = mode === "n" ? Math.min(p.y, s.y + s.height - 1) : s.y
                const r = mode === "e" ? Math.max(p.x, s.x + 1) : s.x + s.width
                const b = mode === "s" ? Math.max(p.y, s.y + 1) : s.y + s.height
                root.selection = Qt.rect(l, t, r - l, b - t)
            } else {
                // Edge resizing keeps the opposite edge fixed and expands about its center.
                const horizontal = mode === "w" || mode === "e"
                const maxW = horizontal ? (mode === "w" ? s.x + s.width : root.imageWidth - s.x)
                                       : 2 * Math.min(s.x + s.width / 2, root.imageWidth - s.x - s.width / 2)
                const maxH = horizontal ? 2 * Math.min(s.y + s.height / 2, root.imageHeight - s.y - s.height / 2)
                                       : (mode === "n" ? s.y + s.height : root.imageHeight - s.y)
                const desired = horizontal ? Math.abs(p.x - (mode === "w" ? s.x + s.width : s.x))
                                           : Math.abs(p.y - (mode === "n" ? s.y + s.height : s.y)) * root.aspectRatio
                const w = Math.max(0, Math.min(maxW, maxH * root.aspectRatio, desired))
                const h = w / root.aspectRatio
                root.selection = Qt.rect(horizontal ? (mode === "w" ? s.x + s.width - w : s.x) : s.x + (s.width - w) / 2,
                                         horizontal ? s.y + (s.height - h) / 2 : (mode === "n" ? s.y + s.height - h : s.y), w, h)
            }
        }
        onDoubleClicked: root.commit()
    }
}
