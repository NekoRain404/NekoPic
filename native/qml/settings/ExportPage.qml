import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"
import "../dialogs"

/*!
    ExportPage — export quality and JPEG background preferences.

    The page is presentation only. Slider and swatch gestures are reported as
    settings requests; SettingsDialog clamps values, updates the public
    properties and persists them.
*/
ColumnLayout {
    id: page
    objectName: "settings-panel-export"

    property string localeId: "zh_CN"
    property bool busy: false
    property int exportQuality: -1
    property int defaultQuality: 90
    property color jpegBackground: "#ffffff"

    readonly property color whiteBackground: "#ffffff"
    readonly property color blackBackground: "#000000"
    readonly property color warmGreyBackground: "#8b8780"

    signal qualityRequested(real value)
    signal backgroundRequested(color value)

    Layout.fillWidth: true
    spacing: Theme.spacingLg

    function _tr(zh, en) {
        return page.localeId === "zh_CN" ? zh : en
    }

    function syncQuality() {
        if (qualitySlider && !qualitySlider.dragging)
            qualitySlider.value = page.exportQuality >= 0 ? page.exportQuality : page.defaultQuality
        if (qualityDefaultToggle)
            qualityDefaultToggle.checked = page.exportQuality < 0
    }

    onExportQualityChanged: page.syncQuality()
    Component.onCompleted: page.syncQuality()

    NekoSectionHeader {
        objectName: "settings-section-export"
        Layout.fillWidth: true
        text: page._tr("导出", "Export")
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
                text: page._tr("导出质量", "Export quality")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontWeightMedium
            }
            Text {
                Layout.fillWidth: true
                text: page._tr("仅对支持质量设置的格式有效（JPEG、WebP、AVIF 等）。",
                               "Applies to formats that support quality (JPEG, WebP, AVIF, and others).")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                lineHeight: Theme.lineHeightNormal
                wrapMode: Text.WordWrap
            }
        }

        Text {
            objectName: "settings-quality-value"
            text: page.exportQuality < 0 ? page._tr("编码器默认", "Codec default")
                                         : page.exportQuality + "%"
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
        enabled: !page.busy && !qualityDefaultToggle.checked
        accessibleName: page._tr("导出质量", "Export quality")
        onPreview: function(value) { page.qualityRequested(value) }
        onFinish: function(value) { page.qualityRequested(value) }
    }

    NekoToggle {
        id: qualityDefaultToggle
        objectName: "settings-quality-default"
        text: page._tr("使用编码器默认值", "Use codec default")
        checked: true
        enabled: !page.busy
        accessibleName: page._tr("使用编码器默认质量", "Use codec default quality")
        onClicked: {
            if (checked)
                page.qualityRequested(-1)
            else
                page.qualityRequested(page.defaultQuality)
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
                text: page._tr("JPEG 背景", "JPEG background")
                color: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontWeightMedium
            }
            Text {
                Layout.fillWidth: true
                text: page._tr("JPEG 不支持透明度，透明区域会填充此颜色。",
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
                swatchColor: page.whiteBackground
                selected: Qt.colorEqual(page.jpegBackground, page.whiteBackground)
                enabled: !page.busy
                accessibleName: page._tr("白色背景", "White background")
                onClicked: page.backgroundRequested(page.whiteBackground)
            }

            NekoSwatch {
                objectName: "settings-background-black"
                swatchColor: page.blackBackground
                selected: Qt.colorEqual(page.jpegBackground, page.blackBackground)
                enabled: !page.busy
                accessibleName: page._tr("黑色背景", "Black background")
                onClicked: page.backgroundRequested(page.blackBackground)
            }

            NekoSwatch {
                objectName: "settings-background-warm-grey"
                swatchColor: page.warmGreyBackground
                selected: Qt.colorEqual(page.jpegBackground, page.warmGreyBackground)
                enabled: !page.busy
                accessibleName: page._tr("暖灰色背景", "Warm grey background")
                onClicked: page.backgroundRequested(page.warmGreyBackground)
            }
        }
    }
}
