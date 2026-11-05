#include "blur.h"

#include <QColorSpace>
#include <QtTest>

#include <cstring>
#include <limits>

using namespace NekoPic::Blur;

namespace {

QImage patternImage(int width, int height, QImage::Format format)
{
    QImage image(width, height, format);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int red = (x * 37 + y * 17 + 11) & 0xff;
            const int green = (x * 11 + y * 53 + 29) & 0xff;
            const int blue = (x * 71 + y * 23 + 7) & 0xff;
            image.setPixelColor(x, y, QColor(red, green, blue, 255));
        }
    }
    return image;
}

void compareOutside(const QImage& result, const QImage& source, const QRect& roi)
{
    for (int y = 0; y < source.height(); ++y)
        for (int x = 0; x < source.width(); ++x)
            if (!roi.contains(x, y))
                QCOMPARE(result.pixelColor(x, y), source.pixelColor(x, y));
}

} // namespace

class BlurTest : public QObject
{
    Q_OBJECT
private slots:
    void uniformImageStaysUniform();
    void brightPixelSpreadsAndOutsideUntouched();
    void hardAlphaEdgeHasNoColourFringe();
    void rgba64KeepsPrecision();
    void rejectsInvalidRequests();
    void withinLimitsReportsErrors();
    void strokeBlursBandAndLeavesOutside();
    void singlePointStrokeHasRoundFootprint();
    void clipsAtAllFourEdges();
    void preservesMetadata();
    void deterministicOutput();
    void preservesSupportedFormats();
};

void BlurTest::uniformImageStaysUniform()
{
    const QColor colour(40, 90, 160, 255);
    QImage image(32, 24, QImage::Format_RGBA8888);
    image.fill(colour);

    const auto result = applyRect(image, QRect(6, 5, 14, 11), 7);

    QCOMPARE(result.size(), image.size());
    QCOMPARE(result.format(), image.format());
    for (int y = 5; y <= 15; ++y)
        for (int x = 6; x <= 19; ++x)
            QCOMPARE(result.pixelColor(x, y), colour);
    QCOMPARE(result.pixelColor(0, 0), colour);
    QCOMPARE(result.pixelColor(31, 23), colour);
}

void BlurTest::brightPixelSpreadsAndOutsideUntouched()
{
    QImage image(21, 21, QImage::Format_RGB32);
    image.fill(Qt::black);
    image.setPixelColor(10, 10, Qt::white);

    const QRect area(6, 6, 9, 9);
    const auto result = applyRect(image, area, 3);

    QCOMPARE(result.format(), image.format());
    QVERIFY(result.pixelColor(10, 10).red() > 0);
    QVERIFY(result.pixelColor(10, 10).red() < 255);
    QVERIFY(result.pixelColor(9, 10).red() > 0);
    QVERIFY(result.pixelColor(10, 9).red() > 0);
    QVERIFY(result.pixelColor(8, 10).red() > 0);
    QVERIFY(result.pixelColor(10, 8).red() > 0);

    compareOutside(result, image, area);
    // The source must not be modified.
    QCOMPARE(image.pixelColor(10, 10), QColor(Qt::white));
}

void BlurTest::hardAlphaEdgeHasNoColourFringe()
{
    const QList<QImage::Format> formats{QImage::Format_ARGB32, QImage::Format_ARGB32_Premultiplied};

    for (const auto format : formats) {
        QImage image(2, 1, format);
        image.setPixelColor(0, 0, QColor(255, 0, 0, 255));
        image.setPixelColor(1, 0, QColor(0, 255, 0, 0));

        const auto result = applyRect(image, image.rect(), 3);
        QCOMPARE(result.format(), format);
        for (int x = 0; x < 2; ++x) {
            const auto pixel = result.pixelColor(x, 0);
            // Transparent green contributes no colour: no green/blue fringe.
            QCOMPARE(pixel.green(), 0);
            QCOMPARE(pixel.blue(), 0);
            QCOMPARE(pixel.red(), 255);
            QVERIFY(pixel.alpha() > 0);
            QVERIFY(pixel.alpha() < 255);
        }
    }
}

void BlurTest::rgba64KeepsPrecision()
{
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(0, 0, 0, 65535));
    image.setPixelColor(1, 0, QColor::fromRgba64(65535, 0, 0, 65535));

    const auto result = applyRect(image, image.rect(), 1);

    QCOMPARE(result.format(), QImage::Format_RGBA64);
    const auto left = result.pixelColor(0, 0).rgba64();
    const auto right = result.pixelColor(1, 0).rgba64();
    // Values follow the documented three-box-pass arithmetic and are not
    // multiples of 257, proving the result never passed through 8-bit.
    QCOMPARE(left.red(), quint16(31554));
    QCOMPARE(right.red(), quint16(33981));
    QCOMPARE(left.alpha(), quint16(65535));
    QCOMPARE(right.alpha(), quint16(65535));
    QVERIFY(left.red() % 257 != 0);
    QVERIFY(right.red() % 257 != 0);
}

