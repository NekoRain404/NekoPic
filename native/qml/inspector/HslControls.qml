pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    HslControls — eight-colour HSL editor.

    Selecting a swatch changes the keys emitted by the three sliders
    (`hsl.<channel>.<field>`). Resetting emits a complete begin/preview/finish
    transaction for each of the three keys so the controller can undo it as a
    single user action, matching the H5 "reset current colour" button.
*/
ColumnLayout {
    id: root

    property var values: ({})
    property bool controlsEnabled: true
    property string channel: "red"

    readonly property var channels: [
        { id: "red", label: qsTr("红"), hue: 4 },
        { id: "orange", label: qsTr("橙"), hue: 28 },
        { id: "yellow", label: qsTr("黄"), hue: 50 },
        { id: "green", label: qsTr("绿"), hue: 128 },
        { id: "aqua", label: qsTr("青"), hue: 174 },
        { id: "blue", label: qsTr("蓝"), hue: 214 },
        { id: "purple", label: qsTr("紫"), hue: 272 },
        { id: "magenta", label: qsTr("洋红"), hue: 326 }
    ]
    readonly property var currentChannel: channelData(channel)

    signal gestureStarted(string key)
    signal gesturePreview(string key, real value)
    signal gestureFinished(string key, real value)

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    function channelData(id) {
        for (let i = 0; i < channels.length; ++i) {
            if (channels[i].id === id)
                return channels[i]
        }
        return channels[0]
    }

    function keyFor(field) {
        return "hsl." + root.channel + "." + field
    }

    function resetCurrent() {
        const fields = ["hue", "saturation", "luminance"]
        const sliders = [hueSlider, saturationSlider, luminanceSlider]
        for (let i = 0; i < fields.length; ++i) {
            const key = keyFor(fields[i])
            root.gestureStarted(key)
            root.gesturePreview(key, 0)
            root.gestureFinished(key, 0)
            sliders[i].setLocalValue(0)
        }
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("只调整一种颜色，保留其他颜色。")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        wrapMode: Text.WordWrap
    }

    Row {
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacingXs

        Repeater {
            model: root.channels

            delegate: AbstractButton {
                id: swatch
                required property var modelData
                required property int index

                width: 27
                height: 27
                objectName: "hsl-channel-" + modelData.id
                enabled: root.controlsEnabled
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                padding: 0
                opacity: root.controlsEnabled ? 1 : Theme.opacityMuted

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checkable: true
                Accessible.checked: root.channel === modelData.id

                onClicked: root.channel = modelData.id

                ToolTip.visible: swatch.hovered
                ToolTip.text: swatch.modelData.label
                ToolTip.delay: Motion.duration(Motion.slow)

                background: Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Qt.hsla(swatch.modelData.hue / 360, 0.45, 0.62, 1)
                    border.width: root.channel === swatch.modelData.id ? Theme.focusRingWidth : Theme.borderWidth
                    border.color: root.channel === swatch.modelData.id
                                  ? Theme.focusRing : Theme.alpha(Theme.textPrimary, 0.28)
                    scale: root.channel === swatch.modelData.id ? 1.1
                           : swatch.hovered ? 1.04 : 1.0
                    Behavior on scale {
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
                    visible: swatch.activeFocus
                }
            }
        }
    }

    Section {
        title: root.currentChannel.label
        caption: "HSL"

        AdjustmentSlider {
            id: hueSlider
            values: root.values
            adjustKey: root.keyFor("hue")
            label: qsTr("色相")
            from: -100
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-hsl-" + root.channel + "-hue"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) { root.gesturePreview(key, value) }
            onGestureFinished: function(key, value) { root.gestureFinished(key, value) }
        }

        AdjustmentSlider {
            id: saturationSlider
            values: root.values
            adjustKey: root.keyFor("saturation")
            label: qsTr("饱和度")
            from: -100
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-hsl-" + root.channel + "-saturation"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) { root.gesturePreview(key, value) }
            onGestureFinished: function(key, value) { root.gestureFinished(key, value) }
        }

        AdjustmentSlider {
            id: luminanceSlider
            values: root.values
            adjustKey: root.keyFor("luminance")
            label: qsTr("明亮度")
            from: -100
            to: 100
            defaultValue: 0
            origin: 0
            controlEnabled: root.controlsEnabled
            sliderObjectName: "adjustment-hsl-" + root.channel + "-luminance"
            onGestureStarted: function(key) { root.gestureStarted(key) }
            onGesturePreview: function(key, value) { root.gesturePreview(key, value) }
            onGestureFinished: function(key, value) { root.gestureFinished(key, value) }
        }
    }

    NekoButton {
        objectName: "hsl-reset"
        Layout.fillWidth: true
        text: qsTr("重置当前颜色")
        variant: "secondary"
        implicitHeight: Theme.controlHeightSm
        enabled: root.controlsEnabled
        onClicked: root.resetCurrent()
    }
}
