#include "mosaic.h"

#include <QColorSpace>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

using namespace NekoPic::Mosaic;

namespace {

// Verbatim copy of the pre-optimization generic integer path. It intentionally
// uses QImage::pixelColor/setPixelColor so the direct 8-bit codecs are compared
// against Qt's own conversions, not against a second copy of the fast maths.
QImage genericReference(const QImage &source, const QRect &roi, int blockSize,
                        const QImage &mask = {})
{
    auto result = source.copy();
    const auto selected = [&](int x, int y) {
        return mask.isNull()
            || reinterpret_cast<const QRgb *>(mask.constScanLine(y - roi.top()))[x - roi.left()] != 0;
    };
    const auto readPixel = [&](int x, int y) {
        return source.pixelColor(x, y).rgba64();
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

            quint64 red = 0;
            quint64 green = 0;
            quint64 blue = 0;
            quint64 alpha = 0;
            for (int y = blockY; y < endY; ++y) {
                for (int x = blockX; x < endX; ++x) {
                    const auto pixel = readPixel(x, y);
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
                    const auto originalAlpha = readPixel(x, y).alpha();
                    if (originalAlpha != 0)
                        result.setPixelColor(x, y, QColor::fromRgba64(
                            averageRed, averageGreen, averageBlue, originalAlpha));
                }
            }
        }
    }
    return result;
}

// Recreates the stroke mask exactly as production does, then applies the
// generic reference over it. Used only for small, valid test strokes.
QImage strokeReference(const QImage &source, const Stroke &stroke, int blockSize)
{
    auto left = 1e7;
    auto right = -1e7;
    auto top = 1e7;
    auto bottom = -1e7;
    for (const auto &point : stroke.points) {
        left = std::min(left, point.x());
        right = std::max(right, point.x());
        top = std::min(top, point.y());
        bottom = std::max(bottom, point.y());
    }
    const auto padding = stroke.diameter / 2.0 + 1.0;
    left = std::clamp(std::floor(left - padding), 0.0, double(source.width()));
    right = std::clamp(std::ceil(right + padding), 0.0, double(source.width()));
    top = std::clamp(std::floor(top - padding), 0.0, double(source.height()));
    bottom = std::clamp(std::ceil(bottom + padding), 0.0, double(source.height()));
    const QRect roi(static_cast<int>(left), static_cast<int>(top),
                    static_cast<int>(right - left), static_cast<int>(bottom - top));

    auto hasSegment = false;
    for (qsizetype index = 1; index < stroke.points.size(); ++index)
        if (!(stroke.points[index] - stroke.points[index - 1]).isNull())
            hasSegment = true;

    QImage mask(roi.size(), QImage::Format_ARGB32_Premultiplied);
    mask.fill(Qt::transparent);
    {
        QPainter painter(&mask);
        painter.setRenderHint(QPainter::Antialiasing, false);
        painter.translate(-roi.left(), -roi.top());
        painter.setBrush(Qt::white);
        painter.setPen(Qt::NoPen);
        if (!hasSegment) {
            // A lone dab (or repeated identical points) is a filled ellipse.
            painter.drawEllipse(stroke.points.first(), stroke.diameter / 2.0,
                                stroke.diameter / 2.0);
        } else {
            painter.setBrush(Qt::NoBrush);
            painter.setPen(QPen(Qt::white, stroke.diameter, Qt::SolidLine, Qt::RoundCap,
                                Qt::RoundJoin));
            QPainterPath path(stroke.points.first());
            for (qsizetype index = 1; index < stroke.points.size(); ++index)
                path.lineTo(stroke.points[index]);
            painter.drawPath(path);
        }
    }
    return genericReference(source, roi, blockSize, mask);
}

QImage patternedImage(QImage::Format format, int width = 23, int height = 17)
{
    QImage image(width, height, format);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            // Transparent and partially transparent samples, plus opaque ones.
            const int alpha = (x * 7 + y * 5) % 5 == 0 ? 0
                : (x * 13 + y * 3) % 256;
            image.setPixelColor(x, y,
                QColor((x * 31 + y * 17) % 256, (x * 11 + y * 29) % 256,
                    (x * 19 + y * 23) % 256, alpha));
        }
    }
    return image;
}

const QList<QImage::Format> rgba8Formats{
    QImage::Format_RGBA8888,
    QImage::Format_RGBA8888_Premultiplied,
    QImage::Format_RGBX8888,
    QImage::Format_ARGB32,
    QImage::Format_ARGB32_Premultiplied,
    QImage::Format_RGB32,
};

} // namespace

