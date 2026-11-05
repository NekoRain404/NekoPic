import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    SettingsDialog — the product's single, complete preferences surface.

    The page is a two-column layout inside the shared modal NekoDialog: a fixed
    category rail on the left and a scrollable, per-category body on the right.
    The dialog header (title, description, close) and footer (Done) stay fixed;
    only the right-hand content scrolls, and its scrollbar is deliberately
    invisible while wheel/touch scrolling keeps working.

    The dialog is stateless with respect to persistence: the integrator seeds
    the public properties from SettingsManager, applies changes live and
    persists every settingChanged()/localeSelected() signal immediately.

    Localised labels follow `localeId` directly so the page reads correctly in
    both shipped languages even before translation catalogues are regenerated.
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
    property alias recoveryEnabled: recoveryToggle.checked
    property string startupTool: "adjust"

    property var localeOptions: [
        { id: "en", nativeName: "English" },
        { id: "zh_CN", nativeName: "简体中文" }
    ]

    /*! Read-only capability summary supplied by the application shell. */
    property var formatCapabilities: ({ readableCount: 0, writableCount: 0 })
    /*! Recovery snapshot metadata, supplied by RecoveryStore when available. */
    property bool recoveryAvailable: false
    property string recoverySourceName: ""
    property string recoveryCapturedAt: ""
    property string recoveryImageSize: ""

    property bool busy: false
    /*! One of categories[i].id. */
    property string currentCategory: "appearance"

    readonly property var categories: [
        { id: "appearance", label: root._tr("外观", "Appearance") },
        { id: "editing", label: root._tr("编辑", "Editing") },
        { id: "export", label: root._tr("导出", "Export") },
        { id: "language", label: root._tr("语言", "Language") },
        { id: "recovery", label: root._tr("恢复与安全", "Recovery & Safety") },
        { id: "about", label: root._tr("关于", "About") }
    ]

    readonly property var startupToolOptions: [
        { id: "adjust", label: root._tr("调色", "Adjust") },
        { id: "filters", label: root._tr("滤镜", "Filters") },
        { id: "select", label: root._tr("选择", "Select") },
        { id: "pan", label: root._tr("平移", "Pan") },
        { id: "brush", label: root._tr("画笔", "Brush") },
        { id: "text", label: root._tr("文字", "Text") },
        { id: "shapes", label: root._tr("形状", "Shapes") },
        { id: "mosaic", label: root._tr("马赛克", "Mosaic") },
        { id: "eye", label: root._tr("吸管", "Eyedropper") },
        { id: "crop", label: root._tr("裁剪", "Crop") }
    ]

    /*! Emitted for every user-driven change; the parent persists `value`. */
    signal settingChanged(string key, var value)
    /*! Emitted in addition to settingChanged("locale", id). */
    signal localeSelected(string id)
    /*! The integrator shows the keyboard-shortcuts reference. */
    signal shortcutsRequested()
    /*! The integrator discards the existing crash-recovery snapshot. */
    signal recoveryDiscardRequested()

    // ── Internal state ─────────────────────────────────────────────────────
    readonly property var _themeModes: ["system", "light", "dark"]
    readonly property var _startupToolIds: [
        "adjust", "filters", "select", "pan", "brush",
        "text", "shapes", "mosaic", "eye", "crop"
    ]
    readonly property color whiteBackground: "#ffffff"
    readonly property color blackBackground: "#000000"
    readonly property color warmGreyBackground: "#8b8780"

    property int _lastQuality: 90
    property bool _accepted: false

    // ── Page geometry ──────────────────────────────────────────────────────
    // Wide enough to read as a preferences page, capped so it still leaves a
    // visible scrim on 1100×720 and 1440×900 windows.
    width: {
        const hostWidth = root.parent && root.parent.width > 0 ? root.parent.width : 1440
        return Math.max(720, Math.min(820, hostWidth - Theme.spacing3xl * 2))
    }
    height: {
        const hostHeight = root.parent && root.parent.height > 0 ? root.parent.height : 900
        return Math.min(640, hostHeight - Theme.spacing2xl)
    }

    title: root._tr("偏好设置", "Settings")
    description: root._tr("更改会立即应用并自动保存。",
                          "Changes apply immediately and are saved automatically.")
    acceptText: root._tr("完成", "Done")
    acceptObjectName: "settings-done"
    accessibleName: root._tr("偏好设置", "Settings")
    showCloseButton: true
    bodyFillHeight: true

    onAccepted: root._accepted = true
    onClosed: {
        if (!root._accepted)
            root.rejected()
        root._accepted = false
    }

    // ── Localisation and validation helpers ────────────────────────────────
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

    function _hasCategory(id) {
        for (let i = 0; i < root.categories.length; ++i) {
            if (root.categories[i].id === id)
                return true
        }
        return false
    }

    function _hasStartupTool(id) {
        return root._startupToolIds.indexOf(id) >= 0
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

    function _selectStartupTool(id) {
        if (root.busy || !root._hasStartupTool(id) || root.startupTool === id)
            return
        root.startupTool = id
        root.settingChanged("startupTool", id)
    }

    function _activateCategory(id) {
        if (!root._hasCategory(id) || root.currentCategory === id)
            return
        root.currentCategory = id
        if (scroller)
            scroller.contentY = 0
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
        root.recoveryEnabled = true
        root.startupTool = "adjust"
        root.localeId = "zh_CN"

        root.settingChanged("themeMode", "dark")
        root.settingChanged("reduceMotion", false)
        root.settingChanged("gpuPreviewEnabled", true)
        root.settingChanged("exportQuality", -1)
        root.settingChanged("jpegBackground", root.whiteBackground)
        root.settingChanged("confirmOnClose", true)
        root.settingChanged("showCheckerboard", true)
        root.settingChanged("recoveryEnabled", true)
        root.settingChanged("startupTool", "adjust")
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

    onStartupToolChanged: {
        if (!root._hasStartupTool(root.startupTool))
            root.startupTool = "adjust"
    }

    onCurrentCategoryChanged: {
        if (!root._hasCategory(root.currentCategory))
            root.currentCategory = "appearance"
    }

    Component.onCompleted: {
        if (themeControl)
            themeControl.currentIndex = Math.max(0, root._themeIndex(root.themeMode))
        if (!root._hasCategory(root.currentCategory))
            root.currentCategory = "appearance"
        if (!root._hasStartupTool(root.startupTool))
            root.startupTool = "adjust"
        root._syncQuality()
    }

    // ── Reusable settings row ──────────────────────────────────────────────
    // Label + explanatory hint on the left, a single control on the right.
    // The control is the default property so rows stay declarative.
    component SettingRow: RowLayout {
        id: row
        property string label: ""
        property string hint: ""
        default property alias controlData: controlHost.data

        Layout.fillWidth: true
        spacing: Theme.spacingLg

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Text {
                Layout.fillWidth: true
                text: row.label
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: row.hint
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }
        }

        Item {
            id: controlHost
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }

    // ── Body: category rail + scrollable content ───────────────────────────
    RowLayout {
        objectName: "settings-page"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.spacingXl

        // Left: fixed category navigation.
        ColumnLayout {
            id: navColumn
            objectName: "settings-nav"
            Layout.preferredWidth: 168
            Layout.minimumWidth: 168
            Layout.maximumWidth: 168
            Layout.fillHeight: true
            spacing: Theme.spacingXs

            Accessible.role: Accessible.PageTabList
            Accessible.name: root._tr("设置分类", "Settings categories")

            Repeater {
                id: categoryRepeater
                model: root.categories

                delegate: AbstractButton {
                    id: categoryButton
                    required property var modelData
                    required property int index

                    objectName: "settings-category-" + modelData.id
                    Layout.fillWidth: true
                    implicitHeight: Theme.controlHeight
                    padding: 0
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    activeFocusOnTab: true
                    text: modelData.label

                    readonly property bool current: root.currentCategory === modelData.id

                    Accessible.role: Accessible.PageTab
                    Accessible.name: categoryButton.text
                    Accessible.checkable: true
                    Accessible.checked: categoryButton.current
                    Accessible.focused: categoryButton.activeFocus

                    KeyNavigation.up: index > 0 ? categoryRepeater.itemAt(index - 1) : null
                    KeyNavigation.down: index < categoryRepeater.count - 1
                                         ? categoryRepeater.itemAt(index + 1) : null

                    onClicked: {
                        root._activateCategory(modelData.id)
                        categoryButton.forceActiveFocus()
                    }

                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: categoryButton.current ? Theme.selection
                             : categoryButton.hovered ? Theme.hover
                             : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.duration(Motion.fast)
                                easing.type: Motion.decelerateEasing
                            }
                        }

                        Rectangle {
                            visible: categoryButton.current
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingXs
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.indicatorWidth
                            height: Theme.indicatorHeight
                            radius: width / 2
                            color: Theme.accent
                        }
                    }

                    contentItem: Text {
                        leftPadding: Theme.spacingMd + Theme.spacingSm
                        rightPadding: Theme.spacingSm
                        text: categoryButton.text
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                        font.weight: categoryButton.current
                                     ? Theme.fontWeightMedium : Theme.fontWeightRegular
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Theme.focusRingOffset
                        radius: Theme.radiusSm + Theme.focusRingOffset
                        color: "transparent"
                        border.width: Theme.focusRingWidth
                        border.color: Theme.focusRing
                        visible: categoryButton.visualFocus && categoryButton.enabled
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingMd + Theme.spacingSm
                text: "NekoPic " + Qt.application.version
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.borderWidth
            color: Theme.separator
        }

        // Right: one scrollable category at a time. The scrollbar is hidden
        // on purpose; wheel, touch and keyboard scrolling remain available.
        Flickable {
            id: scroller
            objectName: "settings-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 240
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: true

            ScrollBar.vertical: NekoScrollBar {
                objectName: "settings-scrollbar"
                policy: ScrollBar.AlwaysOff
                accessibleName: root._tr("设置内容滚动", "Settings content scroll")
            }

            ColumnLayout {
                id: settingsColumn
                width: scroller.width
                spacing: Theme.spacingXl

                // ── Appearance ─────────────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-appearance"
                    visible: root.currentCategory === "appearance"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    NekoSectionHeader {
                        objectName: "settings-section-appearance"
                        Layout.fillWidth: true
                        text: root._tr("外观", "Appearance")
                        eyebrow: true
                        showDivider: true
                    }

                    SettingRow {
                        label: root._tr("主题", "Theme")
                        hint: root._tr("跟随系统设置，或固定为浅色或深色。",
                                       "Follow the system setting, or use a fixed light or dark appearance.")

                        NekoSegmentedControl {
                            id: themeControl
                            objectName: "settings-theme"
                            width: 210
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

                    SettingRow {
                        label: root._tr("减少动效", "Reduce motion")
                        hint: root._tr("关闭界面动画和过渡效果。",
                                       "Turn off interface animations and transitions.")

                        NekoToggle {
                            id: reduceMotionToggle
                            objectName: "settings-reduce-motion"
                            checked: false
                            enabled: !root.busy
                            accessibleName: root._tr("减少动效", "Reduce motion")
                            onClicked: root._commit("reduceMotion", checked)
                        }
                    }
                }

                // ── Editing ────────────────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-editing"
                    visible: root.currentCategory === "editing"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    NekoSectionHeader {
                        objectName: "settings-section-editing"
                        Layout.fillWidth: true
                        text: root._tr("编辑", "Editing")
                        eyebrow: true
                        showDivider: true
                    }

                    SettingRow {
                        label: root._tr("GPU 预览", "GPU preview")
                        hint: root._tr("调整时使用硬件加速的实时预览；关闭后回退到 CPU。",
                                       "Use hardware-accelerated live previews while adjusting; falls back to CPU when off.")

                        NekoToggle {
                            id: gpuPreviewToggle
                            objectName: "settings-gpu-preview"
                            checked: true
                            enabled: !root.busy
                            accessibleName: root._tr("GPU 预览", "GPU preview")
                            onClicked: root._commit("gpuPreviewEnabled", checked)
                        }
                    }

                    SettingRow {
                        label: root._tr("显示透明棋盘格", "Show transparency checkerboard")
                        hint: root._tr("在透明区域后方显示棋盘格图案。",
                                       "Show a checkerboard pattern behind transparent areas.")

                        NekoToggle {
                            id: checkerboardToggle
                            objectName: "settings-checkerboard"
                            checked: true
                            enabled: !root.busy
                            accessibleName: root._tr("显示透明棋盘格", "Show transparency checkerboard")
                            onClicked: root._commit("showCheckerboard", checked)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        Text {
                            Layout.fillWidth: true
                            text: root._tr("启动工具", "Startup tool")
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontWeightMedium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root._tr("打开图片后默认使用的工具；下次打开图片时生效。",
                                           "Tool selected after an image opens; applies the next time an image is opened.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                            lineHeight: Theme.lineHeightNormal
                            wrapMode: Text.WordWrap
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm

                            Repeater {
                                model: root.startupToolOptions

                                delegate: NekoButton {
                                    required property var modelData
                                    objectName: "settings-startup-tool-" + modelData.id
                                    text: modelData.label
                                    variant: root.startupTool === modelData.id ? "primary" : "secondary"
                                    enabled: !root.busy
                                    Accessible.checkable: true
                                    Accessible.checked: root.startupTool === modelData.id
                                    onClicked: root._selectStartupTool(modelData.id)
                                }
                            }
                        }
                    }
                }

                // ── Export ─────────────────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-export"
                    visible: root.currentCategory === "export"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    NekoSectionHeader {
                        objectName: "settings-section-export"
                        Layout.fillWidth: true
                        text: root._tr("导出", "Export")
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
                                Layout.fillWidth: true
                                text: root._tr("导出质量", "Export quality")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontBody
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

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.borderWidth
                        color: Theme.separator
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Text {
                                Layout.fillWidth: true
                                text: root._tr("JPEG 背景", "JPEG background")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontWeightMedium
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
                        }

                        RowLayout {
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
                        }
                    }
                }

                // ── Language ───────────────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-language"
                    visible: root.currentCategory === "language"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    NekoSectionHeader {
                        objectName: "settings-section-language"
                        Layout.fillWidth: true
                        text: root._tr("语言", "Language")
                        eyebrow: true
                        showDivider: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root._tr("界面语言会立即切换。",
                                       "The interface language changes immediately.")
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
                }

                // ── Recovery and safety ────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-recovery"
                    visible: root.currentCategory === "recovery"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    NekoSectionHeader {
                        objectName: "settings-section-recovery"
                        Layout.fillWidth: true
                        text: root._tr("恢复与安全", "Recovery & Safety")
                        eyebrow: true
                        showDivider: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root._tr(
                                  "自动恢复会在文档有未保存更改时，将渲染结果作为 PNG 快照写入本机应用数据目录。快照不会离开本设备，正常保存或正常退出后会自动删除。恢复后的文档是扁平化图像，对象不可再编辑。",
                                  "Crash recovery writes a PNG snapshot of the rendered document to local app data while there are unsaved changes. Snapshots never leave this device and are removed after a clean save or a normal exit. A recovered document is flattened, so objects cannot be edited.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                        lineHeight: Theme.lineHeightNormal
                        wrapMode: Text.WordWrap
                    }

                    SettingRow {
                        label: root._tr("自动保存恢复快照", "Save recovery snapshots")
                        hint: root._tr("关闭后不再写入新快照，已有快照仍可恢复。",
                                       "When off, no new snapshots are written; existing snapshots can still be recovered.")

                        NekoToggle {
                            id: recoveryToggle
                            objectName: "settings-recovery-enabled"
                            checked: true
                            enabled: !root.busy
                            accessibleName: root._tr("自动保存恢复快照", "Save recovery snapshots")
                            onClicked: root._commit("recoveryEnabled", checked)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: recoveryStatusColumn.implicitHeight + Theme.spacingLg * 2
                        radius: Theme.radiusMd
                        color: Theme.background
                        border.width: Theme.borderWidth
                        border.color: Theme.border

                        ColumnLayout {
                            id: recoveryStatusColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLg
                            spacing: Theme.spacingXs

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm

                                Text {
                                    objectName: "settings-recovery-status"
                                    Layout.fillWidth: true
                                    text: root.recoveryAvailable
                                          ? root._tr("发现可恢复的快照", "Recovery snapshot available")
                                          : root._tr("当前没有恢复快照", "No recovery snapshot available")
                                    color: root.recoveryAvailable ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Theme.fontWeightMedium
                                    wrapMode: Text.WordWrap
                                }

                                NekoButton {
                                    objectName: "settings-recovery-discard"
                                    visible: root.recoveryAvailable
                                    text: root._tr("清除快照", "Discard snapshot")
                                    variant: "ghost"
                                    enabled: !root.busy
                                    onClicked: root.recoveryDiscardRequested()
                                }
                            }

                            Text {
                                objectName: "settings-recovery-details"
                                Layout.fillWidth: true
                                visible: root.recoveryAvailable
                                text: [root.recoverySourceName, root.recoveryCapturedAt,
                                       root.recoveryImageSize].filter(function(part) {
                                           return part !== undefined && part !== null
                                                  && String(part).length > 0
                                       }).join(" · ")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                                lineHeight: Theme.lineHeightNormal
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.recoveryAvailable
                                      ? root._tr("启动时会提示恢复或放弃。", "A prompt offers Restore or Discard at startup.")
                                      : root._tr("编辑文档后，快照会在这里显示。", "Snapshots appear here after a document is edited.")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    SettingRow {
                        label: root._tr("关闭前确认", "Confirm before closing")
                        hint: root._tr("有未保存更改时提示确认。",
                                       "Ask for confirmation when there are unsaved changes.")

                        NekoToggle {
                            id: confirmOnCloseToggle
                            objectName: "settings-confirm-on-close"
                            checked: true
                            enabled: !root.busy
                            accessibleName: root._tr("关闭前确认", "Confirm before closing")
                            onClicked: root._commit("confirmOnClose", checked)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.borderWidth
                        color: Theme.separator
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Text {
                                Layout.fillWidth: true
                                text: root._tr("恢复默认设置", "Reset to defaults")
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontWeightMedium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root._tr("将外观、编辑、导出、语言与恢复选项恢复为默认值。",
                                               "Restore appearance, editing, export, language and recovery options to their defaults.")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                                lineHeight: Theme.lineHeightNormal
                                wrapMode: Text.WordWrap
                            }
                        }

                        NekoButton {
                            objectName: "settings-reset"
                            text: root._tr("恢复默认设置", "Reset to defaults")
                            variant: "secondary"
                            iconName: "reset"
                            enabled: !root.busy
                            onClicked: root.resetToDefaults()
                        }
                    }
                }

                // ── About ──────────────────────────────────────────────────
                ColumnLayout {
                    objectName: "settings-panel-about"
                    visible: root.currentCategory === "about"
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

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
                            font.pixelSize: Theme.fontTitle
                            font.weight: Theme.fontWeightDemiBold
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
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aboutCapabilitiesColumn.implicitHeight + Theme.spacingLg * 2
                        radius: Theme.radiusMd
                        color: Theme.background
                        border.width: Theme.borderWidth
                        border.color: Theme.border

                        ColumnLayout {
                            id: aboutCapabilitiesColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLg
                            spacing: Theme.spacingXs

                            Text {
                                objectName: "settings-about-formats"
                                Layout.fillWidth: true
                                text: {
                                    const readable = root.formatCapabilities
                                                     && root.formatCapabilities.readableCount !== undefined
                                                     ? root.formatCapabilities.readableCount : 0
                                    const writable = root.formatCapabilities
                                                     && root.formatCapabilities.writableCount !== undefined
                                                     ? root.formatCapabilities.writableCount : 0
                                    if (readable <= 0 && writable <= 0)
                                        return root._tr("格式能力将在应用启动后显示。",
                                                        "Format capabilities are shown when the app is running.")
                                    return root._tr("可读取 " + readable + " 种格式 · 可写入 "
                                                    + writable + " 种格式",
                                                    "Reads " + readable + " formats · writes "
                                                    + writable + " formats")
                                }
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root._tr("导出格式取决于当前构建启用的编解码器。",
                                               "Export formats depend on the codecs enabled in this build.")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                                lineHeight: Theme.lineHeightNormal
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        NekoButton {
                            objectName: "settings-shortcuts"
                            text: root._tr("键盘快捷键", "Keyboard shortcuts")
                            variant: "secondary"
                            iconName: "select"
                            enabled: !root.busy
                            onClicked: root.shortcutsRequested()
                        }

                        Item { Layout.fillWidth: true }
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
    }
}
