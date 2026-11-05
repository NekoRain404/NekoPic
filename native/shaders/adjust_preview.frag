#version 440

// Interactive basic-adjustment preview for NekoPic.
//
// This shader mirrors the fused per-pixel stages of
// NekoPic::Adjustments::applyExtended (native/src/core/colorpipeline.cpp),
// including the basic controls, and falls back to the legacy basic-only
// formula when no extended key is active:
//
//   white balance  rgb *= (1 + 0.30 T + 0.10 t,
//                          1 - 0.20 t,
//                          1 - 0.30 T + 0.10 t)
//   tone(v)        = (v * exp2(exposure) - 0.5) * (1 + contrast) + 0.5
//                    + brightness
//   clamp01
//   tonal          level = dot(rgb, vec3(0.2126, 0.7152, 0.0722))
//                  delta = 0.5 * (shadows   * (1 - smoothstep(0, 0.55, level))
//                               + highlights * smoothstep(0.45, 1, level)
//                               + blacks    * (1 - smoothstep(0, 0.25, level))
//                               + whites    * smoothstep(0.75, 1, level))
//                  rgb += delta; clamp01
//   saturation     lum + (rgb - lum) * (1 + saturation)
//   vibrance       saturation' = chroma / max; factor = 1 + vibrance *
//                  (1 - saturation') * 0.8; rgb = lum + (rgb - lum) * factor
//   clamp01
//
// The CPU implementation remains authoritative: it produces the committed
// preview pixels and every exported/saved image. This shader is only used for
// the transient, GPU-drawn preview while the user drags a slider that
// isGpuPreviewKey() accepts. Curves, HSL, colour grading, detail, effects and
// filter presets are intentionally not handled here; they force the CPU path.
//
// ShaderEffectSource textures are premultiplied, so unpremultiply first and
// premultiply again before writing. qt_Opacity is part of the uniform block so
// item opacity behaves like any other Qt Quick item.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float exposure;
    float brightness;
    float contrast;
    float saturation;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float temperature;
    float tint;
    float vibrance;
};

float luma(vec3 color)
{
    // Same weights and evaluation order as colorpipeline.cpp's luma().
    return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;
}

void main()
{
    vec4 texel = texture(source, qt_TexCoord0);

    float alpha = texel.a;
    vec3 color = alpha > 0.0 ? texel.rgb / alpha : vec3(0.0);

    // True exactly when applyExtended() would run instead of the legacy basic
    // path. Basic-only drags keep the original formula byte-for-byte.
    bool extended = highlights != 0.0 || shadows != 0.0 || whites != 0.0
        || blacks != 0.0 || temperature != 0.0 || tint != 0.0 || vibrance != 0.0;

    if (extended) {
        // 1. White balance: temperature/tint channel gains.
        if (temperature != 0.0 || tint != 0.0) {
            vec3 gains = vec3(1.0 + 0.30 * temperature + 0.10 * tint,
                              1.0 - 0.20 * tint,
                              1.0 - 0.30 * temperature + 0.10 * tint);
            color *= gains;
        }

        // 2. Tonal: exposure/brightness/contrast, then the tonal masks.
        if (exposure != 0.0 || brightness != 0.0 || contrast != 0.0) {
            color = (color * exp2(exposure) - 0.5) * (1.0 + contrast) + 0.5
                + brightness;
        }
        color = clamp(color, 0.0, 1.0);

        if (highlights != 0.0 || shadows != 0.0 || whites != 0.0
            || blacks != 0.0) {
            float level = luma(color);
            float shadowMask = 1.0 - smoothstep(0.0, 0.55, level);
            float highlightMask = smoothstep(0.45, 1.0, level);
            float blackMask = 1.0 - smoothstep(0.0, 0.25, level);
            float whiteMask = smoothstep(0.75, 1.0, level);
            float delta = 0.5
                * (shadows * shadowMask + highlights * highlightMask
                   + blacks * blackMask + whites * whiteMask);
            color = clamp(color + vec3(delta), 0.0, 1.0);
        }

        // 3. Saturation and vibrance. Saturation runs first, then vibrance
        // reads the resulting HSV saturation, exactly like the CPU pipeline.
        if (saturation != 0.0) {
            float level = luma(color);
            color = vec3(level) + (color - vec3(level)) * (1.0 + saturation);
        }
        if (vibrance != 0.0) {
            float maximum = max(max(color.r, color.g), color.b);
            float minimum = min(min(color.r, color.g), color.b);
            float chroma = maximum - minimum;
            float currentSaturation = maximum > 1e-9 ? chroma / maximum : 0.0;
            float factor = 1.0 + vibrance * (1.0 - currentSaturation) * 0.8;
            float level = luma(color);
            color = vec3(level) + (color - vec3(level)) * factor;
        }
        color = clamp(color, 0.0, 1.0);
    } else {
        // Legacy basic-only formula (no intermediate clamps), matching
        // Adjustments::apply's optimised integer/floating path.
        color = (color * exp2(exposure) - 0.5) * (1.0 + contrast) + 0.5
            + brightness;
        float level = luma(color);
        color = clamp(vec3(level) + (color - vec3(level)) * (1.0 + saturation),
                      0.0, 1.0);
    }

    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
