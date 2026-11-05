#pragma once

// Internal seams of the extended colour pipeline.
//
// This header is private to native/src/core: it is not installed, is never
// included by QML-facing code, and must not become part of the stable
// colorpipeline.h contract. The registry, the per-image stage configuration
// and the pure numeric helpers are shared by the split translation units.
//
// Pipeline order (documented contract for the panel and for future GPU parity):
//   1. white balance            temperature/tint channel gains
//   2. tonal                    exposure, brightness, contrast, highlights,
//                               shadows, whites, blacks
//   3. saturation + vibrance
//   4. HSL                      8 hue bands with smooth cosine weights
//   5. tone curves              RGB composite, then R, G and B
//   6. colour grading           shadow/midtone/highlight masks
//   7. detail                   texture, clarity, dehaze, sharpen, luminance
//                               and colour noise reduction
//   8. effects                  vignette (+feather), grain, fade
//   9. existing filter preset   unchanged preset formulas and intensity blend
//
// Approximations:
//  - Extended work happens in a normalized, straight-alpha RGBA64 buffer.
//    Floating-point sources therefore lose HDR/negative excursions when an
//    extended control is active; the output is converted back to the source
//    format and alpha is copied from the source verbatim. Basic-only
//    parameters keep the original floating path and its HDR precision.
//  - Luminance noise reduction and clarity use a separable box blur restricted
//    to the image (edge-clamped). Colour noise reduction uses a 3x3 box
//    average of the chroma-carrying RGB neighbourhood.
//  - Grain is a deterministic per-pixel hash, not a stateful RNG, so parallel
//    rows produce identical output.
//  - Intermediate stages clamp to SDR after each cross-channel stage.

#include "adjustments.h"

#include <QImage>
#include <QString>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <numbers>

namespace NekoPic::Adjustments::Internal {

// Filter preset identifiers shared by dispatch and the effects pass.
enum class Preset
{
    None,
    Fresh,
    Vivid,
    Warm,
    Cool,
    Film,
    Faded,
    Vintage,
    Sunset,
    Soft,
    Cream,
    Mono,
    Silver,
    Unknown,
};

struct Rgb
{
    double red;
    double green;
    double blue;
};

// Per-apply stage state. It is built once from sanitized parameters so the
// fused pixel loops never re-evaluate activity flags per pixel.
struct StageConfig
{
    Parameters parameters;

    bool whiteBalanceActive = false;
    double gainRed = 1.0;
    double gainGreen = 1.0;
    double gainBlue = 1.0;

    bool toneActive = false;
    double exposureFactor = 1.0;
    double contrastFactor = 1.0;
    bool tonalAdjustActive = false;
    bool saturationActive = false;
    bool vibranceActive = false;

    std::array<bool, HslChannelCount> hslActive{};
    bool anyHsl = false;
    bool anyTone = false;

    std::array<bool, CurveChannelCount> curveActive{};
    bool anyCurve = false;

    std::array<bool, GradeZoneCount> gradeZoneActive{};
    bool anyGrade = false;
    double gradePivot = 0.5;
    double gradeInv = 0.0;

    bool textureActive = false;
    bool clarityActive = false;
    bool dehazeActive = false;
    bool sharpenActive = false;
    bool luminanceNoiseActive = false;
    bool colorNoiseActive = false;
    bool needSmallBlur = false;
    bool needLargeBlur = false;
    bool anyDetail = false;

