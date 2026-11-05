#include "previewmath.h"

#include <algorithm>
#include <cmath>

namespace NekoPic::Render::PreviewMath {
namespace {

// Keep the parameter domain identical to NekoPic::Adjustments::apply.
double bounded(double value, double limit)
{
    return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
}

double clamp01(double value)
{
    return std::clamp(value, 0.0, 1.0);
}

double luma(double red, double green, double blue)
{
    // Same weights and evaluation order as the extended pipeline's luma().
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

double smoothstep(double edge0, double edge1, double value)
{
    if (edge0 == edge1)
        return value < edge0 ? 0.0 : 1.0;
    const double t = clamp01((value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

struct Coeffs {
    double exposureFactor = 1.0;
    double contrastFactor = 1.0;
    double brightness = 0.0;
    double saturationFactor = 1.0;

    double highlights = 0.0;
    double shadows = 0.0;
    double whites = 0.0;
    double blacks = 0.0;
    double temperature = 0.0;
    double tint = 0.0;
    double vibrance = 0.0;

    // Matches Internal::hasExtendedParameters() for the keys the shader
    // implements. Any active extended key switches the CPU pipeline (and this
    // mirror) from the legacy basic formula to applyExtended()'s ordering.
    bool extended = false;
    bool toneActive = false;
    bool saturationActive = false;

    explicit Coeffs(const Adjustments::Parameters &parameters)
        : exposureFactor(std::exp2(bounded(parameters.exposure, 4.0)))
        , contrastFactor(1.0 + bounded(parameters.contrast, 1.0))
        , brightness(bounded(parameters.brightness, 1.0))
        , saturationFactor(1.0 + bounded(parameters.saturation, 1.0))
        , highlights(bounded(parameters.highlights, 1.0))
        , shadows(bounded(parameters.shadows, 1.0))
        , whites(bounded(parameters.whites, 1.0))
        , blacks(bounded(parameters.blacks, 1.0))
        , temperature(bounded(parameters.temperature, 1.0))
        , tint(bounded(parameters.tint, 1.0))
        , vibrance(bounded(parameters.vibrance, 1.0))
        , extended(bounded(parameters.highlights, 1.0) != 0.0
                   || bounded(parameters.shadows, 1.0) != 0.0
                   || bounded(parameters.whites, 1.0) != 0.0
                   || bounded(parameters.blacks, 1.0) != 0.0
                   || bounded(parameters.temperature, 1.0) != 0.0
                   || bounded(parameters.tint, 1.0) != 0.0
                   || bounded(parameters.vibrance, 1.0) != 0.0)
        , toneActive(bounded(parameters.exposure, 4.0) != 0.0
                     || bounded(parameters.brightness, 1.0) != 0.0
                     || bounded(parameters.contrast, 1.0) != 0.0)
        , saturationActive(bounded(parameters.saturation, 1.0) != 0.0)
    {
    }

    // shaders/adjust_preview.frag: (c * exp2(e) - 0.5) * (1 + contrast) + 0.5 + brightness
    double tone(double value) const
    {
        return (value * exposureFactor - 0.5) * contrastFactor + 0.5 + brightness;
    }

    // shaders/adjust_preview.frag: lum + (c - lum) * (1 + saturation)
    void saturate(double &red, double &green, double &blue) const
    {
        const double level = luma(red, green, blue);
        red = level + (red - level) * saturationFactor;
        green = level + (green - level) * saturationFactor;
        blue = level + (blue - level) * saturationFactor;
    }

    // Mirrors the fused stages 1-3 of the extended pipeline's applyExtended()
    // (white balance, tone, tonal masks, saturation, vibrance) for the keys
    // the shader supports. Intermediates are not quantized, matching the CPU
    // pass; the caller rounds once at the end.
    void adjust(double &red, double &green, double &blue) const
    {
        if (!extended) {
            red = tone(red);
            green = tone(green);
            blue = tone(blue);
            saturate(red, green, blue);
            return;
        }

        // 1. White balance.
        if (temperature != 0.0 || tint != 0.0) {
            const double gainRed = 1.0 + 0.30 * temperature + 0.10 * tint;
            const double gainGreen = 1.0 - 0.20 * tint;
            const double gainBlue = 1.0 - 0.30 * temperature + 0.10 * tint;
            red *= gainRed;
            green *= gainGreen;
            blue *= gainBlue;
        }

        // 2. Tonal.
        if (toneActive) {
            red = tone(red);
            green = tone(green);
            blue = tone(blue);
        }
        red = clamp01(red);
        green = clamp01(green);
        blue = clamp01(blue);

        if (highlights != 0.0 || shadows != 0.0 || whites != 0.0
            || blacks != 0.0) {
            const double level = luma(red, green, blue);
            const double shadowMask = 1.0 - smoothstep(0.0, 0.55, level);
            const double highlightMask = smoothstep(0.45, 1.0, level);
            const double blackMask = 1.0 - smoothstep(0.0, 0.25, level);
            const double whiteMask = smoothstep(0.75, 1.0, level);
            const double delta = 0.5
                * (shadows * shadowMask + highlights * highlightMask
                   + blacks * blackMask + whites * whiteMask);
            red = clamp01(red + delta);
            green = clamp01(green + delta);
            blue = clamp01(blue + delta);
        }

        // 3. Saturation, then vibrance.
        if (saturationActive)
            saturate(red, green, blue);
        if (vibrance != 0.0) {
            const double maximum = std::max({red, green, blue});
            const double minimum = std::min({red, green, blue});
            const double chroma = maximum - minimum;
            const double currentSaturation =
                maximum > 1e-9 ? chroma / maximum : 0.0;
            const double factor =
                1.0 + vibrance * (1.0 - currentSaturation) * 0.8;
            const double level = luma(red, green, blue);
            red = level + (red - level) * factor;
            green = level + (green - level) * factor;
            blue = level + (blue - level) * factor;
        }
        red = clamp01(red);
        green = clamp01(green);
        blue = clamp01(blue);
    }
};

// Matches Adjustments::channel(): clamp to SDR and round half away from zero.
uchar channel8(double value)
{
    return static_cast<uchar>(std::lround(std::clamp(value, 0.0, 1.0) * 255.0));
}

quint16 channel16(double value)
{
    return static_cast<quint16>(std::lround(std::clamp(value, 0.0, 1.0) * 65535.0));
}

} // namespace

QImage applyRgba8(const QImage &source, const Adjustments::Parameters &parameters)
{
    if (source.isNull())
        return {};

    const QImage image = source.format() == QImage::Format_RGBA8888
        ? source : source.convertToFormat(QImage::Format_RGBA8888);
    if (image.isNull())
        return {};

    QImage result = image.copy();
    const Coeffs coeffs(parameters);
    for (int y = 0; y < result.height(); ++y) {
        uchar *pixels = result.scanLine(y);
        for (int x = 0; x < result.width(); ++x) {
            uchar *pixel = pixels + x * 4;
            double red = pixel[0] / 255.0;
            double green = pixel[1] / 255.0;
            double blue = pixel[2] / 255.0;
            coeffs.adjust(red, green, blue);
            pixel[0] = channel8(red);
            pixel[1] = channel8(green);
            pixel[2] = channel8(blue);
            // pixel[3] (alpha) is intentionally untouched.
        }
    }
    return result;
}

QImage applyRgba64(const QImage &source, const Adjustments::Parameters &parameters)
{
    if (source.isNull())
        return {};

    const QImage image = source.format() == QImage::Format_RGBA64
        ? source : source.convertToFormat(QImage::Format_RGBA64);
    if (image.isNull())
        return {};

    QImage result = image.copy();
    const Coeffs coeffs(parameters);
    for (int y = 0; y < result.height(); ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(result.scanLine(y));
        for (int x = 0; x < result.width(); ++x) {
            const QRgba64 pixel = pixels[x];
            double red = pixel.red() / 65535.0;
            double green = pixel.green() / 65535.0;
            double blue = pixel.blue() / 65535.0;
            coeffs.adjust(red, green, blue);
            pixels[x] = QRgba64::fromRgba64(channel16(red), channel16(green),
                                            channel16(blue), pixel.alpha());
        }
    }
    return result;
}

} // namespace NekoPic::Render::PreviewMath
