pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    LayerPanel — object list, stacking order and alignment for the select tool.

    The panel is a pure view: it renders the `summaries` supplied by
    DocumentController::objectSummaries() (topmost first) and keeps its
    highlight in sync with the external `selectedIds` property. It never
    mutates the document itself; every gesture is reported through a signal so
    the owner can call the matching controller method:

        LayerPanel {
            objectName: "layerPanel"
            summaries: editor.objectSummaries()      // refreshed on documentChanged
            selectedIds: canvas.selectionIds         // shared with SelectionOverlay
            onSelectionRequested: function(ids) { ... }
            onVisibilityToggled: function(id, visible) { editor.setObjectVisible(id, visible) }
            onLockToggled: function(id, locked) { editor.setObjectLocked(id, locked) }
            onOrderRequested: function(id, action) {
                if (action === "front") editor.bringObjectToFront(id)
                else if (action === "back") editor.sendObjectToBack(id)
                else if (action === "up") editor.raiseObject(id)
                else editor.lowerObject(id)
            }
            onRemoveRequested: function(ids) { editor.removeObjects(ids) }
            onAlignRequested: function(ids, alignment) { editor.alignObjects(ids, alignment) }
        }

    Signals:
      • selectionRequested(ids)      — row click / Shift toggle. `ids` is the
                                       complete replacement selection.
      • visibilityToggled(id, visible)
      • lockToggled(id, locked)
      • orderRequested(id, action)   — action is "front" | "up" | "down" | "back".
      • removeRequested(ids)         — Delete button or Delete/Backspace key
                                       while the panel has focus.
      • alignRequested(ids, alignment) — Qt::Alignment flag for the six
                                       image-edge/centre alignments.

    Properties:
      • summaries  — array of maps from DocumentController::objectSummaries().
      • selectedIds — externally owned selection set, kept in sync by the owner.
      • theme      — token map supplied by Main; defaults keep it standalone.
      • enabled    — disables row actions while a document command is running.

    Compact by design: the panel is 292 px wide with 22 px icon buttons.
    Every interactive control has an objectName and an accessible name.
