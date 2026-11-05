pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    CurveEditor — five-point tone curve with RGB / R / G / B channels.

    Points are fixed on the x axis (input 0/25/50/75/100) and draggable on the
    y axis (output 0..100). Each drag is exactly one begin/preview/finish
    transaction for `curve.<channel>.<index>`. Numeric NekoSliders below the
    chart provide a precise, fully accessible fallback, and the three preset
    buttons commit all five points as five complete transactions.
*/
ColumnLayout {
    id: root

    property var values: ({})
    property bool controlsEnabled: true
    property string channel: "RGB"
    property var points: [0, 25, 50, 75, 100]
    property bool dragging: false
    property int dragIndex: -1

    readonly property var channelOptions: [
        { id: "RGB", label: "RGB" },
        { id: "R", label: "R" },
        { id: "G", label: "G" },
        { id: "B", label: "B" }
    ]
    readonly property color curveColor: {
        switch (channel) {
        case "R": return Qt.hsla(0.00, 0.62, 0.62, 1)
        case "G": return Qt.hsla(0.38, 0.42, 0.58, 1)
        case "B": return Qt.hsla(0.60, 0.52, 0.64, 1)
        default: return Theme.accent
        }
    }
    readonly property var effectiveValues: {
        const merged = {}
        if (values) {
            for (const key in values)
                merged[key] = values[key]
        }
        for (let i = 0; i < 5; ++i)
            merged["curve." + channel + "." + i] = points[i]
        return merged
    }

    signal gestureStarted(string key)
    signal gesturePreview(string key, real value)
    signal gestureFinished(string key, real value)

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    onValuesChanged: syncFromValues(false)
    onChannelChanged: {
        syncFromValues(true)
        canvas.requestPaint()
    }
    onPointsChanged: canvas.requestPaint()
    Component.onCompleted: syncFromValues(true)

    function keyFor(index) {
        return "curve." + root.channel + "." + index
    }

    function clampValue(value) {
        return Math.max(0, Math.min(100, Math.round(value)))
    }

    function syncFromValues(reload) {
        if (root.dragging)
            return
        const base = (reload || !root.points || root.points.length !== 5)
                ? [0, 25, 50, 75, 100] : root.points.slice()
        let changed = reload
        for (let i = 0; i < 5; ++i) {
            const key = "curve." + root.channel + "." + i
            let value = base[i]
            if (root.values && root.values[key] !== undefined)
                value = Number(root.values[key])
            value = clampValue(value)
            if (base[i] !== value)
                changed = true
            base[i] = value
        }
        if (changed)
            root.points = base
    }

    function setPointValue(index, value) {
        const next = clampValue(value)
        if (root.points[index] === next)
            return
        const copy = root.points.slice()
        copy[index] = next
        root.points = copy
    }

    function beginPoint(index) {
        if (root.dragging || !root.controlsEnabled)
            return
        root.dragging = true
        root.dragIndex = index
        root.gestureStarted(keyFor(index))
    }

    function updateFromChartY(index, chartY) {
        if (!root.dragging || index !== root.dragIndex)
            return
        const plotH = Math.max(1, chart.plotH)
        const ratio = Math.max(0, Math.min(1, (chartY - chart.plotY) / plotH))
        const value = clampValue((1 - ratio) * 100)
        if (value === root.points[index])
            return
        setPointValue(index, value)
        root.gesturePreview(keyFor(index), value)
    }

    function finishPoint() {
        if (!root.dragging)
            return
        const index = root.dragIndex
        root.dragging = false
        root.dragIndex = -1
        root.gestureFinished(keyFor(index), root.points[index])
    }

    function commitPoint(index, value) {
        if (!root.controlsEnabled)
            return
        const next = clampValue(value)
        if (next === root.points[index])
            return
        const key = keyFor(index)
        root.gestureStarted(key)
        setPointValue(index, next)
        root.gesturePreview(key, next)
        root.gestureFinished(key, next)
    }

    function applyPreset(target) {
        if (!root.controlsEnabled)
            return
        const next = [0, 25, 50, 75, 100]
        for (let i = 0; i < 5; ++i)
            next[i] = clampValue(target[i])
        // Points move first so controller echoes during the five transactions
        // see the final curve; undo/redo still receives one transaction each.
        root.points = next
        for (let i = 0; i < 5; ++i) {
            const key = keyFor(i)
            root.gestureStarted(key)
            root.gesturePreview(key, next[i])
            root.gestureFinished(key, next[i])
        }
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("拖动控制点调整明暗关系。")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        wrapMode: Text.WordWrap
    }

    InspectorChoices {
        Layout.fillWidth: true
        model: root.channelOptions
        currentId: root.channel
        objectNamePrefix: "curve-channel-"
        accessibleName: qsTr("Curve channel")
        onSelected: function(id) { root.channel = id }
    }

    Rectangle {
        id: chart
        objectName: "curve-chart"
        Layout.fillWidth: true
        implicitHeight: 168
        radius: Theme.radiusSm
        color: Theme.background
        border.width: Theme.borderWidth
        border.color: Theme.separator
        clip: true

        readonly property real plotInset: Theme.spacingMd
        readonly property real plotX: plotInset
        readonly property real plotY: plotInset
        readonly property real plotW: Math.max(1, width - plotInset * 2)
        readonly property real plotH: Math.max(1, height - plotInset * 2)

        Accessible.role: Accessible.Graphic
        Accessible.name: qsTr("Tone curve editor")

        Canvas {
            id: canvas
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (chart.plotW <= 1 || chart.plotH <= 1)
                    return
                ctx.save()
                ctx.translate(chart.plotX, chart.plotY)
                const w = chart.plotW
                const h = chart.plotH

                ctx.lineWidth = Theme.borderWidth
                ctx.strokeStyle = Theme.separator
                for (let i = 1; i < 4; ++i) {
                    const x = w * i / 4
                    ctx.beginPath()
                    ctx.moveTo(x, 0)
                    ctx.lineTo(x, h)
                    ctx.stroke()
                    const y = h * i / 4
                    ctx.beginPath()
                    ctx.moveTo(0, y)
                    ctx.lineTo(w, y)
                    ctx.stroke()
                }

                ctx.strokeStyle = Theme.alpha(Theme.textTertiary, 0.55)
                ctx.beginPath()
                ctx.moveTo(0, h)
                ctx.lineTo(w, 0)
                ctx.stroke()

                ctx.strokeStyle = root.curveColor
                ctx.lineWidth = Theme.indicatorWidth
                ctx.beginPath()
                for (let i = 0; i < root.points.length; ++i) {
                    const x = w * i / 4
                    const y = h * (1 - root.points[i] / 100)
                    if (i === 0)
                        ctx.moveTo(x, y)
                    else
                        ctx.lineTo(x, y)
                }
                ctx.stroke()
                ctx.restore()
            }
        }

        Repeater {
            model: 5

            delegate: Item {
                id: handle
                required property int index

                objectName: "curve-point-" + index
                width: 22
                height: 22
                x: chart.plotX + index * chart.plotW / 4 - width / 2
                y: chart.plotY + (1 - root.points[index] / 100) * chart.plotH - height / 2
                activeFocusOnTab: true
                z: 2

                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Curve point %1, output %2")
                                .arg(index + 1).arg(Math.round(root.points[index]))
                Accessible.focusable: true
                Accessible.pressed: root.dragging && root.dragIndex === index

                Keys.onPressed: function(event) {
                    if (!root.controlsEnabled)
                        return
                    const step = (event.modifiers & Qt.ShiftModifier) ? 5 : 1
                    let handled = true
                    if (event.key === Qt.Key_Up)
                        root.commitPoint(index, root.points[index] + step)
                    else if (event.key === Qt.Key_Down)
                        root.commitPoint(index, root.points[index] - step)
                    else if (event.key === Qt.Key_Home)
                        root.commitPoint(index, 0)
                    else if (event.key === Qt.Key_End)
                        root.commitPoint(index, 100)
                    else
                        handled = false
                    if (handled)
                        event.accepted = true
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.dragging && root.dragIndex === handle.index ? 13 : 9
                    height: width
                    radius: width / 2
                    color: root.controlsEnabled ? root.curveColor : Theme.textTertiary
                    border.width: Theme.focusRingWidth
                    border.color: Theme.panel
                    Behavior on width {
                        NumberAnimation {
                            duration: Motion.duration(Motion.fast)
                            easing.type: Motion.decelerateEasing
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: Theme.focusRingWidth
                    border.color: Theme.focusRing
                    visible: handle.activeFocus
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.controlsEnabled
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true

                    onPressed: function(mouse) {
                        handle.forceActiveFocus()
                        root.beginPoint(handle.index)
                        root.updateFromChartY(handle.index, mouse.y + handle.y)
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            root.updateFromChartY(handle.index, mouse.y + handle.y)
                    }
                    onReleased: root.finishPoint()
                    onCanceled: root.finishPoint()
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: qsTr("暗部")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
        }
        Item { Layout.fillWidth: true }
        Label {
            text: qsTr("输入亮度 →")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
        }
        Item { Layout.fillWidth: true }
        Label {
            text: qsTr("亮部")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        NekoButton {
            objectName: "curve-preset-linear"
            Layout.fillWidth: true
            text: qsTr("线性")
            variant: "ghost"
            implicitHeight: Theme.controlHeightSm
            leftPadding: Theme.spacingXs
            rightPadding: Theme.spacingXs
            enabled: root.controlsEnabled
            onClicked: root.applyPreset([0, 25, 50, 75, 100])
        }
        NekoButton {
            objectName: "curve-preset-contrast"
            Layout.fillWidth: true
            text: qsTr("柔和 S 曲线")
            variant: "ghost"
            implicitHeight: Theme.controlHeightSm
            leftPadding: Theme.spacingXs
            rightPadding: Theme.spacingXs
            enabled: root.controlsEnabled
            onClicked: root.applyPreset([0, 17, 50, 83, 100])
        }
        NekoButton {
            objectName: "curve-preset-fade"
            Layout.fillWidth: true
            text: qsTr("抬起暗部")
            variant: "ghost"
            implicitHeight: Theme.controlHeightSm
            leftPadding: Theme.spacingXs
            rightPadding: Theme.spacingXs
            enabled: root.controlsEnabled
            onClicked: root.applyPreset([12, 32, 54, 77, 100])
        }
    }

    Section {
        title: qsTr("精确调整")
        caption: root.channel

        Repeater {
            model: 5

            delegate: AdjustmentSlider {
                id: pointSlider
                required property int index

                values: root.effectiveValues
                adjustKey: "curve." + root.channel + "." + index
                label: qsTr("输入 %1 · 输出").arg(index * 25)
                from: 0
                to: 100
                defaultValue: index * 25
                origin: 0
                controlEnabled: root.controlsEnabled
                sliderObjectName: "adjustment-curve-" + root.channel + "-" + index
                onGestureStarted: function(key) { root.gestureStarted(key) }
                onGesturePreview: function(key, value) {
                    root.setPointValue(pointSlider.index, value)
                    root.gesturePreview(key, value)
                }
                onGestureFinished: function(key, value) {
                    root.setPointValue(pointSlider.index, value)
                    root.gestureFinished(key, value)
                }
            }
        }
    }
}
