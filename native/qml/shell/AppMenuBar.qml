import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    AppMenuBar — the application menu bar.

    The shell supplies its Action objects and menu state; the component never
    reaches into window ids. Static labels use the original "Main" translation
    context so moving the menus does not require catalogue changes.
*/
MenuBar {
    id: bar

    property var actions: ({})
    property bool followSystemTheme: false
    property bool darkTheme: true
    property bool reduceMotion: false
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

    background: Rectangle { color: Theme.background }

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

    Menu {
        title: qsTranslate("Main", "File")
        MenuItem { action: bar.actions.open }
        Menu {
            objectName: "recentMenu"
            title: qsTranslate("Main", "Open recent")
            enabled: bar.recentEntries.length > 0 && !bar.busy
            Repeater {
                model: bar.recentEntries
                MenuItem {
                    required property var modelData
                    text: modelData.name
                    enabled: !bar.busy
                    onTriggered: bar.recentRequested(modelData.url)
                }
            }
            MenuSeparator {}
            MenuItem {
                text: qsTranslate("Main", "Clear recent files")
                enabled: bar.recentEntries.length > 0 && !bar.busy
                onTriggered: bar.clearRecentRequested()
            }
        }
        MenuSeparator {}
        MenuItem { action: bar.actions.save }
        MenuItem { action: bar.actions.saveAs }
    }

    Menu {
        title: qsTranslate("Main", "Edit")
        MenuItem { action: bar.actions.undo }
        MenuItem { action: bar.actions.redo }
        MenuSeparator {}
        MenuItem { action: bar.actions.copy }
    }

    Menu {
        title: qsTranslate("Main", "Image")
        MenuItem { action: bar.actions.rotateLeft }
        MenuItem { action: bar.actions.rotateRight }
        MenuItem { action: bar.actions.flipHorizontal }
        MenuItem { action: bar.actions.flipVertical }
        MenuSeparator {}
        MenuItem { action: bar.actions.select }
        MenuItem { action: bar.actions.brush }
        MenuItem { action: bar.actions.shape }
        MenuItem { action: bar.actions.crop }
        MenuItem { action: bar.actions.text }
        MenuItem { action: bar.actions.eyedropper }
        MenuSeparator {}
        MenuItem { action: bar.actions.resizeImage }
        MenuItem { action: bar.actions.canvasSize }
    }

    Menu {
        title: qsTranslate("Main", "View")
        MenuItem { action: bar.actions.zoomIn }
        MenuItem { action: bar.actions.zoomOut }
        MenuItem { action: bar.actions.fit }
        MenuItem { action: bar.actions.actual }
        MenuSeparator {}
        MenuItem { action: bar.actions.commandPalette }
        MenuSeparator {}
        MenuItem {
            text: qsTranslate("Main", "Follow system theme")
            checkable: true
            checked: bar.followSystemTheme
            onTriggered: bar.followSystemThemeToggled(checked)
        }
        MenuItem {
            text: qsTranslate("Main", "Dark theme")
            checkable: true
            checked: bar.darkTheme
            enabled: !bar.followSystemTheme
            onTriggered: bar.darkThemeToggled(checked)
        }
        MenuItem {
            text: qsTranslate("Main", "Reduce motion")
            checkable: true
            checked: bar.reduceMotion
            onTriggered: bar.reduceMotionToggled(checked)
        }
        Menu {
            title: qsTranslate("Main", "Language")
            Repeater {
                model: bar.availableLocales
                MenuItem {
                    required property var modelData
                    text: modelData.nativeName
                    checkable: true
                    checked: bar.localeId === modelData.id
                    onTriggered: bar.localeSelected(modelData.id)
                }
            }
        }
        MenuSeparator {}
        MenuItem { action: bar.actions.settings }
    }
}