*/
Rectangle {
    id: root

    objectName: "layerPanel"

    /*! Token map supplied by Main; defaults keep the panel standalone. */
    property var theme: ({ panel: Theme.panel, background: Theme.background,
                           raised: Theme.surfaceRaised, hover: Theme.hover,
                           border: Theme.border, separator: Theme.separator,
                           text: Theme.textPrimary, muted: Theme.textSecondary,
                           accent: Theme.accent })

    /*! Topmost-first summaries: [{ id, kind, name, bounds, visible, locked }] */
    property var summaries: []
    /*! Selection set shared with SelectionOverlay (authoritative owner state). */
    property var selectedIds: []
    property bool enabled: true

    signal selectionRequested(var ids)
    signal visibilityToggled(var id, bool visible)
    signal lockToggled(var id, bool locked)
    signal orderRequested(var id, string action)
    signal removeRequested(var ids)
    signal alignRequested(var ids, int alignment)

    implicitWidth: 292
    implicitHeight: 380
    color: root.theme.panel

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Layers")
    Accessible.description: qsTr("Object list with stacking order, visibility, lock and alignment controls.")

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _normalizeId(value) {
        if (value === undefined || value === null)
            return 0
        const id = Number(value)
        if (!isFinite(id) || id <= 0)
            return 0
        return Math.floor(id)
    }

    function _summaryList() {
        return Array.isArray(summaries) ? summaries : []
    }

    function _summaryIds() {
        const result = []
        const list = _summaryList()
        for (let i = 0; i < list.length; ++i) {
            const id = _normalizeId(list[i].id)
            if (id !== 0 && result.indexOf(id) < 0)
                result.push(id)
        }
        return result
    }

    /*! selectedIds filtered to ids that still exist, in list order. */
    function _selectedValid() {
        const input = Array.isArray(selectedIds) ? selectedIds : [selectedIds]
        const available = _summaryIds()
        const result = []
        for (let i = 0; i < input.length; ++i) {
            const id = _normalizeId(input[i])
            if (id !== 0 && available.indexOf(id) >= 0 && result.indexOf(id) < 0)
                result.push(id)
        }
        return result
    }

    function _isSelected(id) {
        return _selectedValid().indexOf(id) >= 0
    }

    function _selectionForClick(id, modifiers) {
        const target = _normalizeId(id)
        const current = _selectedValid()
        if (target === 0)
            return current
        if (modifiers & Qt.ShiftModifier) {
            const index = current.indexOf(target)
            if (index >= 0)
                current.splice(index, 1)
            else
                current.push(target)
            return current
        }
        return [target]
    }

    function _kindIcon(kind) {
        switch (kind) {
        case "text": return "text"
        case "shape": return "shapes"
        case "stroke": return "brush"
        default: return "shapes"
        }
    }

    function _typeLabel(kind) {
        switch (kind) {
        case "text": return qsTr("Text")
        case "shape": return qsTr("Shape")
        case "stroke": return qsTr("Stroke")
        default: return qsTr("Object")
        }
    }

    /*! Removes every selected object (one removeRequested for the group). */
    function removeSelected() {
        if (!root.enabled)
            return false
        const ids = _selectedValid()
        if (ids.length === 0)
            return false
        root.removeRequested(ids)
        return true
    }

    function _align(flag) {
        if (!root.enabled)
            return
        const ids = _selectedValid()
        if (ids.length === 0)
            return
        root.alignRequested(ids, flag)
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (root.removeSelected())
                event.accepted = true
        }
    }

    // ── Inline drawing helpers ──────────────────────────────────────────────
    component LockGlyph: Canvas {
        id: lockGlyph
        property bool locked: false
        property color ink: Theme.textSecondary
        implicitWidth: 14
        implicitHeight: 14
        onLockedChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.scale(width / 24, height / 24)
            c.strokeStyle = lockGlyph.ink
            c.lineWidth = 2.2
            c.lineCap = "round"
            c.lineJoin = "round"
            c.beginPath()
            // Shackle: closed is centred, open is offset and lifted.
            if (lockGlyph.locked)
                c.arc(12, 10, 6, Math.PI, 2 * Math.PI)
            else
                c.arc(16, 10, 6, Math.PI, 2 * Math.PI)
            c.moveTo(5, 11)
            c.lineTo(19, 11)
            c.lineTo(19, 21)
            c.lineTo(5, 21)
            c.closePath()
            c.stroke()
        }
    }

    component GlyphButton: AbstractButton {
        id: glyphButton
        property string glyph: ""
        property string accessibleName: ""
        implicitWidth: 22
        implicitHeight: 22
        padding: 0
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: true
        opacity: enabled ? 1 : Theme.opacityDisabled

        Accessible.role: Accessible.Button
        Accessible.name: glyphButton.accessibleName

        background: Rectangle {
            radius: Theme.radiusXs
            color: glyphButton.down ? Theme.pressed
                   : glyphButton.hovered ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }

        contentItem: Text {
            text: glyphButton.glyph
            color: !glyphButton.enabled ? Theme.textTertiary
                   : glyphButton.hovered ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontSmall
            font.weight: Theme.fontWeightMedium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── Content ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingSm

        // Header: title, count, alignment bar.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                Layout.fillWidth: true
                text: qsTr("LAYERS")
                color: root.theme.muted
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.fontWeightDemiBold
                font.letterSpacing: Theme.trackingWide
            }

            Text {
                objectName: "layerCount"
                text: root._summaryList().length
                color: Theme.textTertiary
                font.pixelSize: Theme.fontCaption
            }
        }

        RowLayout {
            objectName: "alignBar"
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: [
                    { action: "left", glyph: "L", flag: Qt.AlignLeft,
                      label: qsTr("Align left edges") },
                    { action: "hcenter", glyph: "C", flag: Qt.AlignHCenter,
                      label: qsTr("Align horizontal centres") },
                    { action: "right", glyph: "R", flag: Qt.AlignRight,
                      label: qsTr("Align right edges") },
                    { action: "top", glyph: "T", flag: Qt.AlignTop,
                      label: qsTr("Align top edges") },
                    { action: "vcenter", glyph: "M", flag: Qt.AlignVCenter,
                      label: qsTr("Align vertical centres") },
                    { action: "bottom", glyph: "B", flag: Qt.AlignBottom,
                      label: qsTr("Align bottom edges") }
                ]

                delegate: NekoIconButton {
                    required property var modelData
                    objectName: "align-" + modelData.action
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    buttonSize: 24
                    iconSize: 14
                    iconName: "align-" + modelData.action
                    accessibleName: modelData.label
                    enabled: root.enabled && root._selectedValid().length > 0
                    onClicked: root._align(modelData.flag)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.borderWidth
            color: root.theme.separator
        }

        // Empty state.
        Text {
            objectName: "layerEmptyState"
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingLg
            visible: root._summaryList().length === 0
            text: qsTr("No objects yet")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Topmost-first object list.
        ListView {
            id: layerList
            objectName: "layerList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root._summaryList().length > 0
            clip: true
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            model: root.summaries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property int objectId: root._normalizeId(modelData.id)
                readonly property bool isSelected: root._isSelected(objectId)
                readonly property bool isVisible: modelData.visible === true
                readonly property bool isLocked: modelData.locked === true

                objectName: "layerRow-" + objectId
                width: ListView.view ? ListView.view.width : 0
                height: 36
                radius: Theme.radiusXs
                color: isSelected ? Theme.selection
                       : rowHover.containsMouse ? Theme.hover : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Motion.duration(Motion.fast)
                        easing.type: Motion.decelerateEasing
                    }
                }

                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name
                Accessible.description: root._typeLabel(modelData.kind)
                Accessible.selected: isSelected

                // Row click sits below the controls, so buttons keep their hits.
                MouseArea {
                    id: rowHover
                    objectName: "layerRowClick-" + row.objectId
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) {
                        root.selectionRequested(root._selectionForClick(row.objectId,
                                                                        mouse.modifiers))
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 2
                    spacing: 2

                    NekoIcon {
                        objectName: "layerTypeIcon-" + row.objectId
                        Layout.preferredWidth: Theme.iconSizeSm
                        Layout.preferredHeight: Theme.iconSizeSm
                        name: root._kindIcon(row.modelData.kind)
                        color: row.isSelected ? Theme.accent
                               : row.isVisible ? Theme.textSecondary : Theme.textTertiary
                    }

                    Text {
                        objectName: "layerName-" + row.objectId
                        Layout.fillWidth: true
                        Layout.minimumWidth: 24
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: row.isVisible
                               ? (row.isSelected ? root.theme.text : Theme.textPrimary)
                               : Theme.textTertiary
                        font.pixelSize: Theme.fontSmall
                        font.weight: row.isSelected ? Theme.fontWeightMedium
                                                    : Theme.fontWeightRegular
                        verticalAlignment: Text.AlignVCenter
                    }

                    NekoIconButton {
                        objectName: "visibility-" + row.objectId
                        buttonSize: 22
                        iconSize: 14
                        checkable: false
                        checked: !row.isVisible
                        iconName: row.isVisible ? "eye" : "eyeOff"
                        accessibleName: row.isVisible
                                        ? qsTr("Hide %1").arg(row.modelData.name)
                                        : qsTr("Show %1").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.visibilityToggled(row.objectId, !row.isVisible)
                    }

                    NekoIconButton {
                        id: lockButton
                        objectName: "lock-" + row.objectId
                        buttonSize: 22
                        iconSize: 14
                        checkable: false
                        checked: row.isLocked
                        accessibleName: row.isLocked
                                        ? qsTr("Unlock %1").arg(row.modelData.name)
                                        : qsTr("Lock %1").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.lockToggled(row.objectId, !row.isLocked)
                        contentItem: LockGlyph {
                            anchors.centerIn: parent
                            locked: row.isLocked
                            ink: !lockButton.enabled ? Theme.textTertiary
                                 : lockButton.checked ? Theme.accent
                                 : lockButton.hovered ? Theme.textPrimary : Theme.textSecondary
                        }
                    }

                    GlyphButton {
                        objectName: "front-" + row.objectId
                        glyph: "⇈"
                        accessibleName: qsTr("Bring %1 to front").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.orderRequested(row.objectId, "front")
                    }

                    GlyphButton {
                        objectName: "up-" + row.objectId
                        glyph: "↑"
                        accessibleName: qsTr("Raise %1").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.orderRequested(row.objectId, "up")
                    }

                    GlyphButton {
                        objectName: "down-" + row.objectId
                        glyph: "↓"
                        accessibleName: qsTr("Lower %1").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.orderRequested(row.objectId, "down")
                    }

                    GlyphButton {
                        objectName: "back-" + row.objectId
                        glyph: "⇊"
                        accessibleName: qsTr("Send %1 to back").arg(row.modelData.name)
                        enabled: root.enabled
                        onClicked: root.orderRequested(row.objectId, "back")
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.borderWidth
            color: root.theme.separator
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Item { Layout.fillWidth: true }

            NekoButton {
                objectName: "deleteSelected"
                text: qsTr("Delete")
                variant: "ghost"
                implicitHeight: 26
                enabled: root.enabled && root._selectedValid().length > 0
                accessibleName: qsTr("Delete selected objects")
                onClicked: root.removeSelected()
            }
        }
    }
}
