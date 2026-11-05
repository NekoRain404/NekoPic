pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    GradeControls — per-zone colour grading.

    The three zones (shadows / midtones / highlights) expose hue, saturation
    and luminance under `grade.<zone>.<field>`, plus the shared blending and
    balance keys. A live swatch previews the current zone colour, including
    values that have not yet round-tripped through the controller.
*/
ColumnLayout {
    id: root

    property var values: ({})
    property bool controlsEnabled: true
    property string zone: "shadows"
    /*! Local overlay so drags update the swatch before the controller echoes. */
    property var localValues: ({})

    readonly property var zones: [
        { id: "shadows", label: qsTr("阴影") },
        { id: "midtones", label: qsTr("中间调") },
        { id: "highlights", label: qsTr("高光") }
    ]

    readonly property var effectiveValues: {
        const merged = {}
        if (values) {
            for (const key in values)
                merged[key] = values[key]
        }
        for (const key in localValues)
            merged[key] = localValues[key]
        return merged
    }

    readonly property real previewHue: gradeValue("hue")
    readonly property real previewSaturation: gradeValue("saturation")
    readonly property real previewLuminance: gradeValue("luminance")
    readonly property color previewColor: Qt.hsla(
        Math.max(0, Math.min(1, previewHue / 360)),
        Math.max(0, Math.min(1, previewSaturation / 100)),
        Math.max(0.05, Math.min(0.95, 0.5 + previewLuminance * 0.004)),
        1)

    signal gestureStarted(string key)
    signal gesturePreview(string key, real value)
    signal gestureFinished(string key, real value)

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    onValuesChanged: mergeExternal()

    function keyFor(field) {
        return "grade." + root.zone + "." + field
    }

    function gradeValue(field) {
        const key = keyFor(field)
        if (root.localValues && root.localValues[key] !== undefined)
            return Number(root.localValues[key])
        if (root.values && root.values[key] !== undefined)
            return Number(root.values[key])
        return 0
    }

    function setLocal(key, value) {
        const next = {}
        for (const existing in root.localValues)
            next[existing] = root.localValues[existing]
        next[key] = value
        root.localValues = next
    }

    function mergeExternal() {
        const next = {}
        for (const existing in root.localValues)
            next[existing] = root.localValues[existing]
        let changed = false
        if (root.values) {
            for (const key in root.values) {
                if (key.indexOf("grade.") === 0 && next[key] !== root.values[key]) {
                    next[key] = root.values[key]
                    changed = true
                }
            }
        }
        if (changed)
            root.localValues = next
    }

    function resetCurrent() {
        const fields = ["hue", "saturation", "luminance"]
        const sliders = [hueSlider, saturationSlider, luminanceSlider]
        for (let i = 0; i < fields.length; ++i) {
            const key = keyFor(fields[i])
            root.gestureStarted(key)
            root.gesturePreview(key, 0)
            root.gestureFinished(key, 0)
            setLocal(key, 0)
            sliders[i].setLocalValue(0)
        }
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("分别为阴影、中间调和高光加入色彩。")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        wrapMode: Text.WordWrap
    }

    InspectorChoices {
        Layout.fillWidth: true
        model: root.zones
        currentId: root.zone
        objectNamePrefix: "grade-zone-"
        accessibleName: qsTr("Colour grading zone")
        onSelected: function(id) { root.zone = id }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingMd

        Rectangle {
            objectName: "grade-swatch"
            implicitWidth: 40
            implicitHeight: 40
            radius: width / 2
            color: root.previewColor
            border.width: Theme.borderWidth * 2
            border.color: Theme.alpha(Theme.textPrimary, 0.16)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Label {
                text: qsTr("色彩预览")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }
            Label {
                text: "H " + Math.round(root.previewHue) + "°  ·  S "
                      + Math.round(root.previewSaturation) + "  ·  L "
                      + Math.round(root.previewLuminance)
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }
    }

    Section {
        title: qsTr("区域色彩")

        AdjustmentSlider {
            id: hueSlider
            values: root.effectiveValues
            adjustKey: root.keyFor("hue")
            label: qsTr("色相")
            from: 0
            to: 360
            defaultValue: 0
            origin: 0
            suffix: "°"
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-grade-" + root.zone + "-hue"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) {
                root.setLocal(key, value)
                root.gesturePreview(key, value)
            }
            onGestureFinished: function(key, value) {
                root.setLocal(key, value)
                root.gestureFinished(key, value)
            }
        }

        AdjustmentSlider {
            id: saturationSlider
            values: root.effectiveValues
            adjustKey: root.keyFor("saturation")
            label: qsTr("着色饱和度")
            from: 0
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-grade-" + root.zone + "-saturation"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) {
                root.setLocal(key, value)
                root.gesturePreview(key, value)
            }
            onGestureFinished: function(key, value) {
                root.setLocal(key, value)
                root.gestureFinished(key, value)
            }
        }

        AdjustmentSlider {
            id: luminanceSlider
            values: root.effectiveValues
            adjustKey: root.keyFor("luminance")
            label: qsTr("亮度")
            from: -100
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-grade-" + root.zone + "-luminance"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) {
                root.setLocal(key, value)
                root.gesturePreview(key, value)
            }
            onGestureFinished: function(key, value) {
                root.setLocal(key, value)
                root.gestureFinished(key, value)
            }
        }
    }

    Section {
        title: qsTr("混合")

        AdjustmentSlider {
            values: root.effectiveValues
            adjustKey: "grade.blending"
            label: qsTr("混合范围")
            from: 0
            to: 100
            defaultValue: 50
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-grade-blending"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) { root.gesturePreview(key, value) }
            onGestureFinished: function(key, value) { root.gestureFinished(key, value) }
        }

        AdjustmentSlider {
            values: root.effectiveValues
            adjustKey: "grade.balance"
            label: qsTr("明暗平衡")
            from: -100
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-grade-balance"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) { root.gesturePreview(key, value) }
            onGestureFinished: function(key, value) { root.gestureFinished(key, value) }
        }
    }

    NekoButton {
        objectName: "grade-reset"
        Layout.fillWidth: true
        text: qsTr("重置当前区域")
        variant: "secondary"
        implicitHeight: Theme.controlHeightSm
        enabled: root.controlsEnabled
        onClicked: root.resetCurrent()
    }
}
