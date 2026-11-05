import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    CommandPalette — Ctrl+K search over the application's commands.

    Commands are plain objects: { title, detail, shortcut, enabled, run }.
    The palette filters on title/detail/shortcut, supports arrow navigation,
    Enter to run and Escape to close. It never mutates the command list.
*/
Item {
    id: root

    property var commands: []
    property string query: ""
    property int currentIndex: 0
    property bool opened: false

    readonly property var filtered: {
        const needle = query.trim().toLowerCase()
        const result = []
        for (let i = 0; i < commands.length; ++i) {
            const command = commands[i]
            if (command.enabled === false) continue
            const haystack = ((command.title || "") + " " + (command.detail || "")
                              + " " + (command.shortcut || "")).toLowerCase()
            if (needle.length === 0 || haystack.indexOf(needle) >= 0) result.push(command)
        }
        return result
    }
    readonly property int resultCount: filtered.length

    signal commandTriggered(string title)

    function open() {
        query = ""
        currentIndex = 0
        opened = true
        searchField.forceActiveFocus()
    }
    function close() {
        opened = false
    }
    function activate(index) {
        if (index < 0 || index >= filtered.length) return
        const command = filtered[index]
        close()
        commandTriggered(command.title)
        if (typeof command.run === "function") command.run()
    }
    function moveSelection(delta) {
        if (filtered.length === 0) return
        currentIndex = Math.max(0, Math.min(filtered.length - 1, currentIndex + delta))
    }

    visible: opened
    z: 3000
    anchors.fill: parent
    focus: opened
    Accessible.role: Accessible.Dialog
    Accessible.name: qsTr("Command palette")

    onFilteredChanged: currentIndex = 0

    // Scrim: click outside the panel closes the palette.
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.duration(Motion.fast) } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        id: panel
        width: Math.min(Theme.dialogWidth, parent.width - Theme.spacing3xl * 2)
        height: Math.min(column.implicitHeight + Theme.spacing2xl * 2, parent.height - Theme.spacing3xl * 2)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(Theme.spacing3xl, parent.height * 0.16)
        radius: Theme.radiusLg
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.border
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.98
        Behavior on opacity { NumberAnimation { duration: Motion.duration(Motion.standard) } }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.duration(Motion.standard)
                easing.type: Motion.emphasizedEasing
            }
        }

        // A single layered shadow keeps the panel readable on both themes.
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 10
            radius: parent.radius
            color: Theme.shadowColor
            opacity: 0.28
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Label {
                    text: qsTr("Search commands")
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontWeightDemiBold
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: "Esc"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontCaption
                }
            }

            TextField {
                id: searchField
                objectName: "commandSearch"
                Layout.fillWidth: true
                implicitHeight: Theme.controlHeight + 6
                placeholderText: qsTr("Type a command or shortcut…")
                placeholderTextColor: Theme.textTertiary
                color: Theme.textPrimary
                selectionColor: Theme.accentSoft
                selectedTextColor: Theme.textPrimary
                font.pixelSize: Theme.fontBody
                leftPadding: Theme.spacingMd
                rightPadding: Theme.spacingMd
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.surfaceRaised
                    border.width: searchField.activeFocus ? 2 : Theme.borderWidth
                    border.color: searchField.activeFocus ? Theme.focusRing : Theme.border
                }
                onTextChanged: root.query = text
                onAccepted: root.activate(root.currentIndex)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Down) { root.moveSelection(1); event.accepted = true }
                    else if (event.key === Qt.Key_Up) { root.moveSelection(-1); event.accepted = true }
                    else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
                }
            }

            Label {
                visible: root.resultCount === 0
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingLg
                Layout.bottomMargin: Theme.spacingLg
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No matching commands")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontBody
            }

            ListView {
                id: list
                objectName: "commandList"
                visible: root.resultCount > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320)
                clip: true
                interactive: false
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    objectName: "command-" + index
                    width: list.width
                    height: 42
                    radius: Theme.radiusSm
                    color: index === root.currentIndex ? Theme.selection
                         : rowHover.containsMouse ? Theme.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.duration(Motion.fast) } }

                    Rectangle {
                        visible: row.index === root.currentIndex
                        x: 0; y: 10; width: 2; height: 22; radius: 1
                        color: Theme.accent
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        spacing: Theme.spacingSm
                        Label {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            elide: Text.ElideRight
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontBody
                        }
                        Label {
                            visible: row.modelData.detail !== undefined && row.modelData.detail.length > 0
                            text: row.modelData.detail || ""
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontCaption
                        }
                        Label {
                            visible: row.modelData.shortcut !== undefined && row.modelData.shortcut.length > 0
                            text: row.modelData.shortcut || ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.activate(row.index)
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("↑↓ move · Enter run · Esc close")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }
    }
}
