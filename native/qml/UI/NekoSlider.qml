import QtQuick
import "."

/*!
    NekoSlider — custom track, handle and gesture contract.

    Emits begin() once when a gesture starts, preview(value) for every value
    change while dragging or using the keyboard, and finish(value) once when
    it ends. Double-click restores defaultValue. Arrow/Home/End keys are
    supported; the handle and focus ring are fully theme-driven.
*/
Item {
    id: root

    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    property real defaultValue: 0
    property int decimals: 0
    property string suffix: ""
    property string accessibleName: ""

    readonly property real span: Math.max(to - from, 0.0001)
    readonly property real position: Math.max(0, Math.min(1, (value - from) / span))
    readonly property real handleSize: Theme.sliderHandleSize
    readonly property real trackStart: handleSize / 2
    readonly property real trackEnd: width - handleSize / 2
    readonly property real trackWidth: Math.max(0, trackEnd - trackStart)
    readonly property string valueText: {
        const rounded = Math.abs(value) < 0.000001 ? 0 : value
        return (decimals > 0 ? rounded.toFixed(decimals) : Math.round(rounded).toString()) + suffix
    }
    property bool dragging: false

    signal begin()
    signal preview(real value)
    signal finish(real value)
    signal reset()

    implicitWidth: Theme.controlMinWidth
    implicitHeight: Theme.sliderHeight
    activeFocusOnTab: true
    opacity: enabled ? 1 : Theme.opacityDisabled

    Accessible.role: Accessible.Slider
    Accessible.name: accessibleName
    Accessible.focusable: true
    Accessible.focused: activeFocus
    Accessible.pressed: root.dragging

    function isSame(a, b) {
        return Math.abs(a - b) < 0.000001
    }

    function clamped(v) {
        const lo = Math.min(from, to)
        const hi = Math.max(from, to)
        let result = Math.max(lo, Math.min(hi, v))
        if (stepSize > 0)
            result = lo + Math.round((result - lo) / stepSize) * stepSize
        return Math.max(lo, Math.min(hi, result))
    }

    function setValueFromX(px) {
        const ratio = Math.max(0, Math.min(1, (px - trackStart) / Math.max(trackWidth, 1)))
        commitPreview(clamped(from + ratio * (to - from)))
    }

    function commitPreview(v) {
        if (isSame(v, value))
            return
        value = v
        preview(v)
    }

    function beginGesture() {
        if (!dragging) {
            dragging = true
            begin()
        }
    }

    function endGesture() {
        if (dragging) {
            dragging = false
            finish(value)
        }
    }

    // Keyboard and double-click commit as a complete begin/preview/finish
    // gesture so controllers can treat them exactly like a drag.
    function commit(v) {
        begin()
        value = clamped(v)
        preview(value)
        finish(value)
    }

    function resetToDefault() {
        commit(defaultValue)
        reset()
    }

    Keys.onPressed: function(event) {
        if (!enabled)
            return
        const step = stepSize > 0 ? stepSize : span / 100
        let handled = true
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down)
            commit(value - step)
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up)
            commit(value + step)
        else if (event.key === Qt.Key_Home)
            commit(from)
        else if (event.key === Qt.Key_End)
            commit(to)
        else
            handled = false
        if (handled)
            event.accepted = true
    }

    Rectangle {
        id: track
        x: root.trackStart
        y: (root.height - height) / 2
        width: root.trackWidth
        height: Theme.sliderTrackHeight
        radius: height / 2
        color: Theme.border
    }

    Rectangle {
        id: fill
        x: track.x
        y: track.y
        width: track.width * root.position
        height: track.height
        radius: track.radius
        color: root.enabled ? Theme.accent : Theme.textTertiary
        Behavior on width {
            enabled: !root.dragging
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    Rectangle {
        id: handle
        width: root.handleSize
        height: root.handleSize
        radius: width / 2
        x: root.trackStart + root.position * root.trackWidth - width / 2
        y: (root.height - height) / 2
        color: Theme.controlKnob
        border.width: Theme.borderWidth
        border.color: root.activeFocus ? Theme.focusRing : Theme.panel
        scale: root.dragging ? 1.08 : (handleArea.containsMouse ? 1.02 : 1.0)
        Behavior on x {
            enabled: !root.dragging
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && root.enabled
    }

    MouseArea {
        id: handleArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: function(event) {
            root.forceActiveFocus()
            root.beginGesture()
            root.setValueFromX(event.x)
        }
        onPositionChanged: function(event) {
            if (pressed)
                root.setValueFromX(event.x)
        }
        onReleased: root.endGesture()
        onDoubleClicked: root.resetToDefault()
    }
}
