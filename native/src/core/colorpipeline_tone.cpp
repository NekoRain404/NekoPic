#include "colorpipeline_internal.h"

namespace NekoPic::Adjustments::Internal {

// ---------------------------------------------------------------------------
// Stages 1-4: white balance, tonal, saturation + vibrance, HSL.
//
// This is the first half of the fused per-pixel pass. It deliberately leaves
// the colour unclamped after HSL, matching the original loop: the curve stage
// (or dispatch when curves are neutral) applies the next clamp.
// ---------------------------------------------------------------------------

void applyToneStages(Rgb& color, const StageConfig& config)
{
    const Parameters& p = config.parameters;
    double red = color.red;
    double green = color.green;
    double blue = color.blue;

    // 1. White balance.
    if (config.whiteBalanceActive) {
        red *= config.gainRed;
        green *= config.gainGreen;
        blue *= config.gainBlue;
    }

    // 2. Tonal.
    if (config.toneActive) {
        const auto tone = [&](double value) {
            return (value * config.exposureFactor - 0.5) * config.contrastFactor + 0.5 +
                   p.brightness;
        };
        red = tone(red);
        green = tone(green);
        blue = tone(blue);
    }
    red = clamp01(red);
    green = clamp01(green);
    blue = clamp01(blue);
    if (config.tonalAdjustActive) {
        const double level = luma(red, green, blue);
        const double shadowMask = 1.0 - smoothstep(0.0, 0.55, level);
        const double highlightMask = smoothstep(0.45, 1.0, level);
        const double blackMask = 1.0 - smoothstep(0.0, 0.25, level);
        const double whiteMask = smoothstep(0.75, 1.0, level);
        const double delta = 0.5 * (p.shadows * shadowMask + p.highlights * highlightMask +
                                    p.blacks * blackMask + p.whites * whiteMask);
        red += delta;
        green += delta;
        blue += delta;
        red = clamp01(red);
        green = clamp01(green);
        blue = clamp01(blue);
    }

    // 3. Saturation and vibrance.
    if (config.saturationActive) {
        const double level = luma(red, green, blue);
        const double factor = 1.0 + p.saturation;
        red = level + (red - level) * factor;
        green = level + (green - level) * factor;
        blue = level + (blue - level) * factor;
    }
    if (config.vibranceActive) {
        const double maximum = std::max({red, green, blue});
        const double minimum = std::min({red, green, blue});
        const double chroma = maximum - minimum;
        const double currentSaturation = maximum > 1e-9 ? chroma / maximum : 0.0;
        const double factor = 1.0 + p.vibrance * (1.0 - currentSaturation) * 0.8;
        const double level = luma(red, green, blue);
        red = level + (red - level) * factor;
        green = level + (green - level) * factor;
        blue = level + (blue - level) * factor;
    }
    red = clamp01(red);
    green = clamp01(green);
    blue = clamp01(blue);

    // 4. HSL targeted adjustments.
    if (config.anyHsl) {
        const double maximum = std::max({red, green, blue});
        const double minimum = std::min({red, green, blue});
        if (maximum - minimum > 1e-6 && maximum > 1e-9) {
            const double hue = hueDegrees(red, green, blue, maximum, minimum);
            double hueShift = 0.0;
            double saturationMultiplier = 1.0;
            double luminanceShift = 0.0;
            for (int channel = 0; channel < HslChannelCount; ++channel) {
                if (!config.hslActive[channel])
                    continue;
                const double weight = hueWeight(hue, kHueCenters[channel]);
                if (weight <= 0.0)
                    continue;
                hueShift += weight * p.hsl[channel].hue * 30.0;
                saturationMultiplier *= 1.0 + weight * p.hsl[channel].saturation;
                luminanceShift += weight * p.hsl[channel].luminance * 0.5;
            }
            const double saturation = clamp01((maximum - minimum) / maximum * saturationMultiplier);
            rgbFromHsv(hue + hueShift, saturation, maximum, red, green, blue);
            if (luminanceShift != 0.0) {
                red = clamp01(red + luminanceShift);
                green = clamp01(green + luminanceShift);
                blue = clamp01(blue + luminanceShift);
            }
        }
    }

    color.red = red;
    color.green = green;
    color.blue = blue;
}

} // namespace NekoPic::Adjustments::Internal
