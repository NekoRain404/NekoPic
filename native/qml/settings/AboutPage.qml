import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AboutPage — build information, format capabilities and the shortcut entry.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-about"

    property string localeId: "zh_CN"
    property bool busy: false
    property var formatCapabilities: ({ readableCount: 0, writableCount: 0 })

    signal shortcutsRequested()

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

    NekoSectionHeader {
        objectName: "settings-section-about"
        Layout.fillWidth: true
        text: page._tr("关于", "About")
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
            text: page._tr("本地优先的桌面照片编辑器。",
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
                    const readable = page.formatCapabilities
                                     && page.formatCapabilities.readableCount !== undefined
                                     ? page.formatCapabilities.readableCount : 0
                    const writable = page.formatCapabilities
                                     && page.formatCapabilities.writableCount !== undefined
                                     ? page.formatCapabilities.writableCount : 0
                    if (readable <= 0 && writable <= 0)
                        return page._tr("格式能力将在应用启动后显示。",
                                        "Format capabilities are shown when the app is running.")
                    return page._tr("可读取 " + readable + " 种格式 · 可写入 "
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
                text: page._tr("导出格式取决于当前构建启用的编解码器。",
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
            text: page._tr("键盘快捷键", "Keyboard shortcuts")
            variant: "secondary"
            iconName: "select"
            enabled: !page.busy
            onClicked: page.shortcutsRequested()
        }

        Item { Layout.fillWidth: true }
    }

    Text {
        Layout.fillWidth: true
        text: page._tr("所有照片都保留在本设备上。",
                       "All photos stay on this device.")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        lineHeight: Theme.lineHeightNormal
        wrapMode: Text.WordWrap
    }
}
