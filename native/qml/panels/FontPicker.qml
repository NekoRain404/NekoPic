import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    FontPicker — compact, searchable font-family picker for the text panel.

    The closed control is a single 34 px row showing the current family with
    right-elided text, so long family names never widen the 292 px panel. The
    popup carries a search field and a keyboard-driven list; it is an overlay
    and never participates in the panel's layout.

    Usage:
        FontPicker {
            model: [{ label: "System default", value: "" }, ...]
            currentValue: ""
            onFamilyChosen: function(value) { ... }
        }

    Keyboard: Down/Up/Enter/Space opens from the button; Down/Up moves the
    highlight, Enter picks, Escape closes and returns focus to the button.
*/
Item {
    id: root

    property var model: []
    property string currentValue: ""
    property string accessibleName: qsTr("Font family")
    property string accessibleDescription: qsTr("Typeface used to render the text")

    /*! Currently filtered entries: [{ label, value }, ...]. */
    readonly property var filteredModel: {
        const query = root.searchText.trim().toLowerCase()
        const items = []
        for (let i = 0; i < root.model.length; ++i) {
            const entry = root.model[i]
            if (!entry)
                continue
            const label = String(entry.label === undefined ? "" : entry.label)
            if (query.length === 0 || label.toLowerCase().indexOf(query) >= 0)
                items.push(entry)
        }
        return items
    }

    /*! Lightweight display label, always showing the selected family. */
    readonly property string currentLabel: {
        for (let i = 0; i < model.length; ++i) {
            if (model[i] && model[i].value === currentValue)
                return String(model[i].label)
        }
        return currentValue.length > 0 ? currentValue : qsTr("System default")
    }

    readonly property bool popupVisible: popup.visible
    readonly property int rowHeight: 28
    readonly property int listMaxHeight: 220

    /*! Search text; filtering is case-insensitive substring matching. */
    property string searchText: ""
    /*! True while the popup is open and the list has focusable entries. */
    readonly property bool hasResults: filteredModel.length > 0

    property bool _returnFocus: false
    property bool _wasOpenOnPress: false

    signal familyChosen(string value)

    implicitWidth: Theme.controlMinWidth
    implicitHeight: Theme.controlHeight

    function openPicker() {
        if (!enabled || popup.visible)
            return
        popup.open()
    }

    function closePicker() {
        if (popup.visible)
            popup.close()
    }

    function togglePicker() {
        if (popup.visible)
            closePicker()
        else
            openPicker()
    }

    /*! Chooses the entry at an index in the current filtered model. */
    function chooseIndex(index) {
        if (index < 0 || index >= filteredModel.length)
            return
        const value = filteredModel[index].value
        _returnFocus = true
        closePicker()
        familyChosen(value)
    }

    function _moveHighlight(delta) {
        if (list.count === 0)
            return
        let next = list.currentIndex
        if (next < 0)
            next = delta > 0 ? 0 : list.count - 1
        else
            next += delta
        if (next < 0)
            next = list.count - 1
        if (next >= list.count)
            next = 0
        list.currentIndex = next
        list.positionViewAtIndex(next, ListView.Contain)
    }

    function _highlightSelected() {
        if (!popup.visible || list.count === 0)
            return
        for (let i = 0; i < filteredModel.length; ++i) {
            if (filteredModel[i].value === currentValue) {
                list.currentIndex = i
                list.positionViewAtIndex(i, ListView.Contain)
                return
            }
        }
        list.currentIndex = 0
    }

    onSearchTextChanged: Qt.callLater(_highlightSelected)
    onEnabledChanged: if (!enabled) closePicker()

    Control {
        id: button
        objectName: "font-picker-button"
        anchors.fill: parent
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: true
        padding: 0
        enabled: root.enabled

        Accessible.role: Accessible.ComboBox
        Accessible.name: root.accessibleName
        Accessible.description: root.accessibleDescription
        Accessible.expanded: root.popupVisible
        Accessible.onPressAction: root.togglePicker()

        Keys.onDownPressed: function(event) {
            root.openPicker()
            event.accepted = true
        }
        Keys.onUpPressed: function(event) {
            root.openPicker()
            event.accepted = true
        }
        Keys.onReturnPressed: function(event) {
            root.togglePicker()
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            root.togglePicker()
            event.accepted = true
        }
        Keys.onSpacePressed: function(event) {
            root.togglePicker()
            event.accepted = true
        }
        Keys.onEscapePressed: function(event) {
            if (root.popupVisible) {
                root.closePicker()
                event.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                button.forceActiveFocus()
                root._wasOpenOnPress = root.popupVisible
            }
            onClicked: {
                if (root._wasOpenOnPress)
                    root.closePicker()
                else
                    root.openPicker()
            }
        }

        background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.background
            border.width: button.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
            border.color: button.activeFocus ? Theme.accent : Theme.border

            Behavior on border.color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }

        contentItem: RowLayout {
            spacing: Theme.spacingSm

            Text {
                objectName: "font-picker-label"
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingSm
                Layout.rightMargin: 0
                text: root.currentLabel
                color: button.enabled ? Theme.textPrimary : Theme.textTertiary
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 1
            }

            NekoIcon {
                Layout.rightMargin: Theme.spacingSm
                Layout.preferredWidth: Theme.iconSizeSm
                Layout.preferredHeight: Theme.iconSizeSm
                Layout.alignment: Qt.AlignVCenter
                name: "chevronDown"
                color: button.enabled ? Theme.textSecondary : Theme.textTertiary
            }
        }
    }

    Popup {
        id: popup
        objectName: "font-picker-popup"
        parent: root
        x: 0
        y: root.height + Theme.spacingXs
        width: root.width
        padding: Theme.spacingSm
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: {
            root._returnFocus = false
            root.searchText = ""
            searchField.text = ""
            Qt.callLater(function() {
                root._highlightSelected()
                searchField.forceActiveFocus(Qt.PopupFocusReason)
            })
        }
        onClosed: {
            if (root._returnFocus) {
                root._returnFocus = false
                button.forceActiveFocus(Qt.PopupFocusReason)
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: Motion.duration(Motion.fast)
                easing.type: Motion.decelerateEasing
            }
        }

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
                objectName: "font-picker-search"
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.controlHeightSm
                font.pixelSize: Theme.fontSmall
                color: Theme.textPrimary
                placeholderText: qsTr("Search fonts…")
                placeholderTextColor: Theme.textTertiary
                selectionColor: Theme.selection
                selectedTextColor: Theme.textPrimary
                leftPadding: Theme.spacingSm
                rightPadding: Theme.spacingSm
                verticalAlignment: TextInput.AlignVCenter

                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search fonts")
                Accessible.description: qsTr("Filter the font family list")

                onTextChanged: root.searchText = text
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root._returnFocus = true
                        root.closePicker()
                        event.accepted = true
                    }
                }
                Keys.onDownPressed: function(event) {
                    root._moveHighlight(1)
                    event.accepted = true
                }
                Keys.onUpPressed: function(event) {
                    root._moveHighlight(-1)
                    event.accepted = true
                }
                Keys.onReturnPressed: function(event) {
                    root.chooseIndex(list.currentIndex)
                    event.accepted = true
                }
                Keys.onEnterPressed: function(event) {
                    root.chooseIndex(list.currentIndex)
                    event.accepted = true
                }
                Keys.onEscapePressed: function(event) {
                    root._returnFocus = true
                    root.closePicker()
                    event.accepted = true
                }

                background: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.background
                    border.width: searchField.activeFocus ? Theme.focusRingWidth : Theme.borderWidth
                    border.color: searchField.activeFocus ? Theme.accent : Theme.border
                }
            }

            ListView {
                id: list
                objectName: "font-picker-list"
                Layout.fillWidth: true
                Layout.preferredHeight: root.hasResults
                    ? Math.min(root.listMaxHeight,
                               Math.max(root.rowHeight, Math.max(0, contentHeight)))
                    : 0
                opacity: root.hasResults ? 1 : 0
                clip: true
                model: root.filteredModel
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: true
                ScrollBar.vertical: NekoScrollBar {
                    policy: ScrollBar.AlwaysOff
                    accessibleName: qsTr("Font list scroll")
                }

                delegate: Rectangle {
                    id: option
                    required property var modelData
                    required property int index
                    objectName: "font-picker-option-" + index
                    width: list.width
                    height: root.rowHeight
                    radius: Theme.radiusXs
                    color: ListView.isCurrentItem ? Theme.selection
                           : optionMouse.containsMouse ? Theme.hover
                           : "transparent"

                    Accessible.role: Accessible.ListItem
                    Accessible.name: String(option.modelData.label)
                    Accessible.selected: ListView.isCurrentItem

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(option.modelData.label)
                        color: option.modelData.value === root.currentValue
                               ? Theme.accent : Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        maximumLineCount: 1
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            list.currentIndex = option.index
                            root.chooseIndex(option.index)
                        }
                    }
                }
            }

            Text {
                objectName: "font-picker-empty"
                Layout.fillWidth: true
                Layout.preferredHeight: root.hasResults ? 0 : root.rowHeight
                opacity: root.hasResults ? 0 : 1
                text: qsTr("No fonts match")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSmall
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
