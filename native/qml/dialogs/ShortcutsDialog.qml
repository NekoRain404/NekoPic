import QtQuick
import QtQuick.Layouts
import "../UI"

/*!
    ShortcutsDialog — read-only reference for the shortcuts that exist today.

    The list mirrors Main.qml exactly; it deliberately does not advertise
    future or proposed shortcuts. StandardKey combinations are shown as their
    Linux/desktop values (Ctrl+O, Ctrl+S, Ctrl+Shift+S, Ctrl+Z, Ctrl+Shift+Z),
    which is the platform this build targets.
*/
NekoDialog {
    id: root

    readonly property var groups: [
        {
            title: qsTr("File"),
            entries: [
                { action: qsTr("Open image…"), shortcut: "Ctrl+O" },
                { action: qsTr("Save"), shortcut: "Ctrl+S" },
                { action: qsTr("Save as…"), shortcut: "Ctrl+Shift+S" }
            ]
        },
        {
            title: qsTr("Edit"),
            entries: [
                { action: qsTr("Undo"), shortcut: "Ctrl+Z" },
                { action: qsTr("Redo"), shortcut: "Ctrl+Shift+Z" },
                { action: qsTr("Copy image"), shortcut: "Ctrl+Shift+C" }
            ]
        },
        {
            title: qsTr("View"),
            entries: [
                { action: qsTr("Zoom in"), shortcut: "Ctrl+=" },
                { action: qsTr("Zoom out"), shortcut: "Ctrl+-" },
                { action: qsTr("Fit to window"), shortcut: "Ctrl+0" },
                { action: qsTr("Actual size (100%)"), shortcut: "Ctrl+1" },
                { action: qsTr("Command palette…"), shortcut: "Ctrl+K" }
            ]
        },
        {
            title: qsTr("Tools"),
            entries: [
                { action: qsTr("Select"), shortcut: "V" },
                { action: qsTr("Brush"), shortcut: "B" },
                { action: qsTr("Shapes"), shortcut: "U" },
                { action: qsTr("Crop"), shortcut: "C" },
                { action: qsTr("Add text"), shortcut: "T" },
                { action: qsTr("Eyedropper"), shortcut: "I" },
                { action: qsTr("Apply crop"), shortcut: "Enter" },
                { action: qsTr("Cancel crop or eyedropper"), shortcut: "Esc" }
            ]
        },
        {
            title: qsTr("Help"),
            entries: [
                { action: qsTr("Keyboard shortcuts"), shortcut: "F1" }
            ]
        }
    ]

    /*! Flat view of every entry, convenient for consumers and tests. */
    readonly property var entries: {
        const flat = []
        for (let i = 0; i < groups.length; ++i) {
            const group = groups[i]
            for (let j = 0; j < group.entries.length; ++j)
                flat.push(group.entries[j])
        }
        return flat
    }

    title: qsTr("Keyboard shortcuts")
    description: qsTr("Shortcuts available in the editor. Crop shortcuts work while the crop tool is active.")

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingLg

        Repeater {
            model: root.groups

            delegate: ColumnLayout {
                id: groupColumn
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                NekoSectionHeader {
                    Layout.fillWidth: true
                    text: groupColumn.modelData.title
                    eyebrow: true
                    showDivider: true
                }

                Repeater {
                    model: groupColumn.modelData.entries

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingXs
                        spacing: Theme.spacingSm

                        Text {
                            Layout.fillWidth: true
                            text: modelData.action
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            implicitWidth: shortcutLabel.implicitWidth + Theme.spacingMd * 2
                            implicitHeight: Theme.iconSizeLg
                            radius: Theme.radiusXs
                            color: Theme.background
                            border.width: Theme.borderWidth
                            border.color: Theme.border

                            Text {
                                id: shortcutLabel
                                anchors.centerIn: parent
                                text: modelData.shortcut
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.fontWeightMedium
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            NekoButton {
                objectName: "shortcuts-close"
                text: qsTr("Done")
                variant: "primary"
                onClicked: root.close()
            }
        }
    }
}
