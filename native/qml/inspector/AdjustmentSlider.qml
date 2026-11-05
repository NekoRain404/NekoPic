pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AdjustmentSlider — label, live value readout and a NekoSlider bound to a
    controller key.

    The slider itself is the gesture owner: NekoSlider emits one begin() when
    a drag or keyboard commit starts and one finish() when it ends. This
    wrapper forwards those as keyed signals and mirrors `values[key]` into the
    handle whenever the controller changes and the user is not dragging.
*/
ColumnLayout {
    id: root

    /*! Flat adjustment map from the controller (`adjustmentValues`). */
    property var values: ({})
    /*! Controller key emitted with every gesture signal. */
    property string adjustKey: ""
    property string label: ""
    property real from: -100
    property real to: 100
    property real defaultValue: 0
    property real origin: 0
    /*! Appended to the numeric readout, e.g. "°" for a hue control. */
    property string suffix: ""
    property bool controlEnabled: true
    /*! objectName of the inner NekoSlider, so tests can drive it directly. */
    property string sliderObjectName: ""

    readonly property bool bipolar: from < 0 && to > 0
    readonly property alias sliderItem: slider
    /*! True once a gesture supplied a value the controller has not echoed. */
    property bool localOverride: false

    signal gestureStarted(string key)
    signal gesturePreview(string key, real value)
    signal gestureFinished(string key, real value)

    Layout.fillWidth: true
    spacing: Theme.spacingXs
    opacity: controlEnabled ? 1 : Theme.opacityMuted

    /*! Imperatively show a value (used by reset actions). */
    function setLocalValue(value) {
        localOverride = true
        slider.value = Math.max(from, Math.min(to, value))
    }

    /*! Pull controller values into the handle without fighting a live drag. */
    function syncValue(force) {
        if (slider.dragging)
            return
        const hasValue = root.values !== undefined && root.values !== null
                && root.adjustKey.length > 0 && root.values[root.adjustKey] !== undefined
        if (hasValue) {
            root.localOverride = false
            const next = Number(root.values[root.adjustKey])
            if (isFinite(next) && Math.abs(slider.value - next) > 0.000001)
                slider.value = Math.max(root.from, Math.min(root.to, next))
        } else if (force || !root.localOverride) {
            if (Math.abs(slider.value - root.defaultValue) > 0.000001)
                slider.value = root.defaultValue
        }
    }

    onValuesChanged: syncValue(false)
    onAdjustKeyChanged: {
        localOverride = false
        syncValue(true)
    }
    Component.onCompleted: syncValue(true)

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: root.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Rectangle {
            implicitWidth: Math.max(38, valueLabel.implicitWidth + Theme.spacingMd)
            implicitHeight: 18
            radius: Theme.radiusXs
            color: Theme.background
            border.width: Theme.borderWidth
            border.color: Theme.separator

            Label {
                id: valueLabel
                anchors.centerIn: parent
                text: (root.bipolar && slider.value > 0 ? "+" : "")
                      + Math.round(slider.value) + root.suffix
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }
    }

    NekoSlider {
        id: slider
        objectName: root.sliderObjectName
        Layout.fillWidth: true
        enabled: root.controlEnabled
        from: root.from
        to: root.to
        stepSize: 1
        defaultValue: root.defaultValue
        origin: root.origin
        accessibleName: root.label
        onBegin: root.gestureStarted(root.adjustKey)
        onPreview: function(value) {
            root.localOverride = true
            root.gesturePreview(root.adjustKey, value)
        }
        onFinish: function(value) {
            root.gestureFinished(root.adjustKey, value)
        }
    }
}
