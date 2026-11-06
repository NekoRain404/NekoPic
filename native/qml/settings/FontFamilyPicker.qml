import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    FontFamilyPicker — compact system-font chooser for the settings page.

    The first entry is always "System default" and maps to an empty family.
    Families come from Qt.fontFamilies(); the popup offers a small search field
    instead of a platform ComboBox so the control keeps the Neko visual
    language and stays testable offscreen.
*/
Item {
    id: root
    objectName: "settings-font-family-picker"

    /*! Empty selects the system UI font. */
    property string family: ""
    property bool busy: false

    signal familySelected(string family)

    property string searchText: ""

    readonly property string systemLabel: qsTr("System default")
    readonly property var options: {
        const query = root.searchText.trim().toLowerCase()
        const result = [{ family: "", label: root.systemLabel }]
        const families = Qt.fontFamilies()
        for (let i = 0; i < families.length; ++i) {
            const name = String(families[i])
            if (query.length > 0 && name.toLowerCase().indexOf(query) < 0)
                continue
            result.push({ family: name, label: name })
        }
        return result
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    NekoButton {
        id: button
        objectName: "settings-font-family"
        anchors.fill: parent
        text: root.family.length > 0 ? root.family : root.systemLabel
        variant: "secondary"
        iconName: "text"
        enabled: !root.busy
        accessibleName: qsTr("UI font family")
        onClicked: {
            root.searchText = ""
            popup.open()
        }
    }

    Popup {
        id: popup
        objectName: "settings-font-family-popup"
        anchors.centerIn: Overlay.overlay
        width: 300
        height: 360
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: Theme.spacingMd

        background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.surfaceRaised
            border.width: Theme.borderWidth
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingSm

            TextField {
                id: searchField
                objectName: "settings-font-family-search"
                Layout.fillWidth: true
                placeholderText: qsTr("Search fonts…")
                color: Theme.textPrimary
                placeholderTextColor: Theme.textTertiary
                font.pixelSize: Theme.fontSmall
                selectByMouse: true
                onTextChanged: root.searchText = text
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.background
                    border.width: Theme.borderWidth
                    border.color: searchField.activeFocus ? Theme.focusRing : Theme.border
                }
            }

            ListView {
                id: familyList
                objectName: "settings-font-family-list"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.options
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: NekoScrollBar { policy: ScrollBar.AlwaysOff }

                delegate: AbstractButton {
                    id: option
                    required property var modelData
                    required property int index

                    objectName: "settings-font-family-option"
                    width: familyList.width
                    height: Theme.controlHeight
                    padding: 0
                    hoverEnabled: true
                    text: modelData.label

                    readonly property bool current: modelData.family === root.family

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: option.text
                    Accessible.checkable: true
                    Accessible.checked: option.current

                    background: Rectangle {
                        radius: Theme.radiusXs
                        color: option.current ? Theme.selection
                             : option.hovered ? Theme.hover
                             : "transparent"
                    }

                    contentItem: Text {
                        leftPadding: Theme.spacingMd
                        rightPadding: Theme.spacingMd
                        text: option.text
                        color: option.current ? Theme.textPrimary : Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                        font.weight: option.current ? Theme.fontWeightMedium
                                                    : Theme.fontWeightRegular
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    onClicked: {
                        const chosen = modelData.family
                        popup.close()
                        if (chosen === root.family)
                            return
                        root.family = chosen
                        root.familySelected(chosen)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Fonts are listed from the operating system.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }

        onOpened: {
            searchField.text = ""
            searchField.forceActiveFocus()
        }
    }
}
