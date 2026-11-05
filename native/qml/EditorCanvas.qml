import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var theme
    property url imageUrl
    property bool hasImage: false
    property int imageWidth: 0
    property int imageHeight: 0
    property string fileName: ""
    property bool dirty: false
    property real zoom: 1
    property bool fitting: true
    property bool mosaicActive: false
    property bool mosaicBrushMode: true
    property real mosaicBrushDiameter: 24
    property bool inputEnabled: true
    property bool cropActive: false
    property real cropAspectRatio: 0
    readonly property rect cropSelection: cropOverlay.selection
    signal cropApplyRequested(rect area)
    signal cropCancelled()
    function resetCropSelection() { cropOverlay.resetSelection() }
    signal openRequested()
    signal mosaicRectangleCommitted(rect area)
    signal mosaicStrokeCommitted(var points)

    function fitImage() {
        fitting = true
        if (imageWidth > 0 && imageHeight > 0)
            zoom = Math.min(Math.max(1, viewport.width - 80) / imageWidth,
                            Math.max(1, viewport.height - 80) / imageHeight, 1)
        view.contentX = 0
        view.contentY = 0
    }
    function actualSize() { zoomAt(1 / zoom, viewport.width / 2, viewport.height / 2) }
    function changeZoom(factor) { zoomAt(factor, viewport.width / 2, viewport.height / 2) }
    function zoomAt(factor, x, y) {
        if (!hasImage || zoom <= 0 || factor <= 0) return
        const imageX = (view.contentX + x - picture.x) / zoom
        const imageY = (view.contentY + y - picture.y) / zoom
        fitting = false
        zoom = Math.max(0.05, Math.min(3, zoom * factor))
        view.contentX = Math.max(0, Math.min(view.contentWidth - view.width, picture.x + imageX * zoom - x))
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, picture.y + imageY * zoom - y))
    }
    function panBy(dx, dy) {
        view.contentX = Math.max(0, Math.min(view.contentWidth - view.width, view.contentX - dx))
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY - dy))
    }
    onImageWidthChanged: if (fitting) fitImage()
    onImageHeightChanged: if (fitting) fitImage()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 39
            color: root.theme ? root.theme.background : "#181a1b"
            RowLayout {
                anchors.fill: parent; anchors.rightMargin: 18; spacing: 0
                Rectangle {
                    Layout.fillHeight: true; Layout.maximumWidth: parent.width * 0.7
                    Layout.preferredWidth: Math.min(parent.width * 0.7, tabContent.implicitWidth + 32)
                    color: root.theme ? root.theme.canvas : "#151718"
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: root.theme ? root.theme.accent : "#edbc9d" }
                    Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: root.theme ? root.theme.border : "#343638" }
                    RowLayout {
                        id: tabContent; anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 8
                        Label { text: "▧"; color: root.theme ? root.theme.muted : "#aaa"; font.pixelSize: 15 }
                        Label { Layout.fillWidth: true; text: root.hasImage && root.fileName.length ? root.fileName : qsTr("Untitled"); elide: Text.ElideMiddle; color: root.theme ? root.theme.text : "white"; font.pixelSize: 11 }
                        Rectangle { visible: root.dirty; width: 5; height: 5; radius: 3; color: root.theme ? root.theme.accent : "#edbc9d" }
                    }
                }
                Item { Layout.fillWidth: true }
                Label { visible: parent.width > 330; text: qsTr("WORKSPACE"); color: root.theme ? root.theme.muted : "#aaa"; font.pixelSize: 9 }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.theme ? root.theme.border : "#343638" }
        }
        Rectangle {
            id: viewport
            Layout.fillWidth: true; Layout.fillHeight: true
            color: root.theme ? root.theme.canvas : "#1b1e1d"
            onWidthChanged: if (root.fitting) root.fitImage()
            onHeightChanged: if (root.fitting) root.fitImage()
            Flickable {
                id: view
                objectName: "canvasView"
                anchors.fill: parent; clip: true
                contentWidth: Math.max(width, picture.width + 80)
                contentHeight: Math.max(height, picture.height + 80)
                boundsBehavior: Flickable.StopAtBounds
                interactive: false
                Canvas {
                    id: checker
                    x: view.contentX; y: view.contentY
                    width: view.width; height: view.height
                    visible: root.hasImage
                    property real imageX: picture.x - view.contentX
                    property real imageY: picture.y - view.contentY
                    property real imageW: picture.width
                    property real imageH: picture.height
                    onImageXChanged: requestPaint()
                    onImageYChanged: requestPaint()
                    onImageWChanged: requestPaint()
                    onImageHChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const left = Math.max(0, imageX), top = Math.max(0, imageY)
                        const right = Math.min(width, imageX + imageW), bottom = Math.min(height, imageY + imageH)
                        ctx.fillStyle = "#eeeeee"
                        ctx.fillRect(left, top, right - left, bottom - top)
                        ctx.fillStyle = "#d1d1d1"
                        const cell = 12
                        const firstX = Math.floor((left - imageX) / cell)
                        const firstY = Math.floor((top - imageY) / cell)
                        for (let row = firstY; imageY + row * cell < bottom; ++row) {
                            for (let col = firstX; imageX + col * cell < right; ++col) {
                                if ((row + col) % 2 !== 0) {
                                    const x = Math.max(left, imageX + col * cell)
                                    const y = Math.max(top, imageY + row * cell)
                                    ctx.fillRect(x, y, Math.min(right, imageX + (col + 1) * cell) - x,
                                                 Math.min(bottom, imageY + (row + 1) * cell) - y)
                                }
                            }
                        }
                    }
                }
                Image {
                    id: picture
                    objectName: "canvasPicture"
                    x: (view.contentWidth - width) / 2; y: (view.contentHeight - height) / 2
                    width: root.hasImage ? root.imageWidth * root.zoom : 0
                    height: root.hasImage ? root.imageHeight * root.zoom : 0
                    source: root.imageUrl
                    cache: false; fillMode: Image.PreserveAspectFit
                    CropOverlay {
                        id: cropOverlay
                        objectName: "cropOverlay"
                        anchors.fill: parent
                        active: root.cropActive && root.hasImage
                        inputEnabled: root.inputEnabled
                        imageWidth: root.imageWidth; imageHeight: root.imageHeight
                        aspectRatio: root.cropAspectRatio
                        visibleRect: Qt.rect(view.contentX - picture.x, view.contentY - picture.y,
                                             view.width, view.height)
                        onApplyRequested: function(area) { root.cropApplyRequested(area) }
                        onCancelled: root.cropCancelled()
                    }
                    MosaicOverlay {
                        objectName: "mosaicOverlay"
                        anchors.fill: parent
                        active: root.mosaicActive && root.hasImage
                        inputEnabled: root.inputEnabled
                        brushMode: root.mosaicBrushMode
                        brushDiameter: root.mosaicBrushDiameter
                        imageWidth: root.imageWidth; imageHeight: root.imageHeight
                        viewScale: root.zoom
                        visibleRect: Qt.rect(view.contentX - picture.x, view.contentY - picture.y,
                                             view.width, view.height)
                        onRectangleCommitted: function(area) { root.mosaicRectangleCommitted(area) }
                        onStrokeCommitted: function(points) { root.mosaicStrokeCommitted(points) }
                    }
                }
                ScrollBar.horizontal: ScrollBar { }
                ScrollBar.vertical: ScrollBar { }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                enabled: root.hasImage
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                property real lastX: 0
                property real lastY: 0
                onWheel: function(event) {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                    if (delta !== 0) root.zoomAt(Math.pow(1.2, delta / 120), event.x, event.y)
                    event.accepted = true
                }
                onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
                onPositionChanged: function(mouse) {
                    if (pressed) {
                        root.panBy(mouse.x - lastX, mouse.y - lastY)
                        lastX = mouse.x; lastY = mouse.y
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 12; visible: !root.hasImage
                Canvas {
                    Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    onPaint: {
                        const c = getContext("2d"); c.reset(); c.strokeStyle = root.theme ? root.theme.accent : "#edbc9d"
                        c.lineWidth = 1.5; c.lineCap = "round"; c.lineJoin = "round"
                        c.beginPath(); c.moveTo(4, 10); c.lineTo(15, 10); c.lineTo(19, 14); c.lineTo(36, 14); c.lineTo(36, 31); c.lineTo(4, 31); c.closePath(); c.stroke()
                    }
                }
                Label { Layout.alignment: Qt.AlignHCenter; text: qsTr("Start with an image"); font.pixelSize: 19; font.weight: Font.DemiBold; color: root.theme ? root.theme.text : "white" }
                Label { Layout.alignment: Qt.AlignHCenter; text: qsTr("Open a photo to begin"); color: root.theme ? root.theme.muted : "#aaa" }
                Button {
                    id: openButton; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8
                    text: qsTr("Open image"); onClicked: root.openRequested()
                    implicitWidth: 112; implicitHeight: 36
                    background: Rectangle { radius: 5; color: root.theme ? (openButton.hovered ? root.theme.hover : root.theme.accent) : "#edbc9d" }
                    contentItem: Label { text: openButton.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: root.theme ? (openButton.hovered ? root.theme.text : root.theme.accentInk) : "#292420"; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 43
            color: root.theme ? root.theme.background : "#181a1b"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.theme ? root.theme.border : "#343638" }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 6
                Rectangle { width: 5; height: 5; radius: 3; color: "#99b4a3" }
                Label { text: root.hasImage ? qsTr("Image ready") : qsTr("Canvas ready"); color: root.theme ? root.theme.muted : "#aaa"; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                ToolButton { text: "−"; enabled: root.hasImage; ToolTip.visible: hovered; ToolTip.text: qsTr("Zoom out"); onClicked: root.changeZoom(1 / 1.2) }
                Label { text: Math.round(root.zoom * 100) + "%"; color: root.theme ? root.theme.text : "white"; Layout.preferredWidth: 45; horizontalAlignment: Text.AlignHCenter }
                ToolButton { text: "+"; enabled: root.hasImage; ToolTip.visible: hovered; ToolTip.text: qsTr("Zoom in"); onClicked: root.changeZoom(1.2) }
                ToolButton { text: qsTr("100%"); enabled: root.hasImage; onClicked: root.actualSize() }
                ToolButton { text: qsTr("Fit"); enabled: root.hasImage; onClicked: root.fitImage() }
            }
        }
    }
}
