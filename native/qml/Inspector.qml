pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "UI"
import "inspector"
import "components"

/*!
    Inspector — the native five-tab colour workspace.

    The inspector is deliberately colour-only: the five Adjust sub-tabs
    (基础, HSL, 曲线, 色彩分级, 细节/效果) form one continuous workspace and
    presets live in the standalone FiltersPanel tool surface. All adjustment
    gestures are forwarded through the public adjustmentStarted / Preview /
    Finished signals so Main.qml and the controller need no changes.

    Compatibility:
      • `currentTab` and the filter* properties/signals are retained so the
        existing shell binding keeps compiling while it migrates the filter
        workspace to its own host. They no longer drive any UI here.
*/
Rectangle {
    id: root

    property var theme
    /*! Compatibility only: 0 = colour workspace, 1 = external filters tool. */
    property int currentTab: 0
    /*! Adjust sub-tab: 0 基础, 1 HSL, 2 曲线, 3 色彩分级, 4 细节/效果. */
    property int adjustTab: 0
    property bool adjustmentsEnabled: false
    property var adjustmentValues: ({})
    property var histogramBins: []

    /*! Retained for Main's filter bindings until the standalone host lands. */
    property bool filtersEnabled: false
    property bool filterIntensityEnabled: filtersEnabled
    property string filterPreset: "none"
    property real filterIntensity: 100
    property bool previewsAvailable: false
    property double previewRevision: 0

    readonly property var adjustTabLabels: [
        qsTr("基础"), "HSL", qsTr("曲线"), qsTr("色彩分级"), qsTr("细节/效果")
    ]

    readonly property var lightModel: [
        { key: "exposure", label: qsTr("曝光") },
        { key: "brightness", label: qsTr("亮度") },
        { key: "contrast", label: qsTr("对比度") },
        { key: "highlights", label: qsTr("高光") },
        { key: "shadows", label: qsTr("阴影") },
        { key: "whites", label: qsTr("白色色阶") },
        { key: "blacks", label: qsTr("黑色色阶") }
    ]
    readonly property var whiteBalanceModel: [
        { key: "temperature", label: qsTr("色温") },
        { key: "tint", label: qsTr("色调 · 绿 — 洋红") }
    ]
    readonly property var colorModel: [
        { key: "saturation", label: qsTr("饱和度") },
        { key: "vibrance", label: qsTr("自然饱和度") }
    ]
    readonly property var textureModel: [
        { key: "texture", label: qsTr("纹理"), min: 0 },
        { key: "clarity", label: qsTr("清晰度"), min: 0 },
        { key: "dehaze", label: qsTr("去雾"), min: 0 },
        { key: "sharpen", label: qsTr("锐化"), min: 0 }
    ]
    readonly property var noiseModel: [
        { key: "noise", label: qsTr("明度降噪"), min: 0 },
        { key: "colorNoise", label: qsTr("彩色降噪"), min: 0 }
    ]
    readonly property var effectModel: [
        { key: "vignette", label: qsTr("暗角"), min: -100 },
        { key: "feather", label: qsTr("暗角羽化"), min: 0, def: 50 },
        { key: "grain", label: qsTr("颗粒"), min: 0 },
        { key: "fade", label: qsTr("褪色"), min: 0 }
    ]

    signal adjustmentStarted(string key)
    signal adjustmentPreview(string key, real value)
    signal adjustmentFinished(string key, real value)
    signal adjustmentReset()
    signal autoEnhanceRequested()

    /*! Compatibility signals for the external filter workspace. */
    signal filterSelected(string preset)
    signal filterIntensityStarted()
    signal filterIntensityPreview(real value)
    signal filterIntensityFinished(real value)

    color: Theme.panel
    implicitWidth: 320

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Workspace heading ──────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingXl
            Layout.rightMargin: Theme.spacingXl
            Layout.topMargin: Theme.spacingXl
            Layout.bottomMargin: Theme.spacingMd
            spacing: Theme.spacingXs

            Text {
                Layout.fillWidth: true
                text: qsTr("LIGHT & COLOR")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.fontWeightDemiBold
                font.letterSpacing: Theme.trackingWide
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("Adjust")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontHeadline
                font.weight: Theme.fontWeightDemiBold
                elide: Text.ElideRight
            }
        }

        // ── Fixed five-subtab strip ────────────────────────────────────────
        AdjustTabBar {
            objectName: "adjust-subtabs"
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingXl
            Layout.rightMargin: Theme.spacingXl
            Layout.bottomMargin: Theme.spacingSm
            model: root.adjustTabLabels
            currentIndex: root.adjustTab
            onActivated: function(index) { root.adjustTab = index }
        }

        // ── Section heading + reset ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingXl
            Layout.rightMargin: Theme.spacingXl
            Layout.bottomMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            Text {
                Layout.fillWidth: true
                text: root.adjustTabLabels[Math.max(0, Math.min(4, root.adjustTab))]
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightDemiBold
                elide: Text.ElideRight
            }

            NekoButton {
                id: resetButton
                objectName: "adjustment-reset"
                enabled: root.adjustmentsEnabled
                text: qsTr("Reset")
                variant: "ghost"
                iconName: "reset"
                implicitHeight: Theme.controlHeightSm
                leftPadding: Theme.spacingSm
                rightPadding: Theme.spacingSm
                accessibleName: qsTr("Reset all adjustments")
                onClicked: root.adjustmentReset()
            }
        }

        // ── Scrollable colour controls ─────────────────────────────────────
        ScrollView {
            id: inspectorScroll
            objectName: "inspector-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ScrollBar.vertical: NekoScrollBar {
                objectName: "inspector-scrollbar"
                policy: ScrollBar.AlwaysOff
                accessibleName: qsTr("Inspector content scroll")
            }
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width
                spacing: 0

                // 基础
                ColumnLayout {
                    visible: root.adjustTab === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXl
                    Layout.rightMargin: Theme.spacingXl
                    Layout.topMargin: Theme.spacingMd
                    Layout.bottomMargin: Theme.spacingLg
                    spacing: Theme.spacingLg

                    NekoButton {
                        objectName: "adjustment-auto"
                        Layout.fillWidth: true
                        text: qsTr("Auto enhance")
                        variant: "secondary"
                        enabled: root.adjustmentsEnabled
                        onClicked: root.autoEnhanceRequested()
                    }

                    Section {
                        title: qsTr("明暗")
                        Repeater {
                            model: root.lightModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: -100
                                to: 100
                                defaultValue: 0
                                origin: 0
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }

                    Section {
                        title: qsTr("白平衡")
                        Repeater {
                            model: root.whiteBalanceModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: -100
                                to: 100
                                defaultValue: 0
                                origin: 0
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }

                    HistogramView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        bins: root.histogramBins
                    }

                    Section {
                        title: qsTr("色彩")
                        Repeater {
                            model: root.colorModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: -100
                                to: 100
                                defaultValue: 0
                                origin: 0
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }
                }

                // HSL
                HslControls {
                    objectName: "hsl-controls"
                    visible: root.adjustTab === 1
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXl
                    Layout.rightMargin: Theme.spacingXl
                    Layout.topMargin: Theme.spacingMd
                    Layout.bottomMargin: Theme.spacingLg
                    values: root.adjustmentValues
                    controlsEnabled: root.adjustmentsEnabled
                    onGestureStarted: function(key) { root.adjustmentStarted(key) }
                    onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                    onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                }

                // 曲线
                CurveEditor {
                    objectName: "curve-editor"
                    visible: root.adjustTab === 2
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXl
                    Layout.rightMargin: Theme.spacingXl
                    Layout.topMargin: Theme.spacingMd
                    Layout.bottomMargin: Theme.spacingLg
                    values: root.adjustmentValues
                    controlsEnabled: root.adjustmentsEnabled
                    onGestureStarted: function(key) { root.adjustmentStarted(key) }
                    onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                    onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                }

                // 色彩分级
                GradeControls {
                    objectName: "grade-controls"
                    visible: root.adjustTab === 3
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXl
                    Layout.rightMargin: Theme.spacingXl
                    Layout.topMargin: Theme.spacingMd
                    Layout.bottomMargin: Theme.spacingLg
                    values: root.adjustmentValues
                    controlsEnabled: root.adjustmentsEnabled
                    onGestureStarted: function(key) { root.adjustmentStarted(key) }
                    onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                    onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                }

                // 细节/效果
                ColumnLayout {
                    visible: root.adjustTab === 4
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXl
                    Layout.rightMargin: Theme.spacingXl
                    Layout.topMargin: Theme.spacingMd
                    Layout.bottomMargin: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Section {
                        title: qsTr("质感与细节")
                        Repeater {
                            model: root.textureModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: modelData.min
                                to: 100
                                defaultValue: modelData.def !== undefined ? modelData.def : 0
                                origin: modelData.min < 0 ? 0 : modelData.min
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }

                    Section {
                        title: qsTr("降噪")
                        Repeater {
                            model: root.noiseModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: modelData.min
                                to: 100
                                defaultValue: modelData.def !== undefined ? modelData.def : 0
                                origin: modelData.min < 0 ? 0 : modelData.min
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }

                    Section {
                        title: qsTr("效果")
                        Repeater {
                            model: root.effectModel
                            delegate: AdjustmentSlider {
                                required property var modelData
                                values: root.adjustmentValues
                                adjustKey: modelData.key
                                label: modelData.label
                                from: modelData.min
                                to: 100
                                defaultValue: modelData.def !== undefined ? modelData.def : 0
                                origin: modelData.min < 0 ? 0 : modelData.min
                                controlEnabled: root.adjustmentsEnabled
                                sliderObjectName: "adjustment-" + modelData.key
                                onGestureStarted: function(key) { root.adjustmentStarted(key) }
                                onGesturePreview: function(key, value) { root.adjustmentPreview(key, value) }
                                onGestureFinished: function(key, value) { root.adjustmentFinished(key, value) }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
