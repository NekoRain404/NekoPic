import QtQuick

// GPU-rendered interactive preview for the basic adjustments.
//
// Place this item over `sourceItem` with matching geometry (for EditorCanvas,
// the picture item) and drive `active` while a slider is dragged. The wrapper
// only affects what is drawn: the CPU implementation in core/adjustments.cpp
// stays authoritative for the committed preview and for export/save.
//
// Integration contract (see docs/adr/0003-gpu-preview.md):
//  - Bind `active` to !RenderCapabilities.softwareFallback && sliderPressed
//    && no filter preset is active. Filters live in the CPU path only.
//  - `sourceItem` must be the unadjusted base image, not the CPU-adjusted one.
//  - Keep this item's geometry equal to sourceItem's; it does not reposition
//    the source item.
//
// While active, ShaderEffectSource.hideSource hides the source item and the
// shader draws the adjusted texture in its place. While inactive (or if the
// shader fails to load) the shader item is hidden and the source item renders
// normally, so the image is never drawn twice.
Item {
    id: root

    property Item sourceItem: null
    property bool active: false

    property real exposure: 0.0
    property real brightness: 0.0
    property real contrast: 0.0
    property real saturation: 0.0

    // Overridable for tests and for builds that relocate the compiled shader.
    // The default path matches qt_add_shaders(PREFIX "/shaders") in
    // native/CMakeLists.txt.
    property url shaderSource: "qrc:/shaders/adjust_preview.frag.qsb"

    // Render children of sourceItem too. Off by default: when sourceItem is
    // the picture, its children are crop/mosaic overlays and must not be
    // baked into the adjusted preview.
    property bool recursiveSource: false

    // The software scene graph cannot run ShaderEffect at all; in that case
    // the status stays Uncompiled forever, so this check is the safety net that
    // keeps the source visible. The integrator should still gate `active` on
    // RenderCapabilities.softwareFallback, which is the authoritative probe.
    readonly property bool shaderBackendSupported:
        GraphicsInfo.api !== GraphicsInfo.Unknown
        && GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.OpenVG
        && GraphicsInfo.api !== GraphicsInfo.Null
        && GraphicsInfo.api !== GraphicsInfo.NullRhi

    // ShaderEffect.Ready is spelled Compiled/Uncompiled/Error in Qt 6. Treat
    // only a real load/compile failure as unavailable; Uncompiled also covers
    // the first frame before the shader is prepared.
    readonly property bool shaderAvailable:
        shaderBackendSupported && effect.status !== ShaderEffect.Error
    readonly property bool shaderReady: effect.status === ShaderEffect.Compiled
    readonly property bool previewing: active && shaderAvailable && sourceItem !== null

    ShaderEffectSource {
        id: effectSource
        objectName: "adjustmentPreviewSource"
        // Deliberately unsized and unanchored: this item is only a texture
        // provider. Giving it geometry would draw the source a second time.
        sourceItem: root.sourceItem
        recursive: root.recursiveSource
        live: root.previewing
        hideSource: root.previewing
        smooth: true
    }

    ShaderEffect {
        id: effect
        objectName: "adjustmentPreviewEffect"
        anchors.fill: parent
        visible: root.previewing
        property var source: effectSource
        property real exposure: root.exposure
        property real brightness: root.brightness
        property real contrast: root.contrast
        property real saturation: root.saturation
        fragmentShader: root.shaderSource
    }
}
