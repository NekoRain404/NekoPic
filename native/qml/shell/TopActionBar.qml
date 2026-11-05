import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    TopActionBar — the primary file/edit action strip below the menu bar.

    The bar is presentation only. The shell supplies an `actions` map of
    { open, undo, redo, rotate, crop, save, saveAs, canvasSize } Action
    objects, and entry points that open menus or dialogs are reported through
    signals.
*/
Rectangle {
    id: bar

    property var actions: ({})
    property bool hasImage: false
    property bool busy: false

    signal transformRequested()
    signal canvasSizeRequested()
    signal settingsRequested()
    signal commandPaletteRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: 58
    color: Theme.panel

    readonly property var openAction: actions.open
    readonly property var undoAction: actions.undo
    readonly property var redoAction: actions.redo
    readonly property var rotateAction: actions.rotate
    readonly property var cropAction: actions.crop
    readonly property var saveAction: actions.save
    readonly property var saveAsAction: actions.saveAs
    readonly property var canvasAction: actions.canvasSize

    component CommandButton: NekoButton {
        id: command
        property bool primary: false
        variant: primary ? "primary" : "secondary"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 18
        spacing: 6

        CommandButton { action: bar.openAction; iconName: "folder" }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 19
            Layout.leftMargin: 5
            Layout.rightMargin: 5
            color: Theme.border
        }
        CommandButton {
            action: bar.undoAction
            text: ""
            iconName: "undo"
            ToolTip.visible: hovered
            ToolTip.text: bar.undoAction ? bar.undoAction.text : ""
        }
        CommandButton {
            action: bar.redoAction
            text: ""
            iconName: "redo"
            ToolTip.visible: hovered
            ToolTip.text: bar.redoAction ? bar.redoAction.text : ""
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 19
            Layout.leftMargin: 5
            Layout.rightMargin: 5
            color: Theme.border
        }
        CommandButton { action: bar.rotateAction; text: qsTr("Rotate"); iconName: "rotate" }
        CommandButton { action: bar.cropAction; iconName: "crop" }
        CommandButton {
            objectName: "action-transform"
            text: qsTr("Transform")
            iconName: "rotate"
            enabled: bar.hasImage && !bar.busy
            onClicked: bar.transformRequested()
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Rotate and flip")
        }
        CommandButton {
            objectName: "action-canvas"
            text: qsTr("Canvas")
            iconName: "fit"
            enabled: bar.canvasAction ? bar.canvasAction.enabled : false
            onClicked: bar.canvasSizeRequested()
            ToolTip.visible: hovered
            ToolTip.text: bar.canvasAction ? bar.canvasAction.text : ""
        }
        Item { Layout.fillWidth: true }
        NekoButton {
            objectName: "settingsButton"
            text: qsTr("Settings")
            variant: "ghost"
            onClicked: bar.settingsRequested()
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Preferences (Ctrl+,)")
        }
        NekoButton {
            text: qsTr("Search")
            variant: "ghost"
            onClicked: bar.commandPaletteRequested()
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Command palette (Ctrl+K)")
        }
        BusyIndicator {
            running: bar.busy
            visible: running
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
        }
        CommandButton { action: bar.saveAction; iconName: "save" }
        CommandButton { action: bar.saveAsAction; primary: true }
    }
}
