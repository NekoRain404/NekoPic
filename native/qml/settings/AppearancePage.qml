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

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

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
        text: page._tr("外观", "Appearance")
        eyebrow: true
        showDivider: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Text {
            Layout.fillWidth: true
            text: page._tr("主题", "Theme")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontWeightMedium
        }
        Text {
            Layout.fillWidth: true
            text: page._tr("跟随系统，或选择浅色、深色与四套精选调色板。",
                           "Follow the system, or pick light, dark and four curated palettes.")
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
            accessibleName: page._tr("主题", "Theme")
            model: [
                page._tr("系统", "System"),
                page._tr("浅色", "Light"),
                page._tr("深色", "Dark"),
                page._tr("午夜", "Midnight"),
                page._tr("暖纸", "Warm paper"),
                page._tr("石墨", "Graphite"),
                page._tr("高对比", "Contrast")
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
        label: page._tr("减少动效", "Reduce motion")
        hint: page._tr("关闭界面动画和过渡效果。",
                       "Turn off interface animations and transitions.")

        NekoToggle {
            id: reduceMotionToggle
            objectName: "settings-reduce-motion"
            checked: false
            enabled: !page.busy
            accessibleName: page._tr("减少动效", "Reduce motion")
            onClicked: page.reduceMotionToggled(checked)
        }
    }
}
