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

struct Coeffs {
    double exposureFactor = 1.0;
    double contrastFactor = 1.0;
    double brightness = 0.0;
    double saturationFactor = 1.0;

    explicit Coeffs(const Adjustments::Parameters &parameters)
        : exposureFactor(std::exp2(bounded(parameters.exposure, 4.0)))
        , contrastFactor(1.0 + bounded(parameters.contrast, 1.0))
        , brightness(bounded(parameters.brightness, 1.0))
        , saturationFactor(1.0 + bounded(parameters.saturation, 1.0))
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
        const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
        red = luminance + (red - luminance) * saturationFactor;
        green = luminance + (green - luminance) * saturationFactor;
        blue = luminance + (blue - luminance) * saturationFactor;
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
            double red = coeffs.tone(pixel[0] / 255.0);
            double green = coeffs.tone(pixel[1] / 255.0);
            double blue = coeffs.tone(pixel[2] / 255.0);
            coeffs.saturate(red, green, blue);
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
            double red = coeffs.tone(pixel.red() / 65535.0);
            double green = coeffs.tone(pixel.green() / 65535.0);
            double blue = coeffs.tone(pixel.blue() / 65535.0);
            coeffs.saturate(red, green, blue);
            pixels[x] = QRgba64::fromRgba64(channel16(red), channel16(green),
                                            channel16(blue), pixel.alpha());
        }
    }
    return result;
}

} // namespace NekoPic::Render::PreviewMath