class MosaicTest : public QObject {
    Q_OBJECT
private slots:
    void rectangleUsesWholeOriginAnchoredBlocksAndOnlyChangesSelection();
    void rectangleClipsAtImageEdges();
    void averagesIgnoreTransparentColorAndPreserveAlpha();
    void preservesHighDepthColorSpaceAndMetadata();
    void strokeConnectsSamplesAndLeavesOutsideUntouched();
    void singlePointStrokeHasRoundFootprint();
    void rejectsInvalidAndExcessiveInputs();
    void clampsOversizedBlockAndDiameter();
    void repeatedSamplesStillPaintOneDab();
    void clipsLongOffCanvasSegments();
    void weightsPartiallyTransparentPixels();
    void rejectsExcessiveStrokeRasterWork();
    void preservesFloatingPointPrecisionAndAlpha();
    void rgba8DirectMatchesGenericReference();
    void rgba8StrokeDirectMatchesGenericReference();
};

void MosaicTest::rectangleUsesWholeOriginAnchoredBlocksAndOnlyChangesSelection()
{
    QImage image(4, 2, QImage::Format_RGBA64);
    constexpr quint16 values[2][4]{{1000, 3000, 9000, 11000}, {5000, 7000, 13000, 15000}};
    for (int y = 0; y < 2; ++y)
        for (int x = 0; x < 4; ++x)
            image.setPixelColor(x, y, QColor::fromRgba64(values[y][x], 0, 0, 65535));
    const auto result = pixelateRect(image, QRect(1, 0, 2, 1), 2);
    QCOMPARE(result.pixelColor(1, 0).rgba64().red(), quint16(4000));
    QCOMPARE(result.pixelColor(2, 0).rgba64().red(), quint16(12000));
    for (int y = 0; y < 2; ++y)
        for (int x = 0; x < 4; ++x)
            if (y != 0 || (x != 1 && x != 2))
                QCOMPARE(result.pixelColor(x, y), image.pixelColor(x, y));
    QCOMPARE(image.pixelColor(1, 0).rgba64().red(), quint16(3000));
}

void MosaicTest::rectangleClipsAtImageEdges()
{
    QImage image(2, 2, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(0, 0, Qt::white);
    const auto result = pixelateRect(image, QRect(-2, -2, 3, 3), 2);
    QCOMPARE(result.pixelColor(0, 0).rgba64().red(), quint16(16384));
    QCOMPARE(result.pixelColor(1, 0), image.pixelColor(1, 0));
    QCOMPARE(result.pixelColor(0, 1), image.pixelColor(0, 1));
}

void MosaicTest::averagesIgnoreTransparentColorAndPreserveAlpha()
{
    QImage image(2, 2, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(0, 65535, 0, 0));
    image.setPixelColor(1, 0, Qt::red);
    image.setPixelColor(0, 1, Qt::blue);
    image.setPixelColor(1, 1, Qt::black);
    const auto result = pixelateRect(image, image.rect(), 2);
    const auto pixel = result.pixelColor(1, 0).rgba64();
    QCOMPARE(pixel.red(), quint16(21845));
    QCOMPARE(pixel.green(), quint16(0));
    QCOMPARE(pixel.blue(), quint16(21845));
    for (int y = 0; y < 2; ++y)
        for (int x = 0; x < 2; ++x)
            QCOMPARE(result.pixelColor(x, y).alpha(), image.pixelColor(x, y).alpha());
    QCOMPARE(result.pixelColor(0, 0), image.pixelColor(0, 0));
}

void MosaicTest::preservesHighDepthColorSpaceAndMetadata()
{
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    image.setPixelColor(1, 0, QColor::fromRgba64(12347, 23458, 34569, 45678));
    image.setColorSpace(QColorSpace::DisplayP3);
    image.setDevicePixelRatio(2.0);
    image.setText("note", "mosaic metadata");
    const auto result = pixelateRect(image, image.rect(), 2);
    QCOMPARE(result.format(), image.format());
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.devicePixelRatio(), 2.0);
    QCOMPARE(result.text("note"), QString("mosaic metadata"));
    QCOMPARE(result.pixelColor(0, 0).rgba64().red(), quint16(12346));
    QCOMPARE(result.pixelColor(0, 0).rgba64().alpha(), quint16(45678));
}

