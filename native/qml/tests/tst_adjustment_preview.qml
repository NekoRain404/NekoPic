import QtQuick
import QtTest
import "../effects"

// Tests for the GPU adjustment preview wrapper. The shader itself is exercised
// when the scene graph backend can compile RHI shaders; the pure software
// backend must keep showing the unmodified source.
//
// fixtures/adjust_preview.frag.qsb is a test fixture produced from
// native/shaders/adjust_preview.frag with (run from native/qml/tests):
//   qsb --glsl 100,120,150,330,440 --hlsl 50 --msl 12 \
//       -o fixtures/adjust_preview.frag.qsb ../../shaders/adjust_preview.frag
// Regenerate it whenever the shader changes. The app itself uses the copy
// baked into its resources by qt_add_shaders.
TestCase {
    id: testCase
    name: "AdjustmentPreview"
    when: windowShown
    visible: true
    width: 240
    height: 200

    readonly property url validShader: Qt.resolvedUrl("fixtures/adjust_preview.frag.qsb")
    readonly property bool gpuBackend:
        GraphicsInfo.api !== GraphicsInfo.Unknown
        && GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.OpenVG
        && GraphicsInfo.api !== GraphicsInfo.Null
        && GraphicsInfo.api !== GraphicsInfo.NullRhi

    Item {
        id: scene
        width: 160
        height: 120

        Rectangle {
            id: sourceRect
            objectName: "sourceRect"
            width: 80
            height: 60
            color: "#4080a0"
        }

        AdjustmentPreview {
            id: preview
            objectName: "preview"
            x: 80
            y: 0
            width: 80
            height: 60
            sourceItem: sourceRect
            shaderSource: testCase.validShader
        }

        // Separate wrapper with a deliberately broken shader. Keeping it away
        // from `preview` matters: a ShaderEffect that has latched Error does
        // not reliably return to Compiled when the URL is restored.
        Rectangle {
            id: brokenSource
            objectName: "brokenSource"
            x: 0
            y: 60
            width: 20
            height: 20
            color: "#808080"
        }

        AdjustmentPreview {
            id: brokenPreview
            objectName: "brokenPreview"
            x: 0
            y: 60
            width: 20
            height: 20
            sourceItem: brokenSource
            shaderSource: Qt.resolvedUrl("fixtures/does-not-exist.frag.qsb")
            active: true
        }
    }

    function init() {
        preview.active = false
        preview.exposure = 0
        preview.brightness = 0
        preview.contrast = 0
        preview.saturation = 0
        preview.highlights = 0
        preview.shadows = 0
        preview.whites = 0
        preview.blacks = 0
        preview.temperature = 0
        preview.tint = 0
        preview.vibrance = 0
        preview.shaderSource = testCase.validShader
        wait(0)
    }

    function findEffect() {
        return findChild(preview, "adjustmentPreviewEffect")
    }

    function findTexture() {
        return findChild(preview, "adjustmentPreviewSource")
    }

    function test_inactiveKeepsSourceVisible() {
        failOnWarning(/.?/)
        const effect = findEffect()
        const texture = findTexture()
        verify(effect !== null, "ShaderEffect child is missing")
        verify(texture !== null, "ShaderEffectSource child is missing")
        compare(preview.sourceItem, sourceRect)
        compare(preview.active, false)
        compare(preview.previewing, false)
        compare(effect.visible, false)
        compare(texture.hideSource, false)
        verify(sourceRect.visible, "inactive preview must not hide the source")
    }

    function test_uniformsRemainBound() {
        failOnWarning(/.?/)
        const effect = findEffect()
        preview.exposure = 1.25
        preview.brightness = -0.4
        preview.contrast = 0.75
        preview.saturation = -0.5
        preview.highlights = 0.35
        preview.shadows = -0.25
        preview.whites = 0.15
        preview.blacks = -0.05
        preview.temperature = 0.45
        preview.tint = -0.35
        preview.vibrance = 0.65
        compare(effect.exposure, 1.25)
        compare(effect.brightness, -0.4)
        compare(effect.contrast, 0.75)
        compare(effect.saturation, -0.5)
        compare(effect.highlights, 0.35)
        compare(effect.shadows, -0.25)
        compare(effect.whites, 0.15)
        compare(effect.blacks, -0.05)
        compare(effect.temperature, 0.45)
        compare(effect.tint, -0.35)
        compare(effect.vibrance, 0.65)
        compare(effect.source, findTexture())
        // Uniform updates never disturb the source while inactive.
        verify(sourceRect.visible)
    }

    function test_activeHidesSourceWhenGpuAvailable() {
        if (!testCase.gpuBackend) {
            skip("scene graph backend cannot run RHI shaders; the wrapper must stay inactive")
            return
        }
        failOnWarning(/.?/)
        const effect = findEffect()
        const texture = findTexture()

        preview.active = true
        tryCompare(preview, "previewing", true, 3000)
        tryCompare(texture, "hideSource", true, 1000)
        compare(effect.visible, true)
        // hideSource hides the item through Qt's private effect-reference
        // bookkeeping (QQuickItemPrivate::refFromEffectItem), so Item.visible
        // intentionally stays true; hideSource is the rendering gate to check.

        preview.active = false
        tryCompare(preview, "previewing", false, 1000)
        compare(effect.visible, false)
        compare(texture.hideSource, false)
    }

    function test_invalidShaderFallsBackToSource() {
        // The broken shader is loaded during component creation, so its warning
        // (if any) is emitted before this function runs.
        const effect = findChild(brokenPreview, "adjustmentPreviewEffect")
        const texture = findChild(brokenPreview, "adjustmentPreviewSource")
        if (testCase.gpuBackend)
            tryCompare(brokenPreview, "shaderAvailable", false, 3000)
        compare(brokenPreview.previewing, false, "a broken shader must not enter preview mode")
        compare(effect.visible, false)
        compare(texture.hideSource, false)
        verify(brokenSource.visible, "a broken shader must keep the source visible")
        // The healthy wrapper is not affected by its neighbour's failure.
        compare(preview.previewing, false)
        verify(sourceRect.visible)
    }

    function test_softwareBackendNeverHidesSource() {
        if (testCase.gpuBackend) {
            skip("GPU backend available; software fallback covered elsewhere")
            return
        }
        failOnWarning(/.?/)
        preview.active = true
        wait(0)
        compare(preview.shaderBackendSupported, false)
        compare(preview.previewing, false)
        compare(findEffect().visible, false)
        compare(findTexture().hideSource, false)
        verify(sourceRect.visible)
        preview.active = false
    }

    // A shader-vs-CPU check is only meaningful when the platform can read
    // rendered pixels back. Probe grabImage() first: some headless/offscreen
    // configurations return blank frames (observed when grabbing a parent
    // scene item), so skip with the reason instead of reporting a false
    // failure.
    function test_shaderMatchesCpuWhenReadbackWorks() {
        if (!testCase.gpuBackend) {
            skip("RHI shaders are unavailable on this scene graph backend")
            return
        }
        failOnWarning(/.?/)
        preview.active = false
        wait(50)
        const base = grabImage(sourceRect)
        const baseOk = Math.abs(base.red(10, 10) - 0x40) <= 4
            && Math.abs(base.green(10, 10) - 0x80) <= 4
            && Math.abs(base.blue(10, 10) - 0xa0) <= 4
        if (!baseOk) {
            skip("grabImage returned a blank frame (offscreen platform): GPU pixel readback is unreliable here")
            return
        }

        preview.exposure = 0.5
        preview.saturation = 0.4
        preview.active = true
        tryCompare(preview, "previewing", true, 3000)
        wait(50)
        const rendered = grabImage(preview)
        const expected = cpuAdjusted(0x40 / 255, 0x80 / 255, 0xa0 / 255, 0.5, 0, 0, 0.4)
        const x = 40
        const y = 30
        verify(Math.abs(rendered.red(x, y) - expected[0]) <= 4,
               "red " + rendered.red(x, y) + " vs CPU " + expected[0])
        verify(Math.abs(rendered.green(x, y) - expected[1]) <= 4,
               "green " + rendered.green(x, y) + " vs CPU " + expected[1])
        verify(Math.abs(rendered.blue(x, y) - expected[2]) <= 4,
               "blue " + rendered.blue(x, y) + " vs CPU " + expected[2])
        preview.active = false
    }

    // Same readback probe as above, but exercising the extended-basic stages
    // (white balance, tonal masks, vibrance). GPU float ordering differs from
    // the CPU's double math, so this check allows 4/255 per channel; a formula
    // mismatch moves channels by far more on this saturated test colour.
    function test_extendedShaderMatchesCpuWhenReadbackWorks() {
        if (!testCase.gpuBackend) {
            skip("RHI shaders are unavailable on this scene graph backend")
            return
        }
        failOnWarning(/.?/)
        preview.active = false
        wait(50)
        const base = grabImage(sourceRect)
        const baseOk = Math.abs(base.red(10, 10) - 0x40) <= 4
            && Math.abs(base.green(10, 10) - 0x80) <= 4
            && Math.abs(base.blue(10, 10) - 0xa0) <= 4
        if (!baseOk) {
            skip("grabImage returned a blank frame (offscreen platform): GPU pixel readback is unreliable here")
            return
        }

        preview.exposure = 0.3
        preview.highlights = 0.3
        preview.shadows = -0.2
        preview.temperature = 0.5
        preview.tint = -0.2
        preview.vibrance = 0.6
        preview.active = true
        tryCompare(preview, "previewing", true, 3000)
        wait(50)
        const rendered = grabImage(preview)
        const expected = cpuAdjustedExtended(0x40 / 255, 0x80 / 255, 0xa0 / 255,
                                              preview.exposure, 0, 0, 0,
                                              preview.highlights, preview.shadows,
                                              0, 0, preview.temperature,
                                              preview.tint, preview.vibrance)
        const x = 40
        const y = 30
        verify(Math.abs(rendered.red(x, y) - expected[0]) <= 4,
               "red " + rendered.red(x, y) + " vs CPU " + expected[0])
        verify(Math.abs(rendered.green(x, y) - expected[1]) <= 4,
               "green " + rendered.green(x, y) + " vs CPU " + expected[1])
        verify(Math.abs(rendered.blue(x, y) - expected[2]) <= 4,
               "blue " + rendered.blue(x, y) + " vs CPU " + expected[2])
        preview.active = false
    }

    // Straight-alpha CPU mirror of adjust_preview.frag, used by the visual
    // check above. Inputs and outputs are 0..1 / 0..255 respectively.
    function cpuAdjusted(red, green, blue, exposure, brightness, contrast, saturation) {
        const exposureFactor = Math.pow(2, exposure)
        const contrastFactor = 1 + contrast
        const saturationFactor = 1 + saturation
        const tone = function(value) {
            return (value * exposureFactor - 0.5) * contrastFactor + 0.5 + brightness
        }
        let r = tone(red)
        let g = tone(green)
        let b = tone(blue)
        const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        r = luminance + (r - luminance) * saturationFactor
        g = luminance + (g - luminance) * saturationFactor
        b = luminance + (b - luminance) * saturationFactor
        const channel = function(value) {
            return Math.round(Math.min(1, Math.max(0, value)) * 255)
        }
        return [channel(r), channel(g), channel(b)]
    }

    // Extended-branch mirror: white balance, tonal masks, saturation and
    // vibrance in the same order/clamps as colorpipeline.cpp applyExtended().
    function cpuAdjustedExtended(red, green, blue, exposure, brightness, contrast,
                                 saturation, highlights, shadows, whites, blacks,
                                 temperature, tint, vibrance) {
        const clamp01 = function(value) { return Math.min(1, Math.max(0, value)) }
        const luma = function(r, g, b) { return 0.2126 * r + 0.7152 * g + 0.0722 * b }
        const smoothstep = function(edge0, edge1, value) {
            const t = clamp01((value - edge0) / (edge1 - edge0))
            return t * t * (3 - 2 * t)
        }
        let r = red
        let g = green
        let b = blue
        if (temperature !== 0 || tint !== 0) {
            r *= 1 + 0.30 * temperature + 0.10 * tint
            g *= 1 - 0.20 * tint
            b *= 1 - 0.30 * temperature + 0.10 * tint
        }
        if (exposure !== 0 || brightness !== 0 || contrast !== 0) {
            const exposureFactor = Math.pow(2, exposure)
            const contrastFactor = 1 + contrast
            const tone = function(value) {
                return (value * exposureFactor - 0.5) * contrastFactor + 0.5 + brightness
            }
            r = tone(r)
            g = tone(g)
            b = tone(b)
        }
        r = clamp01(r); g = clamp01(g); b = clamp01(b)
        if (highlights !== 0 || shadows !== 0 || whites !== 0 || blacks !== 0) {
            const level = luma(r, g, b)
            const shadowMask = 1 - smoothstep(0, 0.55, level)
            const highlightMask = smoothstep(0.45, 1, level)
            const blackMask = 1 - smoothstep(0, 0.25, level)
            const whiteMask = smoothstep(0.75, 1, level)
            const delta = 0.5 * (shadows * shadowMask + highlights * highlightMask
                                 + blacks * blackMask + whites * whiteMask)
            r = clamp01(r + delta); g = clamp01(g + delta); b = clamp01(b + delta)
        }
        if (saturation !== 0) {
            const level = luma(r, g, b)
            const factor = 1 + saturation
            r = level + (r - level) * factor
            g = level + (g - level) * factor
            b = level + (b - level) * factor
        }
        if (vibrance !== 0) {
            const maximum = Math.max(r, g, b)
            const minimum = Math.min(r, g, b)
            const chroma = maximum - minimum
            const currentSaturation = maximum > 1e-9 ? chroma / maximum : 0
            const factor = 1 + vibrance * (1 - currentSaturation) * 0.8
            const level = luma(r, g, b)
            r = level + (r - level) * factor
            g = level + (g - level) * factor
            b = level + (b - level) * factor
        }
        const channel = function(value) {
            return Math.round(clamp01(value) * 255)
        }
        return [channel(r), channel(g), channel(b)]
    }
}
