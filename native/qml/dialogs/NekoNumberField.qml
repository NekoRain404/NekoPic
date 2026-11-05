import QtQuick
import QtQuick.Controls
import "../UI"

/*!
    NekoNumberField — integer-only text input for dialog forms.

    The field validates digits against an inclusive range, exposes the parsed
    value and `valid` for live form validation, supports Up/Down (1) and
    Shift+Up/Down (10) stepping, and draws the design system's focus ring and
    danger border. Values can be written programmatically while suppressing
    the `edited()` signal (used for aspect-ratio synchronisation).
*/
Item {
    id: root

    /*! Visible text; assign directly to change the draft value. */
    property alias text: input.text
    property string placeholderText: ""
    property int minimum: 1
    property int maximum: 32768
    property string accessibleName: ""
    /*! Internal: when true, a text change is treated as a programmatic sync
        and does not emit edited(). */
    property bool suppressEdit: false

    /* Derived state; updated synchronously by refreshFromText(). */
    property string trimmedText: ""
    property bool hasInteger: false
    property int numericValue: 0
    property bool valid: false

    /*! Emitted for user edits (typing, paste, and step keys). */
    signal edited()

    implicitWidth: Theme.controlMinWidth
    implicitHeight: Theme.controlHeight

    onMinimumChanged: refreshFromText()
    onMaximumChanged: refreshFromText()
    Component.onCompleted: refreshFromText()

    /* Derived values are refreshed synchronously before edited() is emitted,
       so handlers never observe a stale numericValue/valid pair. */
    function refreshFromText() {
        const raw = input.text.length > 0 ? input.text.trim() : ""
        trimmedText = raw
        hasInteger = /^[0-9]+$/.test(raw)
        numericValue = hasInteger ? parseInt(raw, 10) : 0
        valid = hasInteger && numericValue >= minimum && numericValue <= maximum
    }

    function step(delta) {
        const base = valid ? numericValue : minimum
        const next = Math.max(minimum, Math.min(maximum, base + delta))
        input.text = String(next)
        input.cursorPosition = input.text.length
    }

    TextField {
        id: input
        anchors.fill: parent
        objectName: root.objectName.length > 0 ? root.objectName + "-input" : "input"
        placeholderText: root.placeholderText
        placeholderTextColor: Theme.textTertiary
        color: root.enabled ? Theme.textPrimary : Theme.textTertiary
        font.pixelSize: Theme.fontSmall
        font.weight: Theme.fontWeightMedium
        leftPadding: Theme.spacingMd
        rightPadding: Theme.spacingMd
        topPadding: 0
        bottomPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: root.minimum; top: root.maximum }

        Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : qsTr("Numeric value")
        Accessible.description: qsTr("Integer between %1 and %2").arg(root.minimum).arg(root.maximum)
        Accessible.focusable: true
        Accessible.focused: input.activeFocus

        onTextChanged: {
            root.refreshFromText()
            if (!root.suppressEdit)
                root.edited()
        }
        onActiveFocusChanged: if (activeFocus) selectAll()

        Keys.onUpPressed: function(event) {
            root.step(event.modifiers & Qt.ShiftModifier ? 10 : 1)
            event.accepted = true
        }
        Keys.onDownPressed: function(event) {
            root.step(event.modifiers & Qt.ShiftModifier ? -10 : -1)
            event.accepted = true
        }

        background: Rectangle {
            radius: Theme.radiusSm
            color: root.enabled ? Theme.background : Theme.surfaceRaised
            border.width: Theme.borderWidth
            border.color: root.trimmedText.length > 0 && !root.valid
                          ? Theme.danger
                          : input.activeFocus ? Theme.accent : Theme.border
            Behavior on border.color {
                ColorAnimation {
                    duration: Motion.duration(Motion.fast)
                    easing.type: Motion.decelerateEasing
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingOffset
        radius: Theme.radiusSm + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: input.activeFocus && root.enabled
    }
}
