#include "mosaic.h"

#include <QColorSpace>
#include <QtTest>
#include <cstring>
#include <limits>

using namespace NekoPic::Mosaic;

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

QTEST_GUILESS_MAIN(MosaicTest)
#include "tst_mosaic.moc"
