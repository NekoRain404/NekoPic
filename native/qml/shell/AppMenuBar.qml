import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AppMenuBar — the application menu bar.

    The shell supplies its Action objects and menu state; the component never
    reaches into window ids. Static labels use the original "Main" translation
    context so moving the menus does not require catalogue changes.

    Every popup is a NekoMenu, so menus, submenus and their rows share the
    design system surface, spacing, shortcut labels and checkmarks.
*/
MenuBar {
    id: bar

    property var actions: ({})
    property bool followSystemTheme: false
    property bool darkTheme: true
    property bool reduceMotion: false
    property bool hasImage: true
    property var recentEntries: []
    property bool busy: false
    property var availableLocales: []
    property string localeId: ""

    signal followSystemThemeToggled(bool checked)
    signal darkThemeToggled(bool checked)
    signal reduceMotionToggled(bool checked)
    signal localeSelected(string id)
    signal recentRequested(url url)
    signal clearRecentRequested()
    /*! Tool selected from a menu without a shared Action. */
    signal toolRequested(string tool)
    /*! Auto enhance requested from the Adjust menu. */
    signal autoEnhanceRequested()
    /*! About requested from the Help menu. */
    signal aboutRequested()

    background: Rectangle { color: Theme.background }

    delegate: MenuBarItem {
        id: barItem

        implicitHeight: 30
        leftPadding: Theme.spacingSm + Theme.spacingXs
        rightPadding: Theme.spacingSm + Theme.spacingXs
        hoverEnabled: true

        Accessible.role: Accessible.MenuItem
        Accessible.name: barItem.text

        background: Rectangle {
            radius: Theme.radiusXs
            color: barItem.down ? Theme.pressed
                 : barItem.highlighted || barItem.hovered ? Theme.hover
                 : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }

        contentItem: Text {
            text: barItem.text
            color: barItem.highlighted || barItem.hovered
                   ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            font.weight: barItem.highlighted
                         ? Theme.fontWeightMedium : Theme.fontWeightRegular
            verticalAlignment: Text.AlignVCenter
        }
    }

    contentItem: RowLayout {
        spacing: 0
        RowLayout {
            Layout.leftMargin: 14
            Layout.rightMargin: 12
            spacing: 7
            Rectangle {
                width: 21
                height: 21
                radius: 5
                color: Theme.accent
                NekoIcon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    name: "logo"
                    color: Theme.accentInk
                }
            }
            Label {
                text: "NekoPic"
                color: Theme.textPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
        Repeater { model: bar.contentModel }
        Item { Layout.fillWidth: true }
        Rectangle {
            width: 5
            height: 5
            radius: 3
            color: "#99b4a3"
        }
        Label {
            Layout.leftMargin: 7
            Layout.rightMargin: 17
            text: qsTranslate("Main", "Local editing")
            color: Theme.textSecondary
            font.pixelSize: 10
        }
    }

    NekoMenu {
        objectName: "menu-file"
        title: qsTranslate("Main", "File")
        NekoMenuItem { action: bar.actions.open }
        NekoMenu {
            objectName: "recentMenu"
            title: qsTranslate("Main", "Open recent")
            enabled: bar.recentEntries.length > 0 && !bar.busy
            Repeater {
                model: bar.recentEntries
                NekoMenuItem {
                    required property var modelData
                    text: modelData.name
                    enabled: !bar.busy
                    onTriggered: bar.recentRequested(modelData.url)
                }
            }
            NekoMenuSeparator {}
            NekoMenuItem {
                text: qsTranslate("Main", "Clear recent files")
                enabled: bar.recentEntries.length > 0 && !bar.busy
                onTriggered: bar.clearRecentRequested()
            }
        }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.save }
        NekoMenuItem { action: bar.actions.saveAs }
    }

    NekoMenu {
        objectName: "menu-edit"
        title: qsTranslate("Main", "Edit")
        NekoMenuItem { action: bar.actions.undo }
        NekoMenuItem { action: bar.actions.redo }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.copy }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.settings }
    }

    NekoMenu {
        objectName: "menu-image"
        title: qsTranslate("Main", "Image")
        NekoMenuItem { action: bar.actions.rotateLeft }
        NekoMenuItem { action: bar.actions.rotateRight }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.flipHorizontal }
        NekoMenuItem { action: bar.actions.flipVertical }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.resizeImage }
        NekoMenuItem { action: bar.actions.canvasSize }
    }

    NekoMenu {
        objectName: "menu-tools"
        title: qsTranslate("Main", "Tools")
        NekoMenuItem { action: bar.actions.select }
        NekoMenuItem { action: bar.actions.pan }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.brush }
        NekoMenuItem { action: bar.actions.text }
        NekoMenuItem { action: bar.actions.shape }
        NekoMenuItem {
            objectName: "menu-mosaic"
            text: qsTranslate("Main", "Mosaic")
            enabled: bar.hasImage && !bar.busy
            onTriggered: bar.toolRequested("mosaic")
        }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.eyedropper }
        NekoMenuItem { action: bar.actions.crop }
    }

    NekoMenu {
        objectName: "menu-adjust"
        title: qsTranslate("Main", "Adjust")
        NekoMenuItem {
            objectName: "menu-adjust-colour"
            text: qsTranslate("Main", "Adjust")
            enabled: bar.hasImage && !bar.busy
            onTriggered: bar.toolRequested("adjust")
        }
        NekoMenuItem {
            objectName: "menu-adjust-filters"
            text: qsTranslate("Main", "Filters")
            enabled: bar.hasImage && !bar.busy
            onTriggered: bar.toolRequested("filters")
        }
        NekoMenuSeparator {}
        NekoMenuItem {
            objectName: "menu-adjust-auto-enhance"
            text: qsTranslate("Main", "Auto enhance")
            enabled: bar.hasImage && !bar.busy
            onTriggered: bar.autoEnhanceRequested()
        }
    }

    NekoMenu {
        objectName: "menu-view"
        title: qsTranslate("Main", "View")
        NekoMenuItem { action: bar.actions.zoomIn }
        NekoMenuItem { action: bar.actions.zoomOut }
        NekoMenuItem { action: bar.actions.fit }
        NekoMenuItem { action: bar.actions.actual }
        NekoMenuSeparator {}
        NekoMenuItem { action: bar.actions.commandPalette }
        NekoMenuSeparator {}
        NekoMenu {
            objectName: "themeMenu"
            title: qsTranslate("Main", "Theme")
            NekoMenuItem {
                objectName: "menu-theme-follow-system"
                text: qsTranslate("Main", "Follow system theme")
                checkable: true
                checked: bar.followSystemTheme
                onTriggered: bar.followSystemThemeToggled(checked)
            }
            NekoMenuItem {
                objectName: "menu-theme-dark"
                text: qsTranslate("Main", "Dark theme")
                checkable: true
                checked: bar.darkTheme
                enabled: !bar.followSystemTheme
                onTriggered: bar.darkThemeToggled(checked)
            }
            NekoMenuItem {
                objectName: "menu-theme-reduce-motion"
                text: qsTranslate("Main", "Reduce motion")
                checkable: true
                checked: bar.reduceMotion
                onTriggered: bar.reduceMotionToggled(checked)
            }
        }
        NekoMenu {
            objectName: "languageMenu"
            title: qsTranslate("Main", "Language")
            Repeater {
                model: bar.availableLocales
                NekoMenuItem {
                    required property var modelData
                    text: modelData.nativeName
                    checkable: true
                    checked: bar.localeId === modelData.id
                    onTriggered: bar.localeSelected(modelData.id)
                }
            }
        }
    }

    NekoMenu {
        objectName: "menu-help"
        title: qsTranslate("Main", "Help")
        NekoMenuItem { action: bar.actions.shortcuts }
        NekoMenuSeparator {}
        NekoMenuItem {
            objectName: "menu-about"
            text: qsTranslate("Main", "About NekoPic")
            onTriggered: bar.aboutRequested()
        }
    }
}
