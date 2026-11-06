import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"
import "../settings"

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

    Each category body is a presentation component under qml/settings/. Those
    components receive only the values they display and report user intent
    through signals; validation and persistence stay here.

    All user-visible strings use qsTr with English sources so lupdate collects
    them; the active catalogue is installed by LanguageManager and the page is
    retranslated when the interface language changes. `localeId` still drives
    the selected language chip and validation.
*/
NekoDialog {
    id: root

    // ── Public contract ────────────────────────────────────────────────────
    property string themeMode: "dark"
    property alias reduceMotion: appearancePage.reduceMotion
    property alias gpuPreviewEnabled: editingPage.gpuPreviewEnabled
    property int exportQuality: -1
    property color jpegBackground: "#ffffff"
    property string localeId: "zh_CN"
    property alias confirmOnClose: recoveryPage.confirmOnClose
    property alias showCheckerboard: editingPage.showCheckerboard
    property alias recoveryEnabled: recoveryPage.recoveryEnabled
    property string startupTool: "adjust"
    /*! Empty selects the system UI font. */
    property string uiFontFamily: ""
    /*! UI text scale in percent (80–140). */
    property int uiFontScale: 100
    /*! Whole-interface scale in percent (80–150); applies on next launch. */
    property int uiScale: 100
    /*! Scale active at launch, used for the "restart to apply" note. */
    property int appliedUiScale: 100
    /*! Action key → portable sequence overrides supplied by SettingsManager. */
    property var shortcuts: ({})
    /*! SettingsManager instance used by the shortcut capture control. */
    property var shortcutService: null

    // Kept in sync with LanguageManager::kLocales. Main.qml binds this to
    // language.availableLocales so the manager stays the single source of
    // truth at runtime; the static list keeps the dialog usable standalone.
    property var localeOptions: [
        { id: "en", nativeName: "English" },
        { id: "zh_CN", nativeName: "简体中文" },
        { id: "ja_JP", nativeName: "日本語" },
        { id: "de_DE", nativeName: "Deutsch" }
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
        { id: "appearance", label: qsTr("Appearance") },
        { id: "editing", label: qsTr("Editing") },
        { id: "shortcuts", label: qsTr("Shortcuts") },
        { id: "export", label: qsTr("Export") },
        { id: "language", label: qsTr("Language") },
        { id: "recovery", label: qsTr("Recovery & Safety") },
        { id: "about", label: qsTr("About") }
    ]

    readonly property var startupToolOptions: [
        { id: "adjust", label: qsTr("Adjust") },
        { id: "filters", label: qsTr("Filters") },
        { id: "select", label: qsTr("Select") },
        { id: "pan", label: qsTr("Pan") },
        { id: "brush", label: qsTr("Brush") },
        { id: "text", label: qsTr("Text") },
        { id: "shapes", label: qsTr("Shapes") },
        { id: "mosaic", label: qsTr("Mosaic") },
        { id: "eye", label: qsTr("Eyedropper") },
        { id: "crop", label: qsTr("Crop") }
    ]

    /*! Emitted for every user-driven change; the parent persists `value`. */
    signal settingChanged(string key, var value)
    /*! Emitted in addition to settingChanged("locale", id). */
    signal localeSelected(string id)
    /*! A shortcut override was requested; the integrator persists it. */
    signal shortcutChangeRequested(string key, string sequence)
    /*! The user asked to reset one action to its built-in shortcut. */
    signal shortcutResetRequested(string key)
    /*! The user asked to restore every built-in shortcut. */
    signal shortcutsResetRequested()
    /*! The integrator shows the keyboard-shortcuts reference. */
    signal shortcutsRequested()
    /*! The integrator discards the existing crash-recovery snapshot. */
    signal recoveryDiscardRequested()

    // ── Internal state ─────────────────────────────────────────────────────
    readonly property var _themeModes: ["system", "light", "dark", "midnight", "warm", "graphite", "contrast", "nordic", "sakura", "forest", "solarized"]
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

    title: qsTr("Settings")
    description: qsTr("Changes apply immediately and are saved automatically.")
    acceptText: qsTr("Done")
    acceptObjectName: "settings-done"
    accessibleName: qsTr("Settings")
    showCloseButton: true
    bodyFillHeight: true

    onAccepted: root._accepted = true
    onClosed: {
        if (!root._accepted)
            root.rejected()
        root._accepted = false
    }

    // ── Localisation and validation helpers ────────────────────────────────

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

    function _setUiFontFamily(family) {
        if (root.busy)
            return
        const value = family !== undefined && family !== null ? String(family) : ""
        if (root.uiFontFamily === value)
            return
        root.uiFontFamily = value
        root.settingChanged("uiFontFamily", value)
    }

    function _setUiFontScale(value) {
        if (root.busy)
            return
        const clamped = Math.max(80, Math.min(140, Math.round(value)))
        if (root.uiFontScale === clamped)
            return
        root.uiFontScale = clamped
        root.settingChanged("uiFontScale", clamped)
    }

    function _setUiScale(value) {
        if (root.busy)
            return
        const clamped = Math.max(80, Math.min(150, Math.round(value)))
        if (root.uiScale === clamped)
            return
        root.uiScale = clamped
        root.settingChanged("uiScale", clamped)
    }

    function _activateCategory(id) {
        if (!root._hasCategory(id) || root.currentCategory === id)
            return
        root.currentCategory = id
        if (scroller)
            scroller.contentY = 0
    }

    function _syncQuality() {
        if (exportPage)
            exportPage.syncQuality()
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
        root.uiFontFamily = ""
        root.uiFontScale = 100
        root.uiScale = 100

        root.settingChanged("themeMode", "dark")
        root.settingChanged("reduceMotion", false)
        root.settingChanged("gpuPreviewEnabled", true)
        root.settingChanged("exportQuality", -1)
        root.settingChanged("jpegBackground", root.whiteBackground)
        root.settingChanged("confirmOnClose", true)
        root.settingChanged("showCheckerboard", true)
        root.settingChanged("recoveryEnabled", true)
        root.settingChanged("startupTool", "adjust")
        root.settingChanged("uiFontFamily", "")
        root.settingChanged("uiFontScale", 100)
        root.settingChanged("uiScale", 100)
        root.shortcutsResetRequested()
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

    onUiFontScaleChanged: {
        const clamped = Math.max(80, Math.min(140, Math.round(root.uiFontScale)))
        if (root.uiFontScale !== clamped)
            root.uiFontScale = clamped
    }

    onUiScaleChanged: {
        const clamped = Math.max(80, Math.min(150, Math.round(root.uiScale)))
        if (root.uiScale !== clamped)
            root.uiScale = clamped
    }

    onCurrentCategoryChanged: {
        if (!root._hasCategory(root.currentCategory))
            root.currentCategory = "appearance"
    }

    Component.onCompleted: {
        if (!root._hasCategory(root.currentCategory))
            root.currentCategory = "appearance"
        if (!root._hasStartupTool(root.startupTool))
            root.startupTool = "adjust"
        root._syncQuality()
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
            Accessible.name: qsTr("Settings categories")

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
                accessibleName: qsTr("Settings content scroll")
            }

            ColumnLayout {
                id: settingsColumn
                width: scroller.width
                spacing: Theme.spacingXl

                AppearancePage {
                    id: appearancePage
                    visible: root.currentCategory === "appearance"
                    localeId: root.localeId
                    busy: root.busy
                    themeMode: root.themeMode
                    uiFontFamily: root.uiFontFamily
                    uiFontScale: root.uiFontScale
                    uiScale: root.uiScale
                    appliedUiScale: root.appliedUiScale

                    onThemeSelected: function(mode) {
                        if (root.busy || root.themeMode === mode)
                            return
                        root.themeMode = mode
                        root.settingChanged("themeMode", mode)
                    }
                    onReduceMotionToggled: function(checked) {
                        root._commit("reduceMotion", checked)
                    }
                    onUiFontFamilySelected: function(family) {
                        root._setUiFontFamily(family)
                    }
                    onUiFontScaleSelected: function(percent) {
                        root._setUiFontScale(percent)
                    }
                    onUiScaleSelected: function(percent) {
                        root._setUiScale(percent)
                    }
                }

                EditingPage {
                    id: editingPage
                    visible: root.currentCategory === "editing"
                    localeId: root.localeId
                    busy: root.busy
                    startupTool: root.startupTool
                    startupToolOptions: root.startupToolOptions

                    onGpuPreviewToggled: function(checked) {
                        root._commit("gpuPreviewEnabled", checked)
                    }
                    onCheckerboardToggled: function(checked) {
                        root._commit("showCheckerboard", checked)
                    }
                    onStartupToolSelected: function(id) {
                        root._selectStartupTool(id)
                    }
                }

                ShortcutsPage {
                    id: shortcutsPage
                    visible: root.currentCategory === "shortcuts"
                    busy: root.busy
                    shortcuts: root.shortcuts
                    shortcutService: root.shortcutService

                    onShortcutChangeRequested: function(key, sequence) {
                        root.shortcutChangeRequested(key, sequence)
                    }
                    onShortcutResetRequested: function(key) {
                        root.shortcutResetRequested(key)
                    }
                    onShortcutsResetRequested: root.shortcutsResetRequested()
                }

                ExportPage {
                    id: exportPage
                    visible: root.currentCategory === "export"
                    localeId: root.localeId
                    busy: root.busy
                    exportQuality: root.exportQuality
                    defaultQuality: root._lastQuality
                    jpegBackground: root.jpegBackground

                    onQualityRequested: function(value) {
                        root._setExportQuality(value)
                    }
                    onBackgroundRequested: function(value) {
                        root._setBackground(value)
                    }
                }

                LanguagePage {
                    id: languagePage
                    visible: root.currentCategory === "language"
                    localeId: root.localeId
                    busy: root.busy
                    localeOptions: root.localeOptions

                    onLocaleSelected: function(locale) {
                        root._selectLocale(locale)
                    }
                }

                RecoveryPage {
                    id: recoveryPage
                    visible: root.currentCategory === "recovery"
                    localeId: root.localeId
                    busy: root.busy
                    recoveryAvailable: root.recoveryAvailable
                    recoverySourceName: root.recoverySourceName
                    recoveryCapturedAt: root.recoveryCapturedAt
                    recoveryImageSize: root.recoveryImageSize

                    onRecoveryEnabledToggled: function(checked) {
                        root._commit("recoveryEnabled", checked)
                    }
                    onConfirmOnCloseToggled: function(checked) {
                        root._commit("confirmOnClose", checked)
                    }
                    onRecoveryDiscardRequested: root.recoveryDiscardRequested()
                    onResetRequested: root.resetToDefaults()
                }

                AboutPage {
                    id: aboutPage
                    visible: root.currentCategory === "about"
                    localeId: root.localeId
                    busy: root.busy
                    formatCapabilities: root.formatCapabilities

                    onShortcutsRequested: root.shortcutsRequested()
                }
            }
        }
    }
}
