import QtQuick
import "../UI"

/*!
    Loupe — the eyedropper's magnifier.

    Shows a pixel-accurate crop of the source image around a sample point,
    a crosshair marking the sampled pixel, and a compact hex / RGB readout.

    The preview is viewport-backed: the source Image uses sourceClipRect so
    only the small crop around the sample is rasterised to this item's size.
    No image-sized buffer or Canvas is ever allocated.

    Coordinate notes:
      • sampleX / sampleY are in source-image pixels (continuous).
      • sourceRect is clamped inside the image, so near an edge the crosshair
        slides off-centre instead of the preview showing out-of-bounds pixels.
      • crosshairX / crosshairY are local to the preview area.
*/
Item {
    id: root

    /*! Image URL shown by the magnifier. Empty shows a neutral placeholder. */
    property url source: ""
    property int imageWidth: 0
    property int imageHeight: 0
    /*! Sample position in source-image pixels. */
    property real sampleX: 0
    property real sampleY: 0
    /*! Overall loupe width; the preview area is inset slightly. */
    property real size: 132
    /*! Magnification factor relative to the source image's pixels. */
    property real zoomFactor: 8
    property color color: "transparent"
    property bool hasSample: false
    property string hexText: "—"
    property string rgbText: "—"
    /*! Breathing room kept by EyedropperOverlay when positioning the loupe. */
    property real margin: 10

    readonly property real previewInset: Theme.spacingXs
    readonly property real previewSize: Math.max(0, size - 2 * previewInset)
    /*! Height of the readout strip below the magnifier. */
    readonly property real readoutHeight: 46

    readonly property real cropWidth: Math.max(1, Math.min(Math.max(1, imageWidth),
                                                           previewSize / Math.max(1, zoomFactor)))
    readonly property real cropHeight: Math.max(1, Math.min(Math.max(1, imageHeight),
                                                            previewSize / Math.max(1, zoomFactor)))

    /*! Crop requested from the source, clamped to the image bounds. */
    readonly property rect sourceRect: {
        const iw = Math.max(1, imageWidth)
        const ih = Math.max(1, imageHeight)
        const w = Math.min(iw, cropWidth)
        const h = Math.min(ih, cropHeight)
        const x = Math.max(0, Math.min(iw - w, sampleX - w / 2))
        const y = Math.max(0, Math.min(ih - h, sampleY - h / 2))
        return Qt.rect(x, y, w, h)
    }
    readonly property bool validSample: imageWidth > 0 && imageHeight > 0

    /*! Crosshair position inside the preview, in local pixels. */
    readonly property real crosshairX: validSample && sourceRect.width > 0
                                       ? Math.max(0, Math.min(previewSize,
                                                              (sampleX - sourceRect.x) / sourceRect.width * previewSize))
                                       : previewSize / 2
    readonly property real crosshairY: validSample && sourceRect.height > 0
                                       ? Math.max(0, Math.min(previewSize,
                                                              (sampleY - sourceRect.y) / sourceRect.height * previewSize))
                                       : previewSize / 2
    /*! Size of one source pixel in the magnified preview. */
    readonly property real pixelCell: validSample && sourceRect.width > 0
                                      ? Math.max(2, Math.min(previewSize,
                                                             previewSize / sourceRect.width))
                                      : 0

    width: size
    height: size + readoutHeight
    implicitWidth: width
    implicitHeight: height

    // Soft elevation without importing Effects: layered rectangles keep the
    // look identical on the RHI and software scenegraph backends.
    Rectangle {
        anchors.fill: body
        anchors.margins: -Theme.elevationMedium.spread
        anchors.topMargin: -Theme.elevationMedium.spread + Theme.elevationMedium.offsetY
        radius: body.radius + Theme.elevationMedium.spread
        color: Theme.shadowColor
        opacity: Theme.elevationMedium.opacity
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.surfaceRaised
        border.width: Theme.borderWidth
        border.color: Theme.border
    }

    Rectangle {
        id: previewFrame
        x: root.previewInset
        y: root.previewInset
        width: root.previewSize
        height: root.previewSize
        radius: Theme.radiusSm
        color: Theme.canvas
        clip: true

        Image {
            id: zoomed
            objectName: "loupePreview"
            anchors.fill: parent
            // sourceClipRect keeps rasterisation bounded to the crop, even
            // when the source is a very large photograph.
            source: root.source
            sourceClipRect: Qt.rect(root.sourceRect.x, root.sourceRect.y,
                                    root.sourceRect.width, root.sourceRect.height)
            fillMode: Image.Stretch
            smooth: false
            cache: false
            asynchronous: true
            visible: root.source.toString().length > 0 && status === Image.Ready
        }

        // Neutral placeholder while the image loads or when no URL is set.
        Rectangle {
            anchors.fill: parent
            visible: !zoomed.visible
            color: Theme.canvas
            NekoIcon {
                anchors.centerIn: parent
                width: Theme.iconSizeLg
                height: Theme.iconSizeLg
                name: "eye"
                color: Theme.textTertiary
                opacity: Theme.opacityMuted
            }
        }

        Canvas {
            id: crosshair
            anchors.fill: parent
            visible: root.validSample
            onPaint: {
                const c = getContext("2d")
                c.reset()
                const cx = Math.round(root.crosshairX) + 0.5
                const cy = Math.round(root.crosshairY) + 0.5
                const cell = root.pixelCell

                if (root.hasSample && cell > 0) {
                    c.fillStyle = Theme.alpha(root.color, 0.35)
                    c.fillRect(cx - cell / 2, cy - cell / 2, cell, cell)
                }

                // A dark halo keeps the crosshair legible on any photograph.
                c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.6)
                c.lineWidth = 3
                c.beginPath()
                c.moveTo(0, cy); c.lineTo(width, cy)
                c.moveTo(cx, 0); c.lineTo(cx, height)
                c.stroke()

                c.strokeStyle = Theme.accent
                c.lineWidth = 1
                c.beginPath()
                c.moveTo(0, cy); c.lineTo(width, cy)
                c.moveTo(cx, 0); c.lineTo(cx, height)
                c.stroke()

                if (cell > 0) {
                    c.strokeStyle = Theme.alpha(Theme.contrastInk, 0.7)
                    c.lineWidth = 3
                    c.strokeRect(cx - cell / 2, cy - cell / 2, cell, cell)
                    c.strokeStyle = Theme.contrastPaper
                    c.lineWidth = 1
                    c.strokeRect(cx - cell / 2, cy - cell / 2, cell, cell)
                }
            }
        }

        // Hairline over the preview's rounded edge.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: Theme.borderWidth
            border.color: Theme.alpha(Theme.contrastInk, 0.35)
        }
    }

    Item {
        id: readout
        x: Theme.spacingSm
        y: root.size + 2
        width: root.width - 2 * Theme.spacingSm
        height: root.readoutHeight - 4

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSm

            Rectangle {
                id: swatch
                width: Theme.iconSizeSm
                height: Theme.iconSizeSm
                radius: Theme.radiusXs
                anchors.verticalCenter: parent.verticalCenter
                color: root.hasSample ? root.color : Theme.hover
                border.width: Theme.borderWidth
                border.color: root.hasSample ? Theme.alpha(Theme.contrastInk, 0.25) : Theme.border
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                width: readout.width - swatch.width - Theme.spacingSm

                Text {
                    objectName: "loupeHex"
                    width: parent.width
                    text: root.hexText
                    color: root.hasSample ? Theme.textPrimary : Theme.textTertiary
                    font.pixelSize: Theme.fontSmall
                    font.weight: Theme.fontWeightDemiBold
                    font.family: "monospace"
                    font.letterSpacing: Theme.trackingTight
                    elide: Text.ElideRight
                }
                Text {
                    objectName: "loupeRgb"
                    width: parent.width
                    text: root.rgbText
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontCaption
                    font.family: "monospace"
                    elide: Text.ElideRight
                }
            }
        }
    }

    Connections {
        target: root
        function onCrosshairXChanged() { crosshair.requestPaint() }
        function onCrosshairYChanged() { crosshair.requestPaint() }
        function onHasSampleChanged() { crosshair.requestPaint() }
        function onColorChanged() { crosshair.requestPaint() }
        function onPreviewSizeChanged() { crosshair.requestPaint() }
    }
    Connections {
        target: Theme
        function onDarkChanged() { crosshair.requestPaint() }
    }
}