void MosaicTest::strokeConnectsSamplesAndLeavesOutsideUntouched()
{
    QImage image(12, 7, QImage::Format_RGBA64);
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            image.setPixelColor(x, y, QColor::fromRgba64(x * 1000 + y * 100, 0, 0, 65535));
    const Stroke stroke{{QPointF(2.5, 3.5), QPointF(9.5, 3.5)}, 3.0};
    const auto result = pixelateStroke(image, stroke, 2);
    QCOMPARE(result.pixelColor(6, 3).rgba64().red(), quint16(6750));
    QCOMPARE(result.pixelColor(1, 3).rgba64().red(), quint16(750));
    QCOMPARE(result.pixelColor(0, 2), image.pixelColor(0, 2));
    for (int x = 0; x < image.width(); ++x)
        QCOMPARE(result.pixelColor(x, 0), image.pixelColor(x, 0));
}

void MosaicTest::singlePointStrokeHasRoundFootprint()
{
    QImage image(9, 9, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(4, 4, Qt::white);
    image.setPixelColor(2, 2, Qt::red);
    const auto result = pixelateStroke(image, Stroke{{QPointF(4.5, 4.5)}, 4.0}, 2);
    QCOMPARE(result.pixelColor(4, 4).rgba64().red(), quint16(16384));
    QCOMPARE(result.pixelColor(2, 2), image.pixelColor(2, 2));
    QCOMPARE(result.pixelColor(8, 8), image.pixelColor(8, 8));
}

void MosaicTest::rejectsInvalidAndExcessiveInputs()
{
    QImage image(3, 3, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(1, 1, Qt::white);
    QVERIFY(pixelateRect({}, QRect(0, 0, 2, 2), 2).isNull());
    QCOMPARE(pixelateRect(image, image.rect(), 0), image);
    QCOMPARE(pixelateRect(image, image.rect(), 1), image);
    QCOMPARE(pixelateRect(image, QRect(10, 10, 2, 2), 2), image);
    QCOMPARE(pixelateRect(image, QRect(0, 0, -1, 3), 2), image);
    QCOMPARE(pixelateStroke(image, {}, 2), image);
    QCOMPARE(pixelateStroke(image, Stroke{{QPointF(1, 1)}, 0.0}, 2), image);
    QCOMPARE(pixelateStroke(image, Stroke{{QPointF(1, 1)}, std::numeric_limits<double>::infinity()}, 2), image);
    QCOMPARE(pixelateStroke(image, Stroke{{QPointF(std::numeric_limits<double>::quiet_NaN(), 1)}, 3}, 2), image);
    QCOMPARE(pixelateStroke(image, Stroke{{QPointF(1e100, 1)}, 3}, 2), image);
    Stroke excessive;
    excessive.points.fill(QPointF(1, 1), 4097);
    QCOMPARE(pixelateStroke(image, excessive, 2), image);
}

void MosaicTest::clampsOversizedBlockAndDiameter()
{
    QImage image(3, 3, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(1, 1, Qt::white);
    const auto expected = pixelateRect(image, image.rect(), 512);
    QCOMPARE(expected.pixelColor(1, 1).rgba64().red(), quint16(7282));
    QCOMPARE(pixelateRect(image, image.rect(), std::numeric_limits<int>::max()), expected);
    QCOMPARE(pixelateStroke(image, Stroke{{QPointF(1.5, 1.5)}, 1e8}, 512), expected);
}

void MosaicTest::repeatedSamplesStillPaintOneDab()
{
    QImage image(5, 5, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(2, 2, Qt::white);
    const auto result = pixelateStroke(image,
        Stroke{{QPointF(2.5, 2.5), QPointF(2.5, 2.5)}, 3}, 2);
    QCOMPARE(result.pixelColor(2, 2).rgba64().red(), quint16(16384));
}

void MosaicTest::clipsLongOffCanvasSegments()
{
    QImage image(5, 5, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(2, 2, Qt::white);
    const auto result = pixelateStroke(image,
        Stroke{{QPointF(-1e7, 2.5), QPointF(1e7, 2.5)}, 3}, 2);
    QCOMPARE(result.pixelColor(2, 2).rgba64().red(), quint16(16384));
    QCOMPARE(result.pixelColor(2, 0), image.pixelColor(2, 0));
}

void MosaicTest::weightsPartiallyTransparentPixels()
{
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(60000, 0, 0, 1));
    image.setPixelColor(1, 0, QColor::fromRgba64(0, 0, 40000, 3));
    const auto result = pixelateRect(image, image.rect(), 2);
    QCOMPARE(result.pixelColor(0, 0).rgba64().red(), quint16(15000));
    QCOMPARE(result.pixelColor(0, 0).rgba64().blue(), quint16(30000));
    QCOMPARE(result.pixelColor(0, 0).rgba64().alpha(), quint16(1));
    QCOMPARE(result.pixelColor(1, 0).rgba64().alpha(), quint16(3));
}

void MosaicTest::rejectsExcessiveStrokeRasterWork()
{
    QImage image(512, 512, QImage::Format_RGBA64);
    image.fill(Qt::black);
    image.setPixelColor(256, 256, Qt::white);
    Stroke stroke;
    stroke.diameter = 4096;
    stroke.points.reserve(4096);
    for (int index = 0; index < 4096; ++index)
        stroke.points.append(QPointF(index % 2 == 0 ? 255 : 257, 256));
    QCOMPARE(pixelateStroke(image, stroke, 2), image);
}

void MosaicTest::preservesFloatingPointPrecisionAndAlpha()
{
    QImage image(3, 1, QImage::Format_RGBA32FPx4);
    constexpr float samples[]{0.123456F, 0.0F, 0.0F, 0.345678F,
                              0.123460F, 0.0F, 0.0F, 0.345678F,
                              0.912345F, 0.0F, 0.0F, 0.876543F};
    std::memcpy(image.bits(), samples, sizeof(samples));
    const auto result = pixelateRect(image, QRect(0, 0, 2, 1), 2);
    const auto *pixels = reinterpret_cast<const float *>(result.constBits());
    QCOMPARE(pixels[0], 0.123458F);
    QCOMPARE(pixels[3], 0.345678F);
    QCOMPARE(pixels[7], 0.345678F);
    QVERIFY(std::memcmp(result.constBits() + 8 * sizeof(float),
                        image.constBits() + 8 * sizeof(float), 4 * sizeof(float)) == 0);
}

void MosaicTest::rgba8DirectMatchesGenericReference()
{
    const QList<QRect> rectangles{
        QRect(3, 2, 11, 9), QRect(0, 0, 5, 5), QRect(15, 10, 8, 7)};
    for (const auto format : rgba8Formats) {
        const auto image = patternedImage(format);
        for (int blockSize : {2, 3, 7}) {
            for (const auto &rectangle : rectangles) {
                const auto roi = rectangle.intersected(image.rect());
                const auto expected = genericReference(image, roi, blockSize);
                const auto result = pixelateRect(image, rectangle, blockSize);
                QVERIFY2(result == expected,
                    qPrintable(QStringLiteral("format %1 block %2 rect %3,%4 %5x%6")
                        .arg(int(format)).arg(blockSize).arg(rectangle.x())
                        .arg(rectangle.y()).arg(rectangle.width()).arg(rectangle.height())));
                for (int y = 0; y < image.height(); ++y) {
                    for (int x = 0; x < image.width(); ++x) {
                        QCOMPARE(result.pixelColor(x, y).alpha(),
                                 image.pixelColor(x, y).alpha());
                        // Fully transparent destination pixels stay untouched,
                        // including their (possibly encoded) RGB payload.
                        if (image.pixelColor(x, y).alpha() == 0)
                            QCOMPARE(result.pixelColor(x, y), image.pixelColor(x, y));
                    }
                }
            }
            // The whole-image ROI exercises padded edges and partial blocks.
            QVERIFY(pixelateRect(image, image.rect(), blockSize)
                == genericReference(image, image.rect(), blockSize));
        }
        QVERIFY(image == patternedImage(format));
    }
}

void MosaicTest::rgba8StrokeDirectMatchesGenericReference()
{
    const QList<Stroke> strokes{
        Stroke{{QPointF(3.5, 4.5), QPointF(12.5, 9.5), QPointF(19.5, 3.5)}, 5.0},
        Stroke{{QPointF(11.5, 8.5)}, 4.0},
    };
    for (const auto format : rgba8Formats) {
        const auto image = patternedImage(format);
        for (const auto &stroke : strokes) {
            for (int blockSize : {2, 4}) {
                const auto expected = strokeReference(image, stroke, blockSize);
                const auto result = pixelateStroke(image, stroke, blockSize);
                QVERIFY2(result == expected,
                    qPrintable(QStringLiteral("format %1 block %2")
                        .arg(int(format)).arg(blockSize)));
                for (int y = 0; y < image.height(); ++y)
                    for (int x = 0; x < image.width(); ++x) {
                        QCOMPARE(result.pixelColor(x, y).alpha(),
                                 image.pixelColor(x, y).alpha());
                        if (image.pixelColor(x, y).alpha() == 0)
                            QCOMPARE(result.pixelColor(x, y), image.pixelColor(x, y));
                    }
            }
        }
        QVERIFY(image == patternedImage(format));
    }
}

QTEST_GUILESS_MAIN(MosaicTest)
#include "tst_mosaic.moc"
