#pragma once

#include "core/adjustments.h"

#include <QImage>

namespace NekoPic::Render::PreviewMath {

// Shader mirror, not the export path.
//
// These functions reproduce the formula in shaders/adjust_preview.frag on the
// CPU so parity tests can keep the GPU preview honest. The authoritative
// implementation stays NekoPic::Adjustments::apply: it produces committed
// preview pixels and every exported/saved image. Nothing in the app should use
// this namespace to render or save.
//
// Storage notes:
//  - The shader receives premultiplied texels from ShaderEffectSource, so it
//    unpremultiplies before evaluating the formula and premultiplies again on
//    output. The mirror operates on straight-alpha QImage data, matching the
//    CPU path's pixel domain; the premultiply round trip is Qt's texture
//    storage detail and is hidden from QImage-level comparisons.
//  - Filter presets are deliberately not mirrored. Enabling a filter forces
//    the CPU preview path (see ADR-0003), so the shader is never used then.
//  - Parameter clamping matches Adjustments::apply (exposure [-4, 4],
//    brightness/contrast/saturation [-1, 1], non-finite values become 0).

// Applies the preview formula to an RGBA8888 (straight alpha) image. The
// source is converted to RGBA8888 when needed; alpha bytes are never changed.
QImage applyRgba8(const QImage &source, const Adjustments::Parameters &parameters);

// Same formula at 16 bits per channel. Exists because the authoritative CPU
// path evaluates non-floating images in RGBA64; keeping this cheap mirror
// makes 16-bit parity coverage explicit.
QImage applyRgba64(const QImage &source, const Adjustments::Parameters &parameters);

} // namespace NekoPic::Render::PreviewMath
