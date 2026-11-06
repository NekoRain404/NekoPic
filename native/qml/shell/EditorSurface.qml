import QtQuick
import QtQuick.Layouts
import ".."
import "../UI"

/*!
    EditorSurface — the canvas and its document-facing bindings.

    The shell supplies the controller, tool panels and the few view-state
    values the canvas needs; operations that change shell state are reported
    through signals. The component root is EditorCanvas, so the shell keeps
    every existing canvas method and property.
*/
EditorCanvas {
    id: surface
    objectName: "editorCanvas"
    Layout.fillWidth: true
    Layout.fillHeight: true
    theme: ({
        panel: Theme.panel,
        background: Theme.background,
        raised: Theme.surfaceRaised,
        hover: Theme.hover,
        border: Theme.border,
        text: Theme.textPrimary,
        muted: Theme.textSecondary,
        accent: Theme.accent
    })

    property var editorModel: null
    property var panels: ({})
    property var settingsObject: null
    property var renderCapabilitiesObject: null
    property var recentFilesObject: null
    property string activeTool: "adjust"

    signal toolChangeRequested(string tool)
    signal statusRequested(string message)
    signal textObjectActivated(var info)
    signal textPointChosen(real imageX, real imageY)
    signal cropApplyChosen(var area)
    signal movePreviewStarted()
    signal movePreviewSettled()
    signal recentOpenRequested(url url)
    signal openDialogRequested()
    signal foregroundColorRequested(color value)
    signal colorSampleChanged(color value, real imageX, real imageY)

    hasImage: editorModel ? editorModel.hasImage : false
    imageUrl: editorModel ? editorModel.imageUrl : ""
    imageWidth: editorModel ? editorModel.imageWidth : 0
    imageHeight: editorModel ? editorModel.imageHeight : 0
    baseImageUrl: editorModel && editorModel.baseImageUrl !== undefined ? editorModel.baseImageUrl : ""
    gpuPreviewAvailable: renderCapabilitiesObject
                         && renderCapabilitiesObject.gpuPreviewAvailable
                         && (!settingsObject || settingsObject.gpuPreviewEnabled)
    showCheckerboard: !settingsObject || settingsObject.showCheckerboard
    adjustmentPreviewActive: editorModel
                             && editorModel.adjustmentPreviewGpuEligible !== undefined
                             && editorModel.adjustmentPreviewGpuEligible
                             && (editorModel.filterPreset === undefined
                                 || editorModel.filterPreset === "none")
    previewExposure: surface._pending("exposure") / 25
    previewBrightness: surface._pending("brightness") / 100
    previewContrast: surface._pending("contrast") / 100
    previewSaturation: surface._pending("saturation") / 100
    previewHighlights: surface._pending("highlights") / 100
    previewShadows: surface._pending("shadows") / 100
    previewWhites: surface._pending("whites") / 100
    previewBlacks: surface._pending("blacks") / 100
    previewTemperature: surface._pending("temperature") / 100
    previewTint: surface._pending("tint") / 100
    previewVibrance: surface._pending("vibrance") / 100

    function _pending(key) {
        if (!editorModel || !editorModel.pendingAdjustmentValues)
            return 0
        const value = editorModel.pendingAdjustmentValues[key]
        return value === undefined ? 0 : value
    }

    fileName: editorModel ? editorModel.fileName : ""
    dirty: editorModel ? editorModel.dirty : false
    mosaicActive: surface.activeTool === "mosaic"
    cropActive: surface.activeTool === "crop"
    eyedropperActive: surface.activeTool === "eye"
    textActive: surface.activeTool === "text"
    panActive: surface.activeTool === "pan"
    busy: editorModel ? editorModel.busy : false
    selectionActive: surface.activeTool === "select"
    movePreviewReady: editorModel ? editorModel.objectMovePreviewReady : false
    movePreviewBaseUrl: editorModel ? editorModel.objectMoveBaseUrl : ""
    movePreviewObjectUrl: editorModel ? editorModel.objectMoveObjectUrl : ""
    movePreviewBounds: editorModel ? editorModel.objectMoveBounds : Qt.rect(0, 0, 0, 0)
    shapeActive: surface.activeTool === "shapes" && panels.shape
                 && panels.shape.shapeKind !== "polygon"
    polygonActive: surface.activeTool === "shapes" && panels.shape
                   && panels.shape.shapeKind === "polygon"
    brushActive: surface.activeTool === "brush"
    brushDiameter: panels.brush ? panels.brush.diameter : 0
    brushColor: panels.brush ? panels.brush.color : "transparent"
    brushOpacity: panels.brush ? panels.brush.inkOpacity : 100
    brushSoftness: panels.brush ? panels.brush.softness : 0

    onBrushStrokeCommitted: function(points) {
        if (!editorModel || !panels.brush)
            return
        editorModel.addBrushStroke(points, panels.brush.diameter,
                                   panels.brush.effectiveColor,
                                   panels.brush.softness / 100)
    }
    onBrushCancelled: surface.toolChangeRequested("adjust")

    shapeKind: panels.shape ? panels.shape.shapeKind : "rect"
    shapeFillColor: panels.shape ? panels.shape.fillColor : "transparent"
    shapeStrokeColor: panels.shape ? panels.shape.strokeColor : "transparent"
    shapeStrokeWidth: panels.shape ? panels.shape.strokeWidth : 1
    shapeCornerRadius: panels.shape ? panels.shape.cornerRadius : 0
    shapeFilled: panels.shape ? panels.shape.filled : false
    onShapeCommitted: function(kind, area) {
        if (!editorModel || !panels.shape)
            return
        editorModel.addShape(kind, area,
                             panels.shape.filled ? panels.shape.fillColor : "transparent",
                             panels.shape.strokeColor, panels.shape.strokeWidth,
                             panels.shape.cornerRadius)
    }
    onShapeCancelled: surface.toolChangeRequested("adjust")
    onPolygonCommitted: function(points) {
        if (!editorModel || !panels.shape)
            return
        editorModel.addPolygon(points,
                               panels.shape.filled ? panels.shape.fillColor : "transparent",
                               panels.shape.strokeColor, panels.shape.strokeWidth)
    }

    objectAt: function(x, y) { return editorModel ? editorModel.objectAt(x, y) : 0 }
    objectBounds: function(id) { return editorModel ? editorModel.objectBounds(id) : Qt.rect(0, 0, 0, 0) }

    onMoveObjectsRequested: function(ids, dx, dy) {
        const moved = editorModel ? editorModel.moveObjects(ids, dx, dy) : false
        if (!moved && editorModel) {
            surface.movePreviewSettled()
            editorModel.clearObjectMovePreview()
            surface.clearMovePreview()
        }
    }
    onMoveStarted: function(ids) {
        surface.movePreviewStarted()
        if (editorModel)
            editorModel.beginObjectMovePreview(ids)
    }
    onMovePreview: function(ids, dx, dy) {
        // The object crop offset is bound inside EditorCanvas to
        // SelectionOverlay.movePreviewOffset; no controller work happens per
        // pointer event.
    }
    onMoveFinished: function(ids, dx, dy) {
        // The commit is already in flight via moveObjectsRequested; keep the
        // crop until busyChanged reports completion.
    }
    onMoveCancelled: function() {
        surface.movePreviewSettled()
        if (editorModel)
            editorModel.clearObjectMovePreview()
        surface.clearMovePreview()
    }
    onRemoveObjectsRequested: function(ids) {
        if (editorModel)
            editorModel.removeObjects(ids)
    }
    onObjectDoubleClicked: function(id) {
        const info = editorModel ? editorModel.textInfo(id) : null
        if (!info || info.id === undefined)
            return
        surface.textObjectActivated(info)
    }
    onTextPointSelected: function(imageX, imageY) {
        surface.textPointChosen(imageX, imageY)
    }
    onTextCancelled: surface.toolChangeRequested("adjust")
    colorSampler: function(x, y) { return editorModel ? editorModel.colorAt(x, y) : "transparent" }
    onColorPicked: function(value) {
        surface.statusRequested(qsTranslate("Main", "Picked %1").arg(value.toString()))
        surface.foregroundColorRequested(value)
        surface.colorSampleChanged(value, samplePosition.x, samplePosition.y)
    }
    onColorSampled: function(value, imageX, imageY) {
        surface.colorSampleChanged(value, imageX, imageY)
    }
    onEyedropperCancelled: surface.toolChangeRequested("adjust")

    cropAspectRatio: panels.crop ? panels.crop.aspectRatio : 1
    onCropApplyRequested: function(area) { surface.cropApplyChosen(area) }
    onCropCancelled: surface.toolChangeRequested("adjust")

    mosaicBrushMode: panels.mosaic ? panels.mosaic.brushMode : true
    mosaicBrushDiameter: panels.mosaic ? panels.mosaic.brushDiameter : 24
    inputEnabled: !(editorModel && editorModel.busy)

    onMosaicRectangleCommitted: function(area) {
        if (!editorModel || !panels.mosaic)
            return
        if (panels.mosaic.effect === "blur")
            editorModel.blurRectangle(area, panels.mosaic.blurRadius)
        else
            editorModel.mosaicRectangle(area, panels.mosaic.blockSize)
    }
    onMosaicStrokeCommitted: function(points) {
        if (!editorModel || !panels.mosaic)
            return
        if (panels.mosaic.effect === "blur")
            editorModel.blurStroke(points, panels.mosaic.blurRadius)
        else
            editorModel.mosaicStroke(points, panels.mosaic.brushDiameter,
                                     panels.mosaic.blockSize)
    }

    recentEntries: recentFilesObject ? recentFilesObject.entries : []
    onRecentRequested: function(url) { surface.recentOpenRequested(url) }
    onOpenRequested: surface.openDialogRequested()
}
