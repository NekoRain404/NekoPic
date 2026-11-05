import QtQuick
import QtQuick.Controls
import "../UI"

/*!
    DropTarget — the full-window image drop surface and its highlight.

    The shell supplies busy state and receives the dropped URL; the component
    does not reach into window state.
*/
Item {
    id: root

    property bool busy: false

    signal openRequested(url url)

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        visible: dropArea.containsDrag
        color: Theme.alpha(Theme.accent, 0.06)
        border.width: 2
        border.color: Theme.accent
        z: 1000
        Label {
            anchors.centerIn: parent
            text: qsTranslate("Main", "Drop to open image")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontHeadline
            font.weight: Theme.fontWeightDemiBold
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: function(drop) {
            if (root.busy || !drop.hasUrls || drop.urls.length === 0)
                return
            root.openRequested(drop.urls[0])
            drop.acceptProposedAction()
        }
    }
}
