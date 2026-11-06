import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AppearancePage — theme, motion, typography and interface-scale preferences.

    The page is presentation only: it receives the current values and reports
    user intent through signals. Validation and persistence stay in
    SettingsDialog. UI text size is applied live through Theme.fontScale;
    whole-interface scale is stored for the next launch.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-appearance"

    property string localeId: "zh_CN"
    property bool busy: false
    property string themeMode: "dark"
    property alias reduceMotion: reduceMotionToggle.checked
    property string uiFontFamily: ""
    property int uiFontScale: 100
    property int uiScale: 100
    /*! Scale that was active when the dialog opened; drives the restart note. */
    property int appliedUiScale: 100

    readonly property bool restartRequired: uiScale !== appliedUiScale

    signal themeSelected(string mode)
    signal reduceMotionToggled(bool checked)
    signal uiFontFamilySelected(string family)
    signal uiFontScaleSelected(int percent)
    signal uiScaleSelected(int percent)

    readonly property var themeModes: ["system", "light", "dark", "midnight", "warm", "graphite", "contrast", "nordic", "sakura", "forest", "solarized"]
    readonly property var themeLabels: [
        qsTr("System"), qsTr("Light"), qsTr("Dark"), qsTr("Midnight"),
        qsTr("Warm paper"), qsTr("Graphite"), qsTr("Contrast"),
        qsTr("Nordic"), qsTr("Sakura"), qsTr("Forest"), qsTr("Solarized")
    ]

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _themeIndex(mode) {
        for (let i = 0; i < page.themeModes.length; ++i) {
            if (page.themeModes[i] === mode)
                return i
        }
        return -1
    }

    function syncFontScale() {
        if (fontScaleSlider && !fontScaleSlider.dragging)
            fontScaleSlider.value = page.uiFontScale
    }

    function syncUiScale() {
        if (uiScaleSlider && !uiScaleSlider.dragging)
            uiScaleSlider.value = page.uiScale
    }

    onUiFontScaleChanged: page.syncFontScale()
    onUiScaleChanged: page.syncUiScale()

    Component.onCompleted: {
        page.syncFontScale()
        page.syncUiScale()
    }

    NekoSectionHeader {
        objectName: "settings-section-appearance"
        Layout.fillWidth: true
        text: qsTr("Appearance")
        eyebrow: true
        showDivider: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Text {
            Layout.fillWidth: true
            text: qsTr("Theme")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontWeightMedium
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("Follow the system, or pick light, dark and four curated palettes.")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontCaption
            lineHeight: Theme.lineHeightNormal
            wrapMode: Text.WordWrap
        }

        Flow {
            id: themeControl
            objectName: "settings-theme"
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            enabled: !page.busy

            readonly property int count: page.themeModes.length
            readonly property int currentIndex: Math.max(0, page._themeIndex(page.themeMode))

            function activate(index) {
                if (index < 0 || index >= page.themeModes.length)
                    return
                const mode = page.themeModes[index]
                if (page.busy || page.themeMode === mode)
                    return
                page.themeSelected(mode)
            }

            Repeater {
                model: page.themeModes.length

                delegate: NekoButton {
                    required property int index

                    objectName: "settings-theme-" + page.themeModes[index]
                    text: page.themeLabels[index]
                    variant: page.themeMode === page.themeModes[index]
                             ? "primary" : "secondary"
                    enabled: !page.busy
                    Accessible.checkable: true
                    Accessible.checked: page.themeMode === page.themeModes[index]
                    onClicked: themeControl.activate(index)
                }
            }
        }
    }

    SettingRow {
        label: qsTr("Reduce motion")
        hint: qsTr("Turn off interface animations and transitions.")

        NekoToggle {
            id: reduceMotionToggle
            objectName: "settings-reduce-motion"
            checked: false
            enabled: !page.busy
            accessibleName: qsTr("Reduce motion")
            onClicked: page.reduceMotionToggled(checked)
        }
    }

    NekoSectionHeader {
        objectName: "settings-section-typography"
        Layout.fillWidth: true
        text: qsTr("Typography & interface")
        eyebrow: true
        showDivider: true
    }

    SettingRow {
        label: qsTr("UI font family")
        hint: qsTr("Use an installed family for interface text; System default follows the desktop.")

        FontFamilyPicker {
            id: fontPicker
            family: page.uiFontFamily
            busy: page.busy
            onFamilySelected: function(family) { page.uiFontFamilySelected(family) }
        }
    }

    SettingRow {
        label: qsTr("UI text size")
        hint: qsTr("Scales labels, controls and dialogue text without changing the window layout.")

        RowLayout {
            spacing: Theme.spacingSm

            NekoSlider {
                id: fontScaleSlider
                objectName: "settings-font-scale"
                Layout.preferredWidth: 150
                from: 80
                to: 140
                stepSize: 5
                defaultValue: 100
                value: page.uiFontScale
                suffix: "%"
                enabled: !page.busy
                accessibleName: qsTr("UI text size")
                onPreview: function(value) { page.uiFontScaleSelected(Math.round(value)) }
                onFinish: function(value) { page.uiFontScaleSelected(Math.round(value)) }
            }

            Text {
                objectName: "settings-font-scale-value"
                text: Math.round(fontScaleSlider.value) + "%"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightMedium
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    SettingRow {
        label: qsTr("Interface scale")
        hint: qsTr("Scales the whole window on the next launch; requires restarting NekoPic.")

        RowLayout {
            spacing: Theme.spacingSm

            NekoSlider {
                id: uiScaleSlider
                objectName: "settings-ui-scale"
                Layout.preferredWidth: 150
                from: 80
                to: 150
                stepSize: 5
                defaultValue: 100
                value: page.uiScale
                suffix: "%"
                enabled: !page.busy
                accessibleName: qsTr("Interface scale")
                onPreview: function(value) { page.uiScaleSelected(Math.round(value)) }
                onFinish: function(value) { page.uiScaleSelected(Math.round(value)) }
            }

            Text {
                objectName: "settings-ui-scale-value"
                text: Math.round(uiScaleSlider.value) + "%"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSmall
                font.weight: Theme.fontWeightMedium
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Text {
        objectName: "settings-ui-scale-note"
        Layout.fillWidth: true
        visible: page.restartRequired
        text: qsTr("Restart NekoPic to apply the interface scale.")
        color: Theme.warning
        font.pixelSize: Theme.fontCaption
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }
}
