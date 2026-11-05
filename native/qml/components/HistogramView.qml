import QtQuick
import "../UI"

/*!
    HistogramView — compact 256-bin histogram.

    `bins` is a JS array of counts (0..255 channel or luma). Rendering is a
    single Canvas pass over the visible width; the component never allocates
    per-bin items. Empty or null data draws a subtle baseline.
*/
Item {
    id: root

    property var bins: []
    property color lineColor: Theme.accent
    property color fillColor: Theme.alpha(Theme.accent, 0.18)
    property color baselineColor: Theme.separator
    property int binCount: 256

    implicitHeight: 64

    readonly property real peak: {
        if (!bins || bins.length === 0) return 0
        let max = 0
        for (let i = 0; i < bins.length; ++i) max = Math.max(max, Number(bins[i]) || 0)
        return max
    }

    onBinsChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = root.baselineColor
            ctx.fillRect(0, height - 1, width, 1)
            if (!root.bins || root.bins.length === 0 || root.peak <= 0)
                return
            const count = root.bins.length
            const step = width / count
            ctx.beginPath()
            ctx.moveTo(0, height - 1)
            for (let i = 0; i < count; ++i) {
                const value = Math.max(0, Number(root.bins[i]) || 0) / root.peak
                const x = i * step
                const y = height - 1 - value * (height - 4)
                ctx.lineTo(x, y)
            }
            ctx.lineTo(width, height - 1)
            ctx.closePath()
            ctx.fillStyle = root.fillColor
            ctx.fill()
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = 1
            ctx.stroke()
        }
    }
}
