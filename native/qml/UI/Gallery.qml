pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

/*!
    Gallery — manual visual review page for the UI design system.

    Not a test. Load it with e.g.
        QT_QPA_PLATFORM=offscreen qml native/qml/UI/Gallery.qml
    or point qmlscene at it. Toggle the theme and reduced-motion switches in
    the header to inspect every state.
*/
Item {
    id: gallery

    implicitWidth: 1120
    implicitHeight: 920

    property string activeTool: "adjust"
    property int segmentIndex: 0
    property int selectedCard: 0

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: content.implicitHeight + Theme.spacing4xl * 2

        ColumnLayout {
            id: content
            x: Theme.spacing4xl
            y: Theme.spacing3xl
            width: gallery.width - Theme.spacing4xl * 2
            spacing: Theme.spacing3xl

            // ── Brand + mode switches ──────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Rectangle {
                    Layout.preferredWidth: Theme.controlHeightLg
                    Layout.preferredHeight: Theme.controlHeightLg
                    radius: Theme.radiusMd
                    color: Theme.accent

                    NekoIcon {
                        anchors.centerIn: parent
                        width: Theme.iconSizeLg
                        height: Theme.iconSizeLg
                        name: "logo"
                        color: Theme.accentInk
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "NekoPic"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontHeadline
                        font.weight: Theme.fontWeightDemiBold
                        font.letterSpacing: Theme.trackingTight
                    }
                    Text {
                        text: qsTr("Design system · UI module preview")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontCaption
                    }
                }

                Item { Layout.fillWidth: true }

                NekoToggle {
                    text: qsTr("Dark")
                    checked: Theme.dark
                    onToggled: Theme.dark = checked
                }
                NekoToggle {
                    text: qsTr("Reduce motion")
                    checked: Theme.reduceMotion
                    onToggled: Theme.reduceMotion = checked
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.borderWidth
                color: Theme.separator
            }

            // ── Buttons ────────────────────────────────────────────────────
            NekoSectionHeader {
                Layout.fillWidth: true
                text: qsTr("Actions")
                meta: qsTr("primary · secondary · ghost")
                showDivider: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                NekoButton { text: qsTr("Open image"); iconName: "folder" }
                NekoButton { text: qsTr("Save"); iconName: "save"; variant: "primary" }
                NekoButton { text: qsTr("Reset"); iconName: "reset"; variant: "ghost" }
                NekoButton { text: qsTr("Disabled"); enabled: false }
                Item { Layout.fillWidth: true }
                NekoButton { text: qsTr("With icon"); iconName: "check" }
            }

            // ── Icon buttons ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                NekoIconButton { iconName: "undo"; accessibleName: qsTr("Undo") }
                NekoIconButton { iconName: "redo"; accessibleName: qsTr("Redo") }
                NekoIconButton { iconName: "plus"; accessibleName: qsTr("Add") }
                NekoIconButton { iconName: "minus"; accessibleName: qsTr("Remove") }
                NekoIconButton { iconName: "reset"; accessibleName: qsTr("Reset") }
                NekoIconButton { iconName: "eye"; accessibleName: qsTr("Show") }
                NekoIconButton { iconName: "close"; accessibleName: qsTr("Close") }
                NekoIconButton { iconName: "eye"; checkable: true; checked: true; accessibleName: qsTr("Visible") }

                Item { Layout.fillWidth: true }

                NekoButton {
                    text: qsTr("Open dialog")
                    variant: "secondary"
                    iconName: "chevronRight"
                    onClicked: dialog.open()
                }
            }

            // ── Tool rail ──────────────────────────────────────────────────
            NekoSectionHeader {
                Layout.fillWidth: true
                text: qsTr("Tool rail")
                meta: qsTr("checked indicator")
                showDivider: true
            }

            NekoPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.toolButtonHeight + Theme.spacingLg * 2
                elevation: NekoPanel.Flat
                backgroundColor: Theme.panel

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXs

                    Repeater {
                        model: [
                            { icon: "select", label: qsTr("Select") },
                            { icon: "pan", label: qsTr("Pan") },
                            { icon: "adjust", label: qsTr("Adjust") },
                            { icon: "filters", label: qsTr("Filters") },
                            { icon: "mosaic", label: qsTr("Mosaic") },
                            { icon: "crop", label: qsTr("Crop") }
                        ]

                        delegate: NekoToolButton {
                            required property var modelData
                            iconName: modelData.icon
                            text: modelData.label
                            checked: gallery.activeTool === modelData.icon
                            onClicked: gallery.activeTool = modelData.icon
                        }
                    }
                }
            }

            // ── Segmented + toggles ────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing3xl

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    NekoSectionHeader {
                        Layout.fillWidth: true
                        text: qsTr("Segmented control")
                        meta: qsTr("animated pill")
                        showDivider: true
                    }

                    NekoSegmentedControl {
                        Layout.fillWidth: true
                        model: [qsTr("Adjust"), qsTr("Filters"), qsTr("Color")]
                        currentIndex: gallery.segmentIndex
                        accessibleName: qsTr("Inspector sections")
                        onActivated: function(index) { gallery.segmentIndex = index }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    NekoSectionHeader {
                        Layout.fillWidth: true
                        text: qsTr("Toggles")
                        meta: qsTr("switch")
                        showDivider: true
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        NekoToggle { text: qsTr("Local editing"); checked: true }
                        NekoToggle { text: qsTr("Show grid") }
                        NekoToggle { text: qsTr("Disabled"); enabled: false }
                    }
                }
            }

            // ── Sliders ────────────────────────────────────────────────────
            NekoSectionHeader {
                Layout.fillWidth: true
                text: qsTr("Sliders")
                meta: qsTr("drag · keyboard · double-click to reset")
                showDivider: true
            }

            NekoPanel {
                id: sliderPanel
                Layout.fillWidth: true
                Layout.preferredHeight: sliderContent.implicitHeight + Theme.spacingLg * 4
                elevation: NekoPanel.Flat

                ColumnLayout {
                    id: sliderContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingXl

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        Text {
                            text: qsTr("Exposure")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSmall
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: exposure.valueText
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    NekoSlider {
                        id: exposure
                        Layout.fillWidth: true
                        from: -100
                        to: 100
                        value: 22
                        stepSize: 1
                        defaultValue: 0
                        suffix: ""
                        accessibleName: qsTr("Exposure")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        Text {
                            text: qsTr("Strength")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSmall
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: strength.valueText
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    NekoSlider {
                        id: strength
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: 64
                        stepSize: 5
                        defaultValue: 0
                        decimals: 0
                        suffix: "%"
                        accessibleName: qsTr("Filter strength")
                    }
                }
            }

            // ── Cards ──────────────────────────────────────────────────────
            NekoSectionHeader {
                Layout.fillWidth: true
                text: qsTr("Cards")
                meta: qsTr("hover · press · keyboard")
                showDivider: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Repeater {
                    model: [
                        { title: qsTr("Vivid"), detail: qsTr("Punchy colour"), icon: "filters" },
                        { title: qsTr("Warm"), detail: qsTr("Golden light"), icon: "adjust" },
                        { title: qsTr("Mono"), detail: qsTr("Quiet contrast"), icon: "mosaic" }
                    ]

                    delegate: NekoCard {
                        id: cardDelegate
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.panelMinHeight + Theme.spacing2xl
                        accessibleName: cardDelegate.modelData.title
                        elevation: gallery.selectedCard === cardDelegate.index ? NekoPanel.Low : NekoPanel.Flat
                        onClicked: gallery.selectedCard = cardDelegate.index

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.spacingXs

                            NekoIcon {
                                Layout.preferredWidth: Theme.iconSizeLg
                                Layout.preferredHeight: Theme.iconSizeLg
                                name: cardDelegate.modelData.icon
                                color: gallery.selectedCard === cardDelegate.index ? Theme.accent : Theme.textSecondary
                            }
                            Text {
                                text: cardDelegate.modelData.title
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontWeightMedium
                            }
                            Text {
                                text: cardDelegate.modelData.detail
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontCaption
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            // ── Scrollbar ──────────────────────────────────────────────────
            NekoSectionHeader {
                Layout.fillWidth: true
                text: qsTr("Scroll bar")
                meta: qsTr("quiet until active")
                showDivider: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.scrollBarThickness * 16
                radius: Theme.radiusMd
                color: Theme.surface
                border.width: Theme.borderWidth
                border.color: Theme.border

                Flickable {
                    id: scrollDemo
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    clip: true
                    contentHeight: Theme.scrollBarThickness * 26
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        spacing: Theme.spacingSm
                        Repeater {
                            model: 12
                            delegate: Text {
                                required property int index
                                text: qsTr("Recent document ") + (index + 1)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSmall
                            }
                        }
                    }

                    ScrollBar.vertical: NekoScrollBar {
                        policy: ScrollBar.AlwaysOn
                        accessibleName: qsTr("Document list scroll")
                    }
                }
            }

            // ── Footer ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Rectangle {
                    Layout.preferredWidth: Theme.spacingXs
                    Layout.preferredHeight: Theme.spacingXs
                    radius: width / 2
                    color: Theme.success
                }
                Text {
                    text: qsTr("Local editing · all tokens from Theme / Motion")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: qsTr("v0.1 design system")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                }
            }
        }
    }

    NekoDialog {
        id: dialog
        title: qsTr("Export image")
        description: qsTr("A consistent modal surface with a body and a two-button footer.")
        acceptText: qsTr("Export")
        rejectText: qsTr("Cancel")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            NekoSegmentedControl {
                Layout.fillWidth: true
                model: ["PNG", "JPEG"]
                currentIndex: 0
            }

            NekoToggle {
                text: qsTr("Embed colour profile")
                checked: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: qsTr("Quality")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSmall
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: quality.valueText
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                }
            }
            NekoSlider {
                id: quality
                Layout.fillWidth: true
                from: 0
                to: 100
                value: 90
                suffix: "%"
                accessibleName: qsTr("Export quality")
            }
        }
    }
}
