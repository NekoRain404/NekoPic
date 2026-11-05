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
    /*! Value the fill originates from. Set to 0 for bipolar controls. */
    property real origin: from
    property int decimals: 0
    property string suffix: ""
    property string accessibleName: ""

    readonly property real span: Math.max(to - from, 0.0001)
    readonly property real position: Math.max(0, Math.min(1, (value - from) / span))
    readonly property real originPosition: Math.max(0, Math.min(1, (origin - from) / span))
    readonly property real fillFrom: Math.min(position, originPosition)
    readonly property real fillWidth: Math.abs(position - originPosition)
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
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.duration(Motion.fast)
            easing.type: Motion.decelerateEasing
        }
    }

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
        // Treat keyboard/double-click like a drag so external value syncs do
        // not snap the handle back between preview and finish.
        dragging = true
        begin()
        value = clamped(v)
        preview(value)
        finish(value)
        dragging = false
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
        color: handleArea.containsMouse && root.enabled
               ? Theme.alpha(Theme.textSecondary, 0.65)
               : Theme.alpha(Theme.textSecondary, 0.45)
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    Rectangle {
        id: fill
        x: track.x + track.width * root.fillFrom
        y: track.y
        width: track.width * root.fillWidth
        height: track.height
        radius: track.radius
        color: !root.enabled ? Theme.textTertiary
             : (root.dragging || handleArea.containsMouse) ? Theme.accentHover : Theme.accent
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        Behavior on x {
            enabled: !root.dragging
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        Behavior on width {
            enabled: !root.dragging
            NumberAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
    }

    // Subtle centre tick so bipolar controls read at a glance.
    Rectangle {
        visible: root.originPosition > 0.001 && root.originPosition < 0.999
        x: track.x + track.width * root.originPosition - width / 2
        y: (root.height - height) / 2
        width: 1
        height: Theme.sliderTrackHeight + 6
        radius: 0.5
        color: Theme.textTertiary
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
        border.color: root.activeFocus ? Theme.focusRing
                    : (root.dragging || handleArea.containsMouse) ? Theme.textTertiary
                    : Theme.alpha(Theme.textSecondary, 0.65)
        scale: root.dragging ? 1.20 : (handleArea.containsMouse ? 1.14 : 1.0)
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
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

    NekoToolTip {
        visible: root.enabled && (root.dragging || handleArea.containsMouse)
        text: root.accessibleName.length > 0
              ? root.accessibleName + " · " + root.valueText
              : root.valueText
        accessibleName: text
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
