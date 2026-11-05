#include "blur.h"

#include <QColorSpace>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QRgba64>
#include <QStringList>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

namespace NekoPic::Blur {
namespace {

constexpr int maxStrokePoints = 4096;
constexpr double maxCoordinate = 1e7;
constexpr int boxPasses = 3;

struct Layout
{
    bool premultiplied = false;
    bool sixteenBit = false;
};

bool layoutFor(QImage::Format format, Layout& layout)
{
    switch (format) {
    case QImage::Format_RGB32:
    case QImage::Format_ARGB32:
    case QImage::Format_RGBA8888:
        layout = {false, false};
        return true;
    case QImage::Format_ARGB32_Premultiplied:
    case QImage::Format_RGBA8888_Premultiplied:
        layout = {true, false};
        return true;
    case QImage::Format_RGBA64:
        layout = {false, true};
        return true;
    case QImage::Format_RGBA64_Premultiplied:
        layout = {true, true};
        return true;
    default:
        return false;
    }
}

int channelMax(const Layout& layout) { return layout.sixteenBit ? 65535 : 255; }

struct Pixel
{
    quint16 red = 0;
    quint16 green = 0;
    quint16 blue = 0;
    quint16 alpha = 0;
};

Pixel readPixel(const QImage& image, QImage::Format format, int x, int y)
{
    const uchar* line = image.constScanLine(y);
    switch (format) {
    case QImage::Format_RGB32:
    case QImage::Format_ARGB32:
    case QImage::Format_ARGB32_Premultiplied: {
        const QRgb value = reinterpret_cast<const QRgb*>(line)[x];
        const int alpha = format == QImage::Format_RGB32 ? 255 : qAlpha(value);
        return {static_cast<quint16>(qRed(value)), static_cast<quint16>(qGreen(value)),
                static_cast<quint16>(qBlue(value)), static_cast<quint16>(alpha)};
    }
    case QImage::Format_RGBA8888:
    case QImage::Format_RGBA8888_Premultiplied: {
        const uchar* pixel = line + x * 4;
        return {static_cast<quint16>(pixel[0]), static_cast<quint16>(pixel[1]),
                static_cast<quint16>(pixel[2]), static_cast<quint16>(pixel[3])};
    }
    case QImage::Format_RGBA64:
    case QImage::Format_RGBA64_Premultiplied: {
        const QRgba64 value = reinterpret_cast<const QRgba64*>(line)[x];
        return {value.red(), value.green(), value.blue(), value.alpha()};
    }
    default:
        return {};
    }
}

void writePixel(QImage& image, QImage::Format format, int x, int y, const Pixel& pixel)
{
    uchar* line = image.scanLine(y);
    switch (format) {
    case QImage::Format_RGB32: {
        reinterpret_cast<QRgb*>(line)[x] = qRgba(pixel.red, pixel.green, pixel.blue, 255);
        break;
    }
    case QImage::Format_ARGB32:
    case QImage::Format_ARGB32_Premultiplied: {
        reinterpret_cast<QRgb*>(line)[x] = qRgba(pixel.red, pixel.green, pixel.blue, pixel.alpha);
        break;
    }
    case QImage::Format_RGBA8888:
    case QImage::Format_RGBA8888_Premultiplied: {
        uchar* target = line + x * 4;
        target[0] = static_cast<uchar>(pixel.red);
        target[1] = static_cast<uchar>(pixel.green);
        target[2] = static_cast<uchar>(pixel.blue);
        target[3] = static_cast<uchar>(pixel.alpha);
        break;
    }
    case QImage::Format_RGBA64:
    case QImage::Format_RGBA64_Premultiplied: {
        reinterpret_cast<QRgba64*>(line)[x] =
            QRgba64::fromRgba64(pixel.red, pixel.green, pixel.blue, pixel.alpha);
        break;
    }
    default:
        break;
    }
}

quint16 premultiplyChannel(quint16 colour, quint16 alpha, int maxValue)
{
    return static_cast<quint16>((quint64(colour) * alpha + quint64(maxValue) / 2) /
                                quint64(maxValue));
}

Pixel premultiply(Pixel pixel, int maxValue)
{
    if (pixel.alpha == 0)
        return {};
    return {premultiplyChannel(pixel.red, pixel.alpha, maxValue),
            premultiplyChannel(pixel.green, pixel.alpha, maxValue),
            premultiplyChannel(pixel.blue, pixel.alpha, maxValue), pixel.alpha};
}

Pixel unpremultiply(Pixel pixel, int maxValue)
{
    if (pixel.alpha == 0)
        return {0, 0, 0, 0};
    const auto divide = [&pixel, maxValue](quint16 colour) {
        const quint64 value = (quint64(colour) * quint64(maxValue) + pixel.alpha / 2) / pixel.alpha;
        return static_cast<quint16>(std::min<quint64>(value, quint64(maxValue)));
    };
    return {divide(pixel.red), divide(pixel.green), divide(pixel.blue), pixel.alpha};
}

Pixel blendPremultiplied(const Pixel& blurred, const Pixel& source, int coverage)
{
    const quint32 inverse = 255U - quint32(coverage);
    const auto mix = [coverage, inverse](quint16 blurredChannel, quint16 sourceChannel) {
        const quint32 value =
            quint32(blurredChannel) * quint32(coverage) + quint32(sourceChannel) * inverse;
        return static_cast<quint16>((value + 127U) / 255U);
    };
    return {mix(blurred.red, source.red), mix(blurred.green, source.green),
            mix(blurred.blue, source.blue), mix(blurred.alpha, source.alpha)};
}

// Box half-width chosen so three passes reach approximately `radius`.
int boxHalfWidth(int radius, const QImage& image)
{
    const qint64 requested = std::max<qint64>(1, (qint64(radius) + 2) / 3);
    const qint64 cap = std::max<qint64>(std::max(image.width(), image.height()), 1);
    return static_cast<int>(std::min(requested, cap));
}

int kernelMargin(int halfWidth, const QImage& image)
{
    const qint64 margin = qint64(boxPasses) * halfWidth;
    const qint64 cap = std::max<qint64>(std::max(image.width(), image.height()), 1);
    return static_cast<int>(std::min(margin, cap));
}

// Edge-clamped box blur. `dst` and `src` must not alias.
void boxBlurHorizontal(const std::vector<quint16>& src, std::vector<quint16>& dst, int width,
                       int height, int halfWidth)
{
    const int window = 2 * halfWidth + 1;
    for (int y = 0; y < height; ++y) {
        const auto row = std::size_t(y) * std::size_t(width);
        quint64 sum = 0;
        for (int offset = -halfWidth; offset <= halfWidth; ++offset)
            sum += src[row + std::size_t(std::clamp(offset, 0, width - 1))];
        for (int x = 0; x < width; ++x) {
            dst[row + std::size_t(x)] =
                static_cast<quint16>((sum + quint64(window) / 2) / quint64(window));
            sum -= src[row + std::size_t(std::clamp(x - halfWidth, 0, width - 1))];
            sum += src[row + std::size_t(std::clamp(x + halfWidth + 1, 0, width - 1))];
        }
    }
}

void boxBlurVertical(const std::vector<quint16>& src, std::vector<quint16>& dst, int width,
                     int height, int halfWidth)
{
    const int window = 2 * halfWidth + 1;
    for (int x = 0; x < width; ++x) {
        quint64 sum = 0;
        for (int offset = -halfWidth; offset <= halfWidth; ++offset)
            sum += src[std::size_t(std::clamp(offset, 0, height - 1)) * width + x];
        for (int y = 0; y < height; ++y) {
            dst[std::size_t(y) * width + x] =
                static_cast<quint16>((sum + quint64(window) / 2) / quint64(window));
            sum -= src[std::size_t(std::clamp(y - halfWidth, 0, height - 1)) * width + x];
            sum += src[std::size_t(std::clamp(y + halfWidth + 1, 0, height - 1)) * width + x];
        }
    }
}

QImage blurRegion(const QImage& source, const QRect& roi, const QImage& mask, int radius,
                  const Layout& layout)
{
    const auto format = source.format();
    const int maxValue = channelMax(layout);
    const bool straight = !layout.premultiplied;
    const int halfWidth = boxHalfWidth(radius, source);
    const int margin = kernelMargin(halfWidth, source);
    const QRect expanded =
        roi.adjusted(-margin, -margin, margin, margin).intersected(source.rect());
    const int expandedWidth = expanded.width();
    const int expandedHeight = expanded.height();
    const auto count = std::size_t(expandedWidth) * std::size_t(expandedHeight);

    std::array<std::vector<quint16>, 4> channels;
    for (auto& channel : channels)
        channel.resize(count);

    for (int y = 0; y < expandedHeight; ++y) {
        for (int x = 0; x < expandedWidth; ++x) {
            auto pixel = readPixel(source, format, expanded.left() + x, expanded.top() + y);
            if (straight)
                pixel = premultiply(pixel, maxValue);
            const auto index = std::size_t(y) * std::size_t(expandedWidth) + std::size_t(x);
            channels[0][index] = pixel.red;
            channels[1][index] = pixel.green;
            channels[2][index] = pixel.blue;
            channels[3][index] = pixel.alpha;
        }
    }

    std::vector<quint16> scratch(count);
    for (int pass = 0; pass < boxPasses; ++pass) {
        for (auto& channel : channels) {
            boxBlurHorizontal(channel, scratch, expandedWidth, expandedHeight, halfWidth);
            boxBlurVertical(scratch, channel, expandedWidth, expandedHeight, halfWidth);
        }
    }

    auto result = source.copy();
    result.setColorSpace(source.colorSpace());
    result.setDevicePixelRatio(source.devicePixelRatio());
    result.setDotsPerMeterX(source.dotsPerMeterX());
    result.setDotsPerMeterY(source.dotsPerMeterY());
    for (const auto& key : source.textKeys())
        result.setText(key, source.text(key));

    for (int y = roi.top(); y <= roi.bottom(); ++y) {
        const uchar* maskLine = mask.isNull() ? nullptr : mask.constScanLine(y - roi.top());
        for (int x = roi.left(); x <= roi.right(); ++x) {
            const int coverage =
                maskLine ? qAlpha(reinterpret_cast<const QRgb*>(maskLine)[x - roi.left()]) : 255;
            if (coverage == 0)
                continue;

            const auto index = std::size_t(y - expanded.top()) * std::size_t(expandedWidth) +
                               std::size_t(x - expanded.left());
            Pixel pixel{channels[0][index], channels[1][index], channels[2][index],
                        channels[3][index]};
            if (coverage < 255) {
                const auto original = readPixel(source, format, x, y);
                pixel = blendPremultiplied(
                    pixel, straight ? premultiply(original, maxValue) : original, coverage);
            }
            if (straight)
                pixel = unpremultiply(pixel, maxValue);
            writePixel(result, format, x, y, pixel);
        }
    }
    return result;
}

bool validateStroke(const QList<QPointF>& points)
{
    if (points.isEmpty() || points.size() > maxStrokePoints)
        return false;
    for (const auto& point : points) {
        if (!std::isfinite(point.x()) || !std::isfinite(point.y()) ||
            std::abs(point.x()) > maxCoordinate || std::abs(point.y()) > maxCoordinate)
            return false;
    }
    return true;
}

} // namespace

bool withinLimits(const QImage& source, int radius, const Limits& limits, QString* error)
{
    const auto reject = [error](const QString& message) {
        if (error)
            *error = message;
        return false;
    };
    if (error)
        error->clear();

    if (source.isNull())
        return reject(QStringLiteral("The image is empty."));

    Layout layout;
    if (!layoutFor(source.format(), layout)) {
        return reject(
            QStringLiteral("Unsupported image format %1. Blur supports RGB32, ARGB32, RGBA8888 and "
                           "RGBA64 images (including premultiplied variants).")
                .arg(static_cast<int>(source.format())));
    }
    if (radius < 1)
        return reject(QStringLiteral("Blur radius must be at least 1 pixel (got %1).").arg(radius));
    if (limits.maxRadius < 1)
        return reject(QStringLiteral("The configured maximum blur radius is invalid."));
    if (radius > limits.maxRadius) {
        return reject(QStringLiteral("Blur radius %1 exceeds the maximum of %2 pixels.")
                          .arg(radius)
                          .arg(limits.maxRadius));
    }
    if (limits.maxPixels < 1)
        return reject(QStringLiteral("The configured maximum pixel count is invalid."));
    const qint64 pixels = qint64(source.width()) * qint64(source.height());
    if (pixels > limits.maxPixels) {
        return reject(QStringLiteral("Image has %1 pixels, which exceeds the maximum of %2.")
                          .arg(pixels)
                          .arg(limits.maxPixels));
    }
    return true;
}

QImage applyRect(const QImage& source, const QRect& area, int radius, const Limits& limits)
{
    if (!withinLimits(source, radius, limits) || !area.isValid())
        return source;
    const auto roi = area.intersected(source.rect());
    if (roi.isEmpty())
        return source;
    Layout layout;
    layoutFor(source.format(), layout);
    return blurRegion(source, roi, QImage(), radius, layout);
}

QImage applyStroke(const QImage& source, const QList<QPointF>& points, int radius,
                   const Limits& limits)
{
    if (!withinLimits(source, radius, limits) || !validateStroke(points))
        return source;

    double left = std::numeric_limits<double>::max();
    double right = std::numeric_limits<double>::lowest();
    double top = std::numeric_limits<double>::max();
    double bottom = std::numeric_limits<double>::lowest();
    for (const auto& point : points) {
        left = std::min(left, point.x());
        right = std::max(right, point.x());
        top = std::min(top, point.y());
        bottom = std::max(bottom, point.y());
    }

    const double padding = double(radius) + 1.0;
    const double clippedLeft = std::clamp(std::floor(left - padding), 0.0, double(source.width()));
    const double clippedRight = std::clamp(std::ceil(right + padding), 0.0, double(source.width()));
    const double clippedTop = std::clamp(std::floor(top - padding), 0.0, double(source.height()));
    const double clippedBottom =
        std::clamp(std::ceil(bottom + padding), 0.0, double(source.height()));
    const QRect roi(static_cast<int>(clippedLeft), static_cast<int>(clippedTop),
                    static_cast<int>(clippedRight - clippedLeft),
                    static_cast<int>(clippedBottom - clippedTop));
    if (roi.isEmpty())
        return source;

    QImage mask(roi.size(), QImage::Format_ARGB32_Premultiplied);
    if (mask.isNull())
        return source;
    mask.fill(Qt::transparent);
    bool hasSegment = false;
    for (qsizetype index = 1; index < points.size(); ++index) {
        if (!(points[index] - points[index - 1]).isNull()) {
            hasSegment = true;
            break;
        }
    }
    {
        QPainter painter(&mask);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.translate(-roi.left(), -roi.top());
        painter.setBrush(Qt::white);
        painter.setPen(Qt::NoPen);
        if (!hasSegment) {
            painter.drawEllipse(points.first(), double(radius), double(radius));
        } else {
            QPainterPath path(points.first());
            for (qsizetype index = 1; index < points.size(); ++index)
                path.lineTo(points[index]);
            painter.setBrush(Qt::NoBrush);
            painter.setPen(
                QPen(Qt::white, 2.0 * double(radius), Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
            painter.drawPath(path);
        }
    }

    Layout layout;
    layoutFor(source.format(), layout);
    return blurRegion(source, roi, mask, radius, layout);
}

} // namespace NekoPic::Blur
