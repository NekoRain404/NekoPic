#version 440

// Interactive basic-adjustment preview for NekoPic.
//
// This shader mirrors NekoPic::Adjustments::apply
// (native/src/core/adjustments.cpp):
//
//   tone(v)  = (v * exp2(exposure) - 0.5) * (1 + contrast) + 0.5 + brightness
//   lum      = dot(rgb, vec3(0.2126, 0.7152, 0.0722))
//   result   = lum + (rgb - lum) * (1 + saturation)
//
// The CPU implementation remains authoritative: it produces the committed
// preview pixels and every exported/saved image. This shader is only used for
// the transient, GPU-drawn preview while the user drags a slider. Filter
// presets are intentionally not handled here; enabling a filter forces the
// CPU preview path.
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
};

void main()
{
    vec4 texel = texture(source, qt_TexCoord0);

    float alpha = texel.a;
    vec3 color = alpha > 0.0 ? texel.rgb / alpha : vec3(0.0);

    color = (color * exp2(exposure) - 0.5) * (1.0 + contrast) + 0.5 + brightness;
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = clamp(luminance + (color - luminance) * (1.0 + saturation), 0.0, 1.0);

    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
