#include "adjustments.h"

#include <qfloat16.h>
#include <algorithm>
#include <cmath>

namespace NekoPic::Adjustments {
namespace {

double bounded(double value, double limit)
{
    return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
}

quint16 channel(double value)
{
    return static_cast<quint16>(std::lround(std::clamp(value, 0.0, 1.0) * 65535.0));
}

struct Rgb {
    double red;
    double green;
    double blue;
};

Rgb filterTarget(Rgb color, const QString &preset)
{
    const auto [red, green, blue] = color;
    const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    if (preset == "mono") {
        return {luminance, luminance, luminance};
    } else if (preset == "vivid") {
        color.red = std::clamp((red - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.green = std::clamp((green - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.blue = std::clamp((blue - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.red = luminance + (color.red - luminance) * 1.25;
        color.green = luminance + (color.green - luminance) * 1.25;
        color.blue = luminance + (color.blue - luminance) * 1.25;
    } else if (preset == "warm" || preset == "vintage") {
        const double amount = preset == "warm" ? 0.12 : 0.08;
        color.red = std::min(1.0, red + amount * (1.0 - red));
        color.blue = std::max(0.0, blue - amount * blue);
        if (preset == "vintage") {
            color.red = (color.red - 0.5) * 0.82 + 0.54;
            color.green = (green - 0.5) * 0.82 + 0.52;
            color.blue = (color.blue - 0.5) * 0.82 + 0.48;
        }
    } else if (preset == "cool") {
        color.red = std::max(0.0, red - 0.12 * red);
        color.blue = std::min(1.0, blue + 0.12 * (1.0 - blue));
    }
    return color;
}

bool isFloating(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

QImage applyFloating(const QImage &source, double exposure, double brightness,
                     double contrast, double saturation, const QString &preset, double intensity)
{
    auto result = source.copy();
    if (result.isNull()) return {};
    const bool half = source.depth() == 64;
    const bool premultiplied = source.format() == QImage::Format_RGBA16FPx4_Premultiplied
        || source.format() == QImage::Format_RGBA32FPx4_Premultiplied;
    const double exposureFactor = std::exp2(exposure);
    const bool toneChanged = exposure != 0 || brightness != 0 || contrast != 0;
    for (int y = 0; y < result.height(); ++y) {
        auto *floats = half ? nullptr : reinterpret_cast<float *>(result.scanLine(y));
        auto *halves = half ? reinterpret_cast<qfloat16 *>(result.scanLine(y)) : nullptr;
        for (int x = 0; x < result.width(); ++x) {
            const auto offset = x * 4;
            const double alpha = half ? float(halves[offset + 3]) : floats[offset + 3];
            if (premultiplied && alpha <= 0) continue;
            const double scale = premultiplied ? alpha : 1.0;
            Rgb original{(half ? float(halves[offset]) : floats[offset]) / scale,
                         (half ? float(halves[offset + 1]) : floats[offset + 1]) / scale,
                         (half ? float(halves[offset + 2]) : floats[offset + 2]) / scale};
            auto color = original;
            if (toneChanged) {
                const auto tone = [=](double value) {
                    return (value * exposureFactor - 0.5) * (1.0 + contrast) + 0.5 + brightness;
                };
                color = {tone(color.red), tone(color.green), tone(color.blue)};
            }
            if (saturation != 0) {
                const double luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue;
                color = {luminance + (color.red - luminance) * (1.0 + saturation),
                         luminance + (color.green - luminance) * (1.0 + saturation),
                         luminance + (color.blue - luminance) * (1.0 + saturation)};
            }
            if (intensity > 0) {
                const auto target = filterTarget(color, preset);
                const auto blend = [=](double value, double filtered) {
                    if (value == filtered) return value;
                    // Vivid can overshoot during saturation. Match the integer
                    // path by blending first, then clipping its SDR output.
                    if (preset == "vivid")
                        return std::clamp(value + (filtered - value) * intensity, 0.0, 1.0);
                    // Other presets have SDR targets; untouched channels retain HDR values.
                    return value + (std::clamp(filtered, 0.0, 1.0) - value) * intensity;
                };
                color = {blend(color.red, target.red), blend(color.green, target.green),
                         blend(color.blue, target.blue)};
            }
            const double before[]{original.red, original.green, original.blue};
            const double after[]{color.red, color.green, color.blue};
            for (int c = 0; c < 3; ++c) {
                if (after[c] == before[c]) continue;
                if (half) halves[offset + c] = qfloat16(float(after[c] * scale));
                else floats[offset + c] = float(after[c] * scale);
            }
            // Alpha is never rewritten, including half/float payload bits.
        }
    }
    return result;
}

} // namespace

QImage apply(const QImage &source, const Parameters &parameters)
{
    if (source.isNull())
        return {};

    const double exposure = bounded(parameters.exposure, 4.0);
    const double brightness = bounded(parameters.brightness, 1.0);
    const double contrast = bounded(parameters.contrast, 1.0);
    const double saturation = bounded(parameters.saturation, 1.0);
    const double intensity = std::isfinite(parameters.filterIntensity)
        ? std::clamp(parameters.filterIntensity, 0.0, 1.0) : 0.0;
    const auto preset = parameters.filterPreset;
    if (exposure == 0.0 && brightness == 0.0 && contrast == 0.0 && saturation == 0.0
        && (preset.isEmpty() || preset == "none" || intensity == 0.0))
        return source;

    if (isFloating(source.format()))
        return applyFloating(source, exposure, brightness, contrast, saturation, preset, intensity);

    QImage result = source.convertToFormat(QImage::Format_RGBA64);
    if (result.isNull())
        return {};

    const double exposureFactor = std::exp2(exposure);
    const double contrastFactor = 1.0 + contrast;
    const double saturationFactor = 1.0 + saturation;
    for (int y = 0; y < result.height(); ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(result.scanLine(y));
        for (int x = 0; x < result.width(); ++x) {
            const QRgba64 pixel = pixels[x];
            auto tone = [=](quint16 value) {
                return (value / 65535.0 * exposureFactor - 0.5) * contrastFactor
                    + 0.5 + brightness;
            };
            const double red = tone(pixel.red());
            const double green = tone(pixel.green());
            const double blue = tone(pixel.blue());
            const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
            pixels[x] = QRgba64::fromRgba64(
                channel(luminance + (red - luminance) * saturationFactor),
                channel(luminance + (green - luminance) * saturationFactor),
                channel(luminance + (blue - luminance) * saturationFactor), pixel.alpha());
        }
    }
    if (!preset.isEmpty() && intensity > 0.0) {
        for (int y = 0; y < result.height(); ++y) {
            auto *pixels = reinterpret_cast<QRgba64 *>(result.scanLine(y));
            for (int x = 0; x < result.width(); ++x) {
                const QRgba64 pixel = pixels[x];
                double red = pixel.red() / 65535.0;
                double green = pixel.green() / 65535.0;
                double blue = pixel.blue() / 65535.0;
                const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
                double targetRed = red;
                double targetGreen = green;
                double targetBlue = blue;
                if (preset == "mono") {
                    targetRed = targetGreen = targetBlue = luminance;
                } else if (preset == "vivid") {
                    targetRed = std::clamp((red - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetGreen = std::clamp((green - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetBlue = std::clamp((blue - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetRed = luminance + (targetRed - luminance) * 1.25;
                    targetGreen = luminance + (targetGreen - luminance) * 1.25;
                    targetBlue = luminance + (targetBlue - luminance) * 1.25;
                } else if (preset == "warm" || preset == "vintage") {
                    const double amount = preset == "warm" ? 0.12 : 0.08;
                    targetRed = std::min(1.0, red + amount * (1.0 - red));
                    targetBlue = std::max(0.0, blue - amount * blue);
                    if (preset == "vintage") {
                        targetRed = (targetRed - 0.5) * 0.82 + 0.54;
                        targetGreen = (green - 0.5) * 0.82 + 0.52;
                        targetBlue = (targetBlue - 0.5) * 0.82 + 0.48;
                    }
                } else if (preset == "cool") {
                    targetRed = std::max(0.0, red - 0.12 * red);
                    targetBlue = std::min(1.0, blue + 0.12 * (1.0 - blue));
                }
                red += (targetRed - red) * intensity;
                green += (targetGreen - green) * intensity;
                blue += (targetBlue - blue) * intensity;
                pixels[x] = QRgba64::fromRgba64(channel(red), channel(green), channel(blue), pixel.alpha());
            }
        }
    }
    return result;
}

} // namespace NekoPic::Adjustments
