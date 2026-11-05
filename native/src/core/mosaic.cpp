#include "mosaic.h"

#include <QPainter>
#include <QPainterPath>
#include <QtGui/qrgbafloat.h>

#include <algorithm>
#include <cmath>

namespace NekoPic::Mosaic {
namespace {

constexpr qint64 maxPixels = 64 * 1024 * 1024;
constexpr qsizetype maxImageBytes = 1024 * 1024 * 1024;
constexpr qsizetype maxStrokePoints = 4096;
constexpr int maxBlockSize = 512;
constexpr double maxDiameter = 4096.0;
constexpr double maxCoordinate = 1e7;
constexpr double maxRasterWork = 256.0 * 1024.0 * 1024.0;

bool canProcess(const QImage &source, int blockSize)
{
    return !source.isNull() && blockSize > 1
        && qint64(source.width()) * source.height() <= maxPixels
        && source.sizeInBytes() <= maxImageBytes;
}

QRgba64 readPixel(const QImage &image, int x, int y)
{
    if (image.format() == QImage::Format_RGBA64)
        return reinterpret_cast<const QRgba64 *>(image.constScanLine(y))[x];
    return image.pixelColor(x, y).rgba64();
}

void writePixel(QImage &image, int x, int y, QRgba64 pixel)
{
    if (image.format() == QImage::Format_RGBA64)
        reinterpret_cast<QRgba64 *>(image.scanLine(y))[x] = pixel;
    else
        image.setPixelColor(x, y, QColor::fromRgba64(pixel));
}

struct FloatingPixel {
    double red;
    double green;
    double blue;
    double alpha;
};

bool isFloatingPoint(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

bool isPremultipliedFloat(QImage::Format format)
{
    return format == QImage::Format_RGBA16FPx4_Premultiplied
        || format == QImage::Format_RGBA32FPx4_Premultiplied;
}

FloatingPixel readFloatPixel(const QImage &image, int x, int y)
{
    FloatingPixel pixel{};
    if (image.format() <= QImage::Format_RGBA16FPx4_Premultiplied) {
        const auto value = reinterpret_cast<const QRgbaFloat16 *>(image.constScanLine(y))[x];
        pixel = {value.red(), value.green(), value.blue(), value.alpha()};
    } else {
        const auto value = reinterpret_cast<const QRgbaFloat32 *>(image.constScanLine(y))[x];
        pixel = {value.red(), value.green(), value.blue(), value.alpha()};
    }
    if (isPremultipliedFloat(image.format()) && pixel.alpha > 0.0) {
        pixel.red /= pixel.alpha;
        pixel.green /= pixel.alpha;
        pixel.blue /= pixel.alpha;
    }
    return pixel;
}

void writeFloatPixel(QImage &image, int x, int y, const FloatingPixel &pixel)
{
    const auto factor = isPremultipliedFloat(image.format()) ? pixel.alpha : 1.0;
    const auto red = static_cast<float>(pixel.red * factor);
    const auto green = static_cast<float>(pixel.green * factor);
    const auto blue = static_cast<float>(pixel.blue * factor);
    if (image.format() <= QImage::Format_RGBA16FPx4_Premultiplied) {
        auto &target = reinterpret_cast<QRgbaFloat16 *>(image.scanLine(y))[x];
        target.setRed(red);
        target.setGreen(green);
        target.setBlue(blue);
    } else {
        auto &target = reinterpret_cast<QRgbaFloat32 *>(image.scanLine(y))[x];
        target.setRed(red);
        target.setGreen(green);
        target.setBlue(blue);
    }
    // Keep the stored alpha bit for bit, including float and half-float alpha.
}

QImage applyMask(const QImage &source, const QRect &roi, int blockSize, const QImage &mask = {})
{
    auto result = source.format() == QImage::Format_Indexed8
            || source.format() == QImage::Format_Mono || source.format() == QImage::Format_MonoLSB
        ? source.convertToFormat(QImage::Format_RGBA64) : source.copy();
    if (result.isNull())
        return source;

    const auto selected = [&](int x, int y) {
        return mask.isNull()
            || reinterpret_cast<const QRgb *>(mask.constScanLine(y - roi.top()))[x - roi.left()] != 0;
    };
    const auto startX = roi.left() / blockSize * blockSize;
    const auto startY = roi.top() / blockSize * blockSize;
    for (int blockY = startY; blockY <= roi.bottom(); blockY += blockSize) {
        const auto endY = std::min(blockY + blockSize, source.height());
        for (int blockX = startX; blockX <= roi.right(); blockX += blockSize) {
            const auto endX = std::min(blockX + blockSize, source.width());
            const auto writeLeft = std::max(blockX, roi.left());
            const auto writeTop = std::max(blockY, roi.top());
            const auto writeRight = std::min(endX, roi.right() + 1);
            const auto writeBottom = std::min(endY, roi.bottom() + 1);
            auto hasSelection = mask.isNull();
            for (int y = writeTop; !hasSelection && y < writeBottom; ++y)
                for (int x = writeLeft; x < writeRight; ++x)
                    if (selected(x, y)) {
                        hasSelection = true;
                        break;
                    }
            if (!hasSelection)
                continue;

            if (isFloatingPoint(source.format())) {
                FloatingPixel sum{};
                for (int y = blockY; y < endY; ++y) {
                    for (int x = blockX; x < endX; ++x) {
                        const auto pixel = readFloatPixel(source, x, y);
                        if (!std::isfinite(pixel.alpha) || pixel.alpha <= 0.0
                            || !std::isfinite(pixel.red) || !std::isfinite(pixel.green)
                            || !std::isfinite(pixel.blue))
                            continue;
                        sum.red += pixel.red * pixel.alpha;
                        sum.green += pixel.green * pixel.alpha;
                        sum.blue += pixel.blue * pixel.alpha;
                        sum.alpha += pixel.alpha;
                    }
                }
                if (sum.alpha <= 0.0)
                    continue;
                for (int y = writeTop; y < writeBottom; ++y) {
                    for (int x = writeLeft; x < writeRight; ++x) {
                        if (!selected(x, y))
                            continue;
                        const auto originalAlpha = readFloatPixel(source, x, y).alpha;
                        if (std::isfinite(originalAlpha) && originalAlpha > 0.0)
                            writeFloatPixel(result, x, y, {sum.red / sum.alpha,
                                sum.green / sum.alpha, sum.blue / sum.alpha, originalAlpha});
                    }
                }
                continue;
            }

            quint64 red = 0;
            quint64 green = 0;
            quint64 blue = 0;
            quint64 alpha = 0;
            for (int y = blockY; y < endY; ++y) {
                for (int x = blockX; x < endX; ++x) {
                    const auto pixel = readPixel(source, x, y);
                    const auto weight = quint64(pixel.alpha());
                    red += quint64(pixel.red()) * weight;
                    green += quint64(pixel.green()) * weight;
                    blue += quint64(pixel.blue()) * weight;
                    alpha += weight;
                }
            }
            if (alpha == 0)
                continue;
            const auto averageRed = static_cast<quint16>((red + alpha / 2) / alpha);
            const auto averageGreen = static_cast<quint16>((green + alpha / 2) / alpha);
            const auto averageBlue = static_cast<quint16>((blue + alpha / 2) / alpha);
            for (int y = writeTop; y < writeBottom; ++y) {
                for (int x = writeLeft; x < writeRight; ++x) {
                    if (!selected(x, y))
                        continue;
                    const auto originalAlpha = readPixel(source, x, y).alpha();
                    if (originalAlpha != 0)
                        writePixel(result, x, y, QRgba64::fromRgba64(
                            averageRed, averageGreen, averageBlue, originalAlpha));
                }
            }
        }
    }
    return result;
}

} // namespace

QImage pixelateRect(const QImage &source, const QRect &rectangle, int blockSize)
{
    if (!canProcess(source, blockSize) || !rectangle.isValid())
        return source;
    const auto roi = rectangle.intersected(source.rect());
    if (roi.isEmpty())
        return source;
    return applyMask(source, roi, std::min(blockSize, maxBlockSize));
}

QImage pixelateStroke(const QImage &source, const Stroke &stroke, int blockSize)
{
    if (!canProcess(source, blockSize) || stroke.points.isEmpty()
        || stroke.points.size() > maxStrokePoints
        || !std::isfinite(stroke.diameter) || stroke.diameter <= 0.0)
        return source;

    auto left = maxCoordinate;
    auto right = -maxCoordinate;
    auto top = maxCoordinate;
    auto bottom = -maxCoordinate;
    for (const auto &point : stroke.points) {
        if (!std::isfinite(point.x()) || !std::isfinite(point.y())
            || std::abs(point.x()) > maxCoordinate || std::abs(point.y()) > maxCoordinate)
            return source;
        left = std::min(left, point.x());
        right = std::max(right, point.x());
        top = std::min(top, point.y());
        bottom = std::max(bottom, point.y());
    }
    const auto diameter = std::min(stroke.diameter, maxDiameter);
    const auto padding = diameter / 2.0 + 1.0;
    left = std::clamp(std::floor(left - padding), 0.0, double(source.width()));
    right = std::clamp(std::ceil(right + padding), 0.0, double(source.width()));
    top = std::clamp(std::floor(top - padding), 0.0, double(source.height()));
    bottom = std::clamp(std::ceil(bottom + padding), 0.0, double(source.height()));
    const QRect roi(static_cast<int>(left), static_cast<int>(top),
                    static_cast<int>(right - left), static_cast<int>(bottom - top));
    if (roi.isEmpty())
        return source;

    // Bound overlapping raster work as well as the allocation. A tiny image can
    // otherwise still receive thousands of very large, overlapping segments.
    const auto roiArea = double(roi.width()) * roi.height();
    auto rasterWork = std::min(roiArea, diameter * diameter);
    auto hasSegment = false;
    for (qsizetype index = 1; index < stroke.points.size(); ++index) {
        const auto delta = stroke.points[index] - stroke.points[index - 1];
        if (delta.isNull())
            continue;
        hasSegment = true;
        rasterWork += std::min(roiArea, std::hypot(delta.x(), delta.y()) * diameter
            + diameter * diameter);
        if (rasterWork > maxRasterWork)
            return source;
    }

    QImage mask(roi.size(), QImage::Format_ARGB32_Premultiplied);
    if (mask.isNull())
        return source;
    mask.fill(Qt::transparent);
    {
        QPainter painter(&mask);
        painter.setRenderHint(QPainter::Antialiasing, false);
        painter.translate(-roi.left(), -roi.top());
        painter.setBrush(Qt::white);
        painter.setPen(Qt::NoPen);
        if (!hasSegment) {
            painter.drawEllipse(stroke.points.first(), diameter / 2.0, diameter / 2.0);
        } else {
            QPainterPath path(stroke.points.first());
            for (qsizetype index = 1; index < stroke.points.size(); ++index)
                path.lineTo(stroke.points[index]);
            painter.setBrush(Qt::NoBrush);
            painter.setPen(QPen(Qt::white, diameter, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
            painter.drawPath(path);
        }
    }
    return applyMask(source, roi, std::min(blockSize, maxBlockSize), mask);
}

} // namespace NekoPic::Mosaic
