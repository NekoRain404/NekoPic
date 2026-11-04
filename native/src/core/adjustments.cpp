#include "adjustments.h"

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
        && (preset.isEmpty() || intensity == 0.0))
        return source;

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
    if (source.format() != QImage::Format_RGBA64) {
        result = result.convertToFormat(source.format());
        result.setColorSpace(source.colorSpace());
    }
    return result;
}

} // namespace NekoPic::Adjustments
