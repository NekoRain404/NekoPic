import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    LanguagePage — interface-language selection.

    The page receives the available locales and the active id, and reports a
    selection through localeSelected().
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-language"

    property string localeId: "zh_CN"
    property bool busy: false
    property var localeOptions: []

    signal localeSelected(string id)

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

    NekoSectionHeader {
        objectName: "settings-section-language"
        Layout.fillWidth: true
        text: page._tr("语言", "Language")
        eyebrow: true
        showDivider: true
    }

    Text {
        Layout.fillWidth: true
        text: page._tr("界面语言会立即切换。",
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
            model: page.localeOptions

            delegate: NekoButton {
                required property var modelData
                objectName: "settings-locale-" + modelData.id
                text: modelData.nativeName
                variant: page.localeId === modelData.id ? "primary" : "secondary"
                enabled: !page.busy
                Accessible.checkable: true
                Accessible.checked: page.localeId === modelData.id
                onClicked: page.localeSelected(modelData.id)
            }
        }

        Item { Layout.fillWidth: true }
    }
}
