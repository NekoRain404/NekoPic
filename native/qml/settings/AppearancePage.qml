import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AppearancePage — theme and motion preferences.

    The page is presentation only: it receives the current values and reports
    user intent through signals. Validation and persistence stay in
    SettingsDialog.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-appearance"

    property string localeId: "zh_CN"
    property bool busy: false
    property string themeMode: "dark"
    property alias reduceMotion: reduceMotionToggle.checked

    signal themeSelected(string mode)
    signal reduceMotionToggled(bool checked)

    readonly property var themeModes: ["system", "light", "dark", "midnight", "warm", "graphite", "contrast"]

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _themeIndex(mode) {
        for (let i = 0; i < page.themeModes.length; ++i) {
            if (page.themeModes[i] === mode)
                return i
        }
        return -1
    }

    onThemeModeChanged: {
        const index = page._themeIndex(page.themeMode)
        if (index >= 0)
            themeControl.currentIndex = index
    }

    Component.onCompleted: {
        themeControl.currentIndex = Math.max(0, page._themeIndex(page.themeMode))
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

        NekoSegmentedControl {
            id: themeControl
            objectName: "settings-theme"
            Layout.fillWidth: true
            enabled: !page.busy
            accessibleName: qsTr("Theme")
            model: [
                qsTr("System"),
                qsTr("Light"),
                qsTr("Dark"),
                qsTr("Midnight"),
                qsTr("Warm paper"),
                qsTr("Graphite"),
                qsTr("Contrast")
            ]

            onActivated: function(index) {
                if (page.busy)
                    return
                const mode = page.themeModes[index]
                if (mode === undefined || page.themeMode === mode)
                    return
                page.themeSelected(mode)
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
}