    bool vignetteActive = false;
    bool grainActive = false;
    bool fadeActive = false;
    bool filterActive = false;
    bool anyEffect = false;
    Preset preset = Preset::None;
    double vignetteInner = 0.0;
};

// One shared half-width for all eight HSL bands. The red/orange/yellow centres
// are 30 degrees apart, so adjacent bands overlap smoothly; distant bands do
// not contribute at all.
inline constexpr double kHueCenters[HslChannelCount]{0.0,   30.0,  60.0,  120.0,
                                                     180.0, 240.0, 280.0, 320.0};

// ---------------------------------------------------------------------------
// Numeric helpers
//
// These stay inline so every stage translation unit compiles the same
// arithmetic as the original fused loop; the pipeline's pixel output depends
// on this exact evaluation order.
// ---------------------------------------------------------------------------

inline double bounded(double value, double limit)
{
    return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
}

inline double clamp01(double value) { return std::clamp(value, 0.0, 1.0); }

inline double luma(double red, double green, double blue)
{
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

inline double smoothstep(double edge0, double edge1, double value)
{
    if (edge0 == edge1)
        return value < edge0 ? 0.0 : 1.0;
    const double t = clamp01((value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

inline double normalizeHue(double hue)
{
    double result = std::fmod(hue, 360.0);
    if (result < 0.0)
        result += 360.0;
    return result;
}

inline double hueWeight(double hue, double center)
{
    constexpr double kHalfWidth = 45.0;
    double distance = std::abs(hue - center);
    distance = std::min(distance, 360.0 - distance);
    if (distance >= kHalfWidth)
        return 0.0;
    return 0.5 * (1.0 + std::cos(std::numbers::pi * distance / kHalfWidth));
}

inline double hueDegrees(double red, double green, double blue, double maximum, double minimum)
{
    const double chroma = maximum - minimum;
    if (chroma <= 1e-12)
        return 0.0;
    double hue;
    if (maximum == red)
        hue = 60.0 * std::fmod((green - blue) / chroma, 6.0);
    else if (maximum == green)
        hue = 60.0 * ((blue - red) / chroma + 2.0);
    else
        hue = 60.0 * ((red - green) / chroma + 4.0);
    if (hue < 0.0)
        hue += 360.0;
    return hue;
}

inline void rgbFromHsv(double hue, double saturation, double value, double& red, double& green,
                       double& blue)
{
    hue = normalizeHue(hue);
    const double chroma = value * saturation;
    const double hp = hue / 60.0;
    const double second = chroma * (1.0 - std::abs(std::fmod(hp, 2.0) - 1.0));
    double r = 0.0;
    double g = 0.0;
    double b = 0.0;
    if (hp < 1.0) {
        r = chroma;
        g = second;
    } else if (hp < 2.0) {
        r = second;
        g = chroma;
    } else if (hp < 3.0) {
        g = chroma;
        b = second;
    } else if (hp < 4.0) {
        g = second;
        b = chroma;
    } else if (hp < 5.0) {
        r = second;
        b = chroma;
    } else {
        r = chroma;
        b = second;
    }
    const double base = value - chroma;
    red = r + base;
    green = g + base;
    blue = b + base;
}

inline quint16 toChannel(double value)
{
    const double scaled = clamp01(value) * 65535.0;
    const double base = std::floor(scaled);
    return static_cast<quint16>(base + (scaled - base >= 0.5 ? 1.0 : 0.0));
}

inline bool isLinearCurve(const ToneCurve& curve)
{
    for (int point = 0; point < CurvePointCount; ++point) {
        if (!std::isfinite(curve.points[point]))
            return false;
        if (std::abs(curve.points[point] - point * 0.25) > 1e-9)
            return false;
    }
    return true;
}

inline double evaluateCurve(const ToneCurve& curve, double value)
{
    const double x = clamp01(value);
    const double scaled = x * 4.0;
    int segment = static_cast<int>(scaled);
    if (segment > CurvePointCount - 2)
        segment = CurvePointCount - 2;
    const double fraction = scaled - segment;
    const double output =
        curve.points[segment] + (curve.points[segment + 1] - curve.points[segment]) * fraction;
    return clamp01(output);
}

inline void clampColor(Rgb& color)
{
    color.red = clamp01(color.red);
    color.green = clamp01(color.green);
    color.blue = clamp01(color.blue);
}

// ---------------------------------------------------------------------------
// Shared declarations
// ---------------------------------------------------------------------------

Parameters sanitized(const Parameters& input);

Preset parsePreset(const QString& preset);
bool isActivePreset(Preset preset);

// Stage 1-4: white balance, tonal, saturation + vibrance and HSL. Values are
// left unclamped after the HSL stage, exactly like the original fused pass.
void applyToneStages(Rgb& color, const StageConfig& config);

// Stage 5: RGB composite curve, then the per-channel curves, followed by the
// unconditional post-curve clamp.
void applyCurveStages(Rgb& color, const StageConfig& config);

// Stage 6: shadow/midtone/highlight colour grading, followed by the
// unconditional post-grade clamp.
void applyGradeStage(Rgb& color, const StageConfig& config);

// Stage 7: neighbourhood detail work (texture, clarity, dehaze, sharpen and
// luminance noise reduction). Colour noise reduction is a separate pass.
void applyDetailStages(QImage& work, const StageConfig& config, int workers);
void applyColorNoiseStage(QImage& work, const StageConfig& config, int workers);

// Stages 8-9: vignette, grain, fade and the existing filter preset.
void applyEffectStages(QImage& work, const StageConfig& config, int workers);

} // namespace NekoPic::Adjustments::Internal
