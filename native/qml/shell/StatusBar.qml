import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../UI"

/*!
    StatusBar — document facts, zoom controls and the transient status line.

    The bar is presentation only. Canvas and document state arrive through
    properties, and every zoom gesture is reported through signals so the
    shell can drive the canvas.
*/
Rectangle {
    id: page

    property bool hasImage: false
    property int imageWidth: 0
    property int imageHeight: 0
    property int objectCount: 0
    property bool busy: false
    property bool dirty: false
    property string transientStatus: ""
    property real zoom: 1.0

    signal zoomOutRequested()
    signal zoomInRequested()
    signal zoomValueRequested(real value)
    signal actualSizeRequested()
    signal fitRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: 30
    color: Theme.panel

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        spacing: Theme.spacingSm

        Label {
            objectName: "status-dimensions"
            text: page.hasImage ? page.imageWidth + " × " + page.imageHeight + " px" : "— × — px"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
        }
        Text {
            text: "/"
            color: Theme.border
            font.pixelSize: Theme.fontCaption
        }
        Label {
            objectName: "status-srgb"
            text: "sRGB"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
        }
        Text {
            text: "/"
            color: Theme.border
            font.pixelSize: Theme.fontCaption
        }
        Label {
            objectName: "status-object-count"
            text: page.objectCount === 1 ? qsTr("1 object")
                                        : qsTr("%1 objects").arg(page.objectCount)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
        }
        Item { Layout.fillWidth: true }

        NekoIconButton {
            objectName: "status-zoom-out"
            iconName: "minus"
            buttonSize: 22
            iconSize: 14
            accessibleName: qsTr("Zoom out")
            enabled: page.hasImage && page.zoom > 0.0501
            onClicked: page.zoomOutRequested()
        }
        NekoSlider {
            id: statusZoomSlider
            objectName: "status-zoom-slider"
            Layout.preferredWidth: 104
            Layout.preferredHeight: Theme.sliderHeight
            from: 5
            to: 300
            stepSize: 1
            value: page.zoom * 100
            enabled: page.hasImage
            accessibleName: qsTr("Canvas zoom")
            onPreview: function(value) { page.zoomValueRequested(value / 100) }
            onFinish: function(value) { page.zoomValueRequested(value / 100) }
            Connections {
                target: page
                function onZoomChanged() {
                    if (!statusZoomSlider.dragging)
                        statusZoomSlider.value = page.zoom * 100
                }
            }
        }
        NekoIconButton {
            objectName: "status-zoom-in"
            iconName: "plus"
            buttonSize: 22
            iconSize: 14
            accessibleName: qsTr("Zoom in")
            enabled: page.hasImage && page.zoom < 2.999
            onClicked: page.zoomInRequested()
        }
        Label {
            objectName: "status-zoom-value"
            text: Math.round(page.zoom * 100) + "%"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontCaption
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignHCenter
        }
        NekoButton {
            objectName: "status-zoom-actual"
            text: qsTr("100%")
            variant: "ghost"
            implicitHeight: 22
            enabled: page.hasImage
            onClicked: page.actualSizeRequested()
        }
        NekoButton {
            objectName: "status-zoom-fit"
            text: qsTr("Fit")
            variant: "ghost"
            implicitHeight: 22
            enabled: page.hasImage
            onClicked: page.fitRequested()
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            color: Theme.border
        }
        Label {
            objectName: "statusMessage"
            text: page.busy ? qsTr("Working…")
                  : page.transientStatus.length > 0 ? page.transientStatus
                  : page.dirty ? qsTr("Unsaved changes") : qsTr("Local editing")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideRight
            Layout.maximumWidth: 190
        }
    }
}