void BlurTest::rejectsInvalidRequests()
{
    const auto image = patternImage(6, 6, QImage::Format_ARGB32);

    QCOMPARE(applyRect(image, image.rect(), 0), image);
    QCOMPARE(applyRect(image, image.rect(), -3), image);
    QCOMPARE(applyRect(image, QRect(), 2), image);
    QCOMPARE(applyRect(image, QRect(100, 100, 4, 4), 2), image);
    QCOMPARE(applyRect(image, image.rect(), 257), image);

    Limits pixelLimit;
    pixelLimit.maxPixels = 3;
    QCOMPARE(applyRect(image, image.rect(), 2, pixelLimit), image);

    const QImage nullImage;
    QVERIFY(applyRect(nullImage, QRect(0, 0, 2, 2), 2).isNull());

    QImage indexed(4, 4, QImage::Format_Indexed8);
    indexed.setColorCount(2);
    indexed.setColor(0, Qt::black);
    indexed.setColor(1, Qt::white);
    indexed.fill(0);
    QCOMPARE(applyRect(indexed, indexed.rect(), 2), indexed);

    QImage grayscale(4, 4, QImage::Format_Grayscale8);
    grayscale.fill(120);
    QCOMPARE(applyRect(grayscale, grayscale.rect(), 2), grayscale);

    const QList<QPointF> validPoints{QPointF(1.0, 1.0), QPointF(4.0, 4.0)};
    QCOMPARE(applyStroke(image, {}, 2), image);
    QCOMPARE(applyStroke(image, validPoints, 0), image);
    QCOMPARE(applyStroke(image, validPoints, 257), image);
    QCOMPARE(applyStroke(image, {QPointF(std::numeric_limits<double>::quiet_NaN(), 1.0)}, 2),
             image);
    QCOMPARE(applyStroke(image, {QPointF(std::numeric_limits<double>::infinity(), 1.0)}, 2), image);
    QCOMPARE(applyStroke(image, {QPointF(2e7, 1.0)}, 2), image);
    QCOMPARE(applyStroke(image, {QPointF(100.0, 100.0)}, 2), image);

    QList<QPointF> tooManyPoints;
    tooManyPoints.fill(QPointF(2.0, 2.0), 4097);
    QCOMPARE(applyStroke(image, tooManyPoints, 2), image);
}

void BlurTest::withinLimitsReportsErrors()
{
    const QImage image(4, 4, QImage::Format_ARGB32);
    QString error = QStringLiteral("stale");
    QVERIFY(withinLimits(image, 2, {}, &error));
    QVERIFY(error.isEmpty());

    QVERIFY(!withinLimits(QImage(), 2, {}, &error));
    QVERIFY(error.contains(QStringLiteral("empty"), Qt::CaseInsensitive));

    QImage indexed(4, 4, QImage::Format_Indexed8);
    QVERIFY(!withinLimits(indexed, 2, {}, &error));
    QVERIFY(error.contains(QStringLiteral("format"), Qt::CaseInsensitive));

    QVERIFY(!withinLimits(image, 0, {}, &error));
    QVERIFY(error.contains(QStringLiteral("radius"), Qt::CaseInsensitive));
    QVERIFY(!withinLimits(image, 257, {}, &error));
    QVERIFY(error.contains(QStringLiteral("exceeds"), Qt::CaseInsensitive));

    Limits pixelLimit;
    pixelLimit.maxPixels = 3;
    QVERIFY(!withinLimits(image, 2, pixelLimit, &error));
    QVERIFY(error.contains(QStringLiteral("pixels"), Qt::CaseInsensitive));

    Limits invalidRadiusLimit;
    invalidRadiusLimit.maxRadius = 0;
    QVERIFY(!withinLimits(image, 1, invalidRadiusLimit, &error));
    QVERIFY(error.contains(QStringLiteral("maximum"), Qt::CaseInsensitive));

    QVERIFY(!withinLimits(image, 2, pixelLimit, nullptr));
}

void BlurTest::strokeBlursBandAndLeavesOutside()
{
    const auto image = patternImage(40, 20, QImage::Format_ARGB32);
    const auto result = applyStroke(image, {QPointF(8.0, 10.0), QPointF(32.0, 10.0)}, 4);

    QCOMPARE(result.format(), image.format());

    bool changed = false;
    for (int y = 9; y <= 11; ++y)
        for (int x = 12; x <= 28; ++x)
            if (result.pixelColor(x, y) != image.pixelColor(x, y))
                changed = true;
    QVERIFY(changed);

    // Bounding box: points expanded by radius + 1 for antialiasing.
    const QRect affected(3, 5, 34, 10);
    compareOutside(result, image, affected);
}

