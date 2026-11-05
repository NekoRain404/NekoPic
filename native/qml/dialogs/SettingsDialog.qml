import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    SettingsDialog — the product's single preferences surface.

    The dialog is intentionally stateless with respect to persistence: the
    integrator seeds the public properties from SettingsManager and persists
    every settingChanged()/localeSelected() signal immediately. Controls apply
    changes live, while the scrollable body keeps the dialog inside a 900×700
    window on compact displays.

    Localised labels follow the `localeId` property directly so the page reads
    correctly in both shipped languages even before translation catalogues are
    regenerated for this dialog.
*/
NekoDialog {
    id: root

    // ── Public contract ────────────────────────────────────────────────────
    property string themeMode: "dark"
    property alias reduceMotion: reduceMotionToggle.checked
    property alias gpuPreviewEnabled: gpuPreviewToggle.checked
    property int exportQuality: -1
    property color jpegBackground: "#ffffff"
    property string localeId: "zh_CN"
    property alias confirmOnClose: confirmOnCloseToggle.checked
    property alias showCheckerboard: checkerboardToggle.checked
    property var localeOptions: [
        { id: "en", nativeName: "English" },
        { id: "zh_CN", nativeName: "简体中文" }
    ]
    property bool busy: false

    /*! Emitted for every user-driven change; the parent persists `value`. */
    signal settingChanged(string key, var value)
    /*! Emitted in addition to settingChanged("locale", id). */
    signal localeSelected(string id)

    // ── Internal state ─────────────────────────────────────────────────────
    readonly property var _themeModes: ["system", "light", "dark"]
    readonly property color whiteBackground: "#ffffff"
    readonly property color blackBackground: "#000000"
    readonly property color warmGreyBackground: "#8b8780"

    property int _lastQuality: 90
    property bool _accepted: false

    /*! Keeps the scroll body above the fixed reset row and dialog footer. */
    readonly property real _scrollMaxHeight: {
        const host = root.parent && root.parent.height > 0 ? root.parent.height : 700
        return Math.max(120, host - 300)
    }

    width: Math.min(560, parent ? Math.max(Theme.controlMinWidth, parent.width - Theme.spacing3xl * 2)
                                : 560)
    title: root._tr("偏好设置", "Settings")
    description: root._tr("更改会立即应用并自动保存。",
                          "Changes apply immediately and are saved automatically.")
    acceptText: root._tr("完成", "Done")
    accessibleName: root._tr("偏好设置", "Settings")
    showCloseButton: true

    onAccepted: root._accepted = true
    onClosed: {
        if (!root._accepted)
            root.rejected()
        root._accepted = false
    }

    // ── Localisation ───────────────────────────────────────────────────────
    function _tr(zh, en) {
        return root.localeId === "zh_CN" ? zh : en
    }

    function _themeIndex(mode) {
        for (let i = 0; i < root._themeModes.length; ++i) {
            if (root._themeModes[i] === mode)
                return i
        }
        return -1
    }

    function _hasLocale(id) {
        for (let i = 0; i < root.localeOptions.length; ++i) {
            if (root.localeOptions[i].id === id)
                return true
        }
        return false
    }

    // ── Live updates ───────────────────────────────────────────────────────
    function _commit(key, value) {
        if (root.busy)
            return
        root.settingChanged(key, value)
    }

    function _setExportQuality(value) {
        if (root.busy)
            return
        const clamped = Math.max(-1, Math.min(100, Math.round(value)))
        if (root.exportQuality === clamped)
            return
        root.exportQuality = clamped
        root.settingChanged("exportQuality", clamped)
    }

    function _setBackground(value) {
        if (root.busy)
            return
        const opaque = Qt.rgba(value.r, value.g, value.b, 1)
        if (Qt.colorEqual(root.jpegBackground, opaque))
            return
        root.jpegBackground = opaque
        root.settingChanged("jpegBackground", opaque)
    }

    function _selectLocale(id) {
        if (root.busy || root.localeId === id)
            return
        root.localeId = id
        root.localeSelected(id)
        root.settingChanged("locale", id)
    }

    function _syncQuality() {
        if (qualitySlider && !qualitySlider.dragging)
            qualitySlider.value = root.exportQuality >= 0 ? root.exportQuality : root._lastQuality
        if (qualityDefaultToggle)
            qualityDefaultToggle.checked = root.exportQuality < 0
    }

    function resetToDefaults() {
        if (root.busy)
            return

        root._lastQuality = 90
        root.themeMode = "dark"
        root.reduceMotion = false
        root.gpuPreviewEnabled = true
        root.exportQuality = -1
        root.jpegBackground = root.whiteBackground
        root.confirmOnClose = true
        root.showCheckerboard = true
        root.localeId = "zh_CN"

        root.settingChanged("themeMode", "dark")
        root.settingChanged("reduceMotion", false)
        root.settingChanged("gpuPreviewEnabled", true)
        root.settingChanged("exportQuality", -1)
        root.settingChanged("jpegBackground", root.whiteBackground)
        root.settingChanged("confirmOnClose", true)
        root.settingChanged("showCheckerboard", true)
        root.localeSelected("zh_CN")
        root.settingChanged("locale", "zh_CN")
    }

    // ── Validation and control synchronisation ─────────────────────────────
    onThemeModeChanged: {
        const index = root._themeIndex(root.themeMode)
        if (index < 0) {
            root.themeMode = "dark"
            return
        }
        if (themeControl)
            themeControl.currentIndex = index
    }

    onExportQualityChanged: {
        const clamped = Math.max(-1, Math.min(100, Math.round(root.exportQuality)))
        if (root.exportQuality !== clamped) {
            root.exportQuality = clamped
            return
        }
        if (root.exportQuality >= 0)
            root._lastQuality = root.exportQuality
        root._syncQuality()
    }

    onJpegBackgroundChanged: {
        if (Math.abs(root.jpegBackground.a - 1) > 0.0001) {
            root.jpegBackground = Qt.rgba(root.jpegBackground.r, root.jpegBackground.g,
                                          root.jpegBackground.b, 1)
        }
    }

    onLocaleIdChanged: {
        if (!root._hasLocale(root.localeId))
            root.localeId = "zh_CN"
    }

    Component.onCompleted: {
        if (themeControl)
            themeControl.currentIndex = Math.max(0, root._themeIndex(root.themeMode))
        root._syncQuality()
    }

    // ── Body ───────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingMd

        Flickable {
            id: scroller
            objectName: "settings-scroll"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(settingsColumn.implicitHeight, root._scrollMaxHeight)
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: NekoScrollBar {
                policy: ScrollBar.AsNeeded
                accessibleName: root._tr("设置内容滚动", "Settings content scroll")
            }

            ColumnLayout {
                id: settingsColumn
                width: scroller.width
                spacing: Theme.spacingXl

                // ── Appearance ─────────────────────────────────────────────
                NekoSectionHeader {
                    objectName: "settings-section-appearance"
                    Layout.fillWidth: true
                    text: root._tr("外观", "Appearance")
                    eyebrow: true
                    showDivider: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("主题", "Theme")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("跟随系统设置或选择固定外观。",
                                           "Follow the system setting or choose a fixed appearance.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    NekoSegmentedControl {
                        id: themeControl
                        objectName: "settings-theme"
                        Layout.preferredWidth: 210
                        Layout.alignment: Qt.AlignVCenter
                        enabled: !root.busy
                        accessibleName: root._tr("主题", "Theme")
                        model: [
                            root._tr("系统", "System"),
                            root._tr("浅色", "Light"),
                            root._tr("深色", "Dark")
                        ]

                        onActivated: function(index) {
                            if (root.busy)
                                return
                            const mode = root._themeModes[index]
                            if (mode === undefined || root.themeMode === mode)
                                return
                            root.themeMode = mode
                            root.settingChanged("themeMode", mode)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("减少动效", "Reduce motion")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("关闭界面动画和过渡效果。",
                                           "Turn off interface animations and transitions.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    NekoToggle {
                        id: reduceMotionToggle
                        objectName: "settings-reduce-motion"
                        checked: false
                        enabled: !root.busy
                        accessibleName: root._tr("减少动效", "Reduce motion")
                        onClicked: root._commit("reduceMotion", checked)
                    }
                }

                // ── Editing ────────────────────────────────────────────────
                NekoSectionHeader {
                    objectName: "settings-section-editing"
                    Layout.fillWidth: true
                    text: root._tr("编辑", "Editing")
                    eyebrow: true
                    showDivider: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("GPU 预览", "GPU preview")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("调整时使用硬件加速的实时预览。",
                                           "Use hardware-accelerated live previews while adjusting.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    NekoToggle {
                        id: gpuPreviewToggle
                        objectName: "settings-gpu-preview"
                        checked: true
                        enabled: !root.busy
                        accessibleName: root._tr("GPU 预览", "GPU preview")
                        onClicked: root._commit("gpuPreviewEnabled", checked)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("显示透明棋盘格", "Show transparency checkerboard")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("在透明区域后方显示棋盘格图案。",
                                           "Show a checkerboard pattern behind transparent areas.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    NekoToggle {
                        id: checkerboardToggle
                        objectName: "settings-checkerboard"
                        checked: true
                        enabled: !root.busy
                        accessibleName: root._tr("显示透明棋盘格", "Show transparency checkerboard")
                        onClicked: root._commit("showCheckerboard", checked)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("关闭前确认", "Confirm before closing")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("有未保存更改时提示确认。",
                                           "Ask for confirmation when there are unsaved changes.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    NekoToggle {
                        id: confirmOnCloseToggle
                        objectName: "settings-confirm-on-close"
                        checked: true
                        enabled: !root.busy
                        accessibleName: root._tr("关闭前确认", "Confirm before closing")
                        onClicked: root._commit("confirmOnClose", checked)
                    }
                }

                // ── Export ─────────────────────────────────────────────────
                NekoSectionHeader {
                    objectName: "settings-section-export"
                    Layout.fillWidth: true
                    text: root._tr("导出", "Export")
                    eyebrow: true
                    showDivider: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            text: root._tr("导出质量", "Export quality")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("仅对支持质量设置的格式有效（JPEG、WebP、AVIF 等）。",
                                           "Applies to formats that support quality (JPEG, WebP, AVIF, and others).")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }
                    }

                    Text {
                        objectName: "settings-quality-value"
                        text: root.exportQuality < 0 ? root._tr("编码器默认", "Codec default")
                                                     : root.exportQuality + "%"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.weight: Theme.fontWeightMedium
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                NekoSlider {
                    id: qualitySlider
                    objectName: "settings-quality"
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    defaultValue: 90
                    enabled: !root.busy && !qualityDefaultToggle.checked
                    accessibleName: root._tr("导出质量", "Export quality")
                    onPreview: function(value) { root._setExportQuality(value) }
                    onFinish: function(value) { root._setExportQuality(value) }
                }

                NekoToggle {
                    id: qualityDefaultToggle
                    objectName: "settings-quality-default"
                    text: root._tr("使用编码器默认值", "Use codec default")
                    checked: true
                    enabled: !root.busy
                    accessibleName: root._tr("使用编码器默认质量", "Use codec default quality")
                    onClicked: {
                        if (checked)
                            root._setExportQuality(-1)
                        else
                            root._setExportQuality(root._lastQuality)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root._tr("JPEG 背景", "JPEG background")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    NekoSwatch {
                        objectName: "settings-background-white"
                        swatchColor: root.whiteBackground
                        selected: Qt.colorEqual(root.jpegBackground, root.whiteBackground)
                        enabled: !root.busy
                        accessibleName: root._tr("白色背景", "White background")
                        onClicked: root._setBackground(root.whiteBackground)
                    }

                    NekoSwatch {
                        objectName: "settings-background-black"
                        swatchColor: root.blackBackground
                        selected: Qt.colorEqual(root.jpegBackground, root.blackBackground)
                        enabled: !root.busy
                        accessibleName: root._tr("黑色背景", "Black background")
                        onClicked: root._setBackground(root.blackBackground)
                    }

                    NekoSwatch {
                        objectName: "settings-background-warm-grey"
                        swatchColor: root.warmGreyBackground
                        selected: Qt.colorEqual(root.jpegBackground, root.warmGreyBackground)
                        enabled: !root.busy
                        accessibleName: root._tr("暖灰色背景", "Warm grey background")
                        onClicked: root._setBackground(root.warmGreyBackground)
                    }

                    Item { Layout.fillWidth: true }
                }

                Text {
                    Layout.fillWidth: true
                    text: root._tr("JPEG 不支持透明度，透明区域会填充此颜色。",
                                   "JPEG has no transparency; transparent areas are filled with this colour.")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                    lineHeight: Theme.lineHeightNormal
                    wrapMode: Text.WordWrap
                }

                // ── Language ───────────────────────────────────────────────
                NekoSectionHeader {
                    objectName: "settings-section-language"
                    Layout.fillWidth: true
                    text: root._tr("语言", "Language")
                    eyebrow: true
                    showDivider: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root._tr("界面语言会立即切换。", "The interface language changes immediately.")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                    lineHeight: Theme.lineHeightNormal
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Repeater {
                        model: root.localeOptions

                        delegate: NekoButton {
                            required property var modelData
                            objectName: "settings-locale-" + modelData.id
                            text: modelData.nativeName
                            variant: root.localeId === modelData.id ? "primary" : "secondary"
                            enabled: !root.busy
                            Accessible.checkable: true
                            Accessible.checked: root.localeId === modelData.id
                            onClicked: root._selectLocale(modelData.id)
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ── About ──────────────────────────────────────────────────
                NekoSectionHeader {
                    objectName: "settings-section-about"
                    Layout.fillWidth: true
                    text: root._tr("关于", "About")
                    eyebrow: true
                    showDivider: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    Text {
                        objectName: "settings-about-version"
                        text: "NekoPic " + Qt.application.version
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.fontWeightMedium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root._tr("本地优先的桌面照片编辑器。",
                                       "A local-first desktop photo editor.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        objectName: "settings-about-qt"
                        text: "Qt " + Qt.application.qtVersion
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontCaption
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root._tr("所有照片都保留在本设备上。",
                                       "All photos stay on this device.")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontCaption
                        lineHeight: Theme.lineHeightNormal
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.borderWidth
            color: Theme.separator
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            NekoButton {
                objectName: "settings-reset"
                text: root._tr("恢复默认设置", "Reset to defaults")
                variant: "ghost"
                enabled: !root.busy
                onClicked: root.resetToDefaults()
            }

            Item { Layout.fillWidth: true }
        }
    }
}