void BlurTest::singlePointStrokeHasRoundFootprint()
{
    const auto image = patternImage(21, 21, QImage::Format_ARGB32);
    const auto result = applyStroke(image, {QPointF(10.0, 10.0)}, 3);

    QVERIFY(result.pixelColor(10, 10) != image.pixelColor(10, 10));
    QCOMPARE(result.pixelColor(0, 0), image.pixelColor(0, 0));
    QCOMPARE(result.pixelColor(20, 20), image.pixelColor(20, 20));
    compareOutside(result, image, QRect(6, 6, 9, 9));
}

void BlurTest::clipsAtAllFourEdges()
{
    const auto image = patternImage(10, 10, QImage::Format_ARGB32);
    const QList<QRect> rectangles{
        QRect(-5, 2, 8, 6),   // overlaps the left edge
        QRect(5, 2, 8, 6),    // overlaps the right edge
        QRect(2, -5, 6, 8),   // overlaps the top edge
        QRect(2, 5, 6, 8),    // overlaps the bottom edge
        QRect(-5, -5, 20, 20) // covers the whole image
    };

    for (const auto& rectangle : rectangles) {
        const auto result = applyRect(image, rectangle, 3);
        const auto roi = rectangle.intersected(image.rect());
        QVERIFY(!roi.isEmpty());

        bool changed = false;
        for (int y = 0; y < image.height(); ++y) {
            for (int x = 0; x < image.width(); ++x) {
                if (roi.contains(x, y)) {
                    if (result.pixelColor(x, y) != image.pixelColor(x, y))
                        changed = true;
                } else {
                    QCOMPARE(result.pixelColor(x, y), image.pixelColor(x, y));
                }
            }
        }
        QVERIFY(changed);
    }
}

void BlurTest::preservesMetadata()
{
    auto image = patternImage(16, 12, QImage::Format_RGBA64);
    image.setColorSpace(QColorSpace::DisplayP3);
    image.setDevicePixelRatio(2.0);
    image.setDotsPerMeterX(11811);
    image.setDotsPerMeterY(11812);
    image.setText(QStringLiteral("note"), QStringLiteral("blur metadata"));

    const auto result = applyRect(image, QRect(2, 2, 8, 6), 3);

    QCOMPARE(result.format(), image.format());
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.devicePixelRatio(), 2.0);
    QCOMPARE(result.dotsPerMeterX(), 11811);
    QCOMPARE(result.dotsPerMeterY(), 11812);
    QCOMPARE(result.text(QStringLiteral("note")), QStringLiteral("blur metadata"));
}

void BlurTest::deterministicOutput()
{
    const auto image = patternImage(31, 17, QImage::Format_ARGB32);

    const auto rectangleA = applyRect(image, QRect(3, 2, 20, 10), 4);
    const auto rectangleB = applyRect(image, QRect(3, 2, 20, 10), 4);
    QCOMPARE(rectangleA.format(), rectangleB.format());
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            QCOMPARE(rectangleA.pixelColor(x, y), rectangleB.pixelColor(x, y));

    const QList<QPointF> points{QPointF(4.0, 8.0), QPointF(27.0, 8.0)};
    const auto strokeA = applyStroke(image, points, 3);
    const auto strokeB = applyStroke(image, points, 3);
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            QCOMPARE(strokeA.pixelColor(x, y), strokeB.pixelColor(x, y));
}

void BlurTest::preservesSupportedFormats()
{
    const QList<QImage::Format> formats{QImage::Format_RGB32,
                                        QImage::Format_ARGB32,
                                        QImage::Format_ARGB32_Premultiplied,
                                        QImage::Format_RGBA8888,
                                        QImage::Format_RGBA8888_Premultiplied,
                                        QImage::Format_RGBA64,
                                        QImage::Format_RGBA64_Premultiplied};
    const QColor colour(30, 120, 210, 255);

    for (const auto format : formats) {
        QImage image(8, 6, format);
        image.fill(colour);

        const auto result = applyRect(image, QRect(2, 1, 4, 4), 3);
        QCOMPARE(result.format(), format);
        for (int y = 1; y <= 4; ++y)
            for (int x = 2; x <= 5; ++x)
                QCOMPARE(result.pixelColor(x, y), colour);
    }
}

QTEST_GUILESS_MAIN(BlurTest)
#include "tst_blur.moc"
