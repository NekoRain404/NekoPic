#include "adjustments.h"

#include <QColorSpace>
#include <QtTest>
#include <qfloat16.h>
#include <cstring>

using namespace NekoPic::Adjustments;

class AdjustmentsTest : public QObject {
    Q_OBJECT
private slots:
    void identityPreservesImage();
    void exposureBrightensAndDarkens();
    void brightnessAndContrastChangeTonality();
    void saturationChangesColorWithoutChangingAlpha();
    void preservesHighDepthAndColorSpace();
    void handlesNullAndOutOfRangeParameters();
    void presetsRespectIntensityAndPreserveImageMetadata();
    void colorFilterPromotesGrayscaleWithoutDiscardingTint();
    void floatingFilterPreservesStorage_data();
    void floatingFilterPreservesStorage();
    void floatingExposurePreservesHdrPrecision();
    void rgba64FilterHasExactChannels();
    void floatingVividMatchesIntegerAtPartialIntensity();
};

void AdjustmentsTest::identityPreservesImage()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    QCOMPARE(apply(image, {}), image);
}

void AdjustmentsTest::exposureBrightensAndDarkens()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.fill(QColor::fromRgbF(0.25, 0.25, 0.25));
    Parameters p;
    p.exposure = 1.0;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() > image.pixelColor(0, 0).redF());
    p.exposure = -1.0;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() < image.pixelColor(0, 0).redF());
}

void AdjustmentsTest::brightnessAndContrastChangeTonality()
{
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgbF(0.25, 0.25, 0.25));
    image.setPixelColor(1, 0, QColor::fromRgbF(0.75, 0.75, 0.75));
    Parameters p;
    p.brightness = 0.2;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() > image.pixelColor(0, 0).redF());
    p.brightness = 0.0;
    p.contrast = 0.5;
    const auto adjusted = apply(image, p);
    QVERIFY(adjusted.pixelColor(0, 0).redF() < image.pixelColor(0, 0).redF());
    QVERIFY(adjusted.pixelColor(1, 0).redF() > image.pixelColor(1, 0).redF());
}

void AdjustmentsTest::saturationChangesColorWithoutChangingAlpha()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(50000, 20000, 10000, 12345));
    Parameters p;
    p.saturation = -1.0;
    const auto pixel = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(pixel.red(), pixel.green());
    QCOMPARE(pixel.green(), pixel.blue());
    QCOMPARE(pixel.alpha(), quint16(12345));
}

void AdjustmentsTest::preservesHighDepthAndColorSpace()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    image.setColorSpace(QColorSpace::DisplayP3);
    Parameters p;
    p.brightness = 0.01;
    const auto result = apply(image, p);
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.pixelColor(0, 0).rgba64().alpha(), quint16(45678));
    QVERIFY(result.pixelColor(0, 0).rgba64().red() % 257 != 0);
}

void AdjustmentsTest::handlesNullAndOutOfRangeParameters()
{
    QVERIFY(apply(QImage(), {}).isNull());
    QImage image(1, 1, QImage::Format_RGBA64);
    image.fill(Qt::red);
    Parameters p;
    p.brightness = 100.0;
    const auto result = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(result.red(), quint16(65535));
    QCOMPARE(result.green(), quint16(65535));
}

void AdjustmentsTest::presetsRespectIntensityAndPreserveImageMetadata()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(50000, 20000, 10000, 12345));
    image.setColorSpace(QColorSpace::DisplayP3);
    Parameters p;
    p.filterPreset = "mono";
    p.filterIntensity = 0.0;
    QCOMPARE(apply(image, p), image);
    p.filterIntensity = 1.0;
    const auto filtered = apply(image, p);
    QCOMPARE(filtered.format(), image.format());
    QCOMPARE(filtered.colorSpace(), image.colorSpace());
    QCOMPARE(filtered.pixelColor(0, 0).rgba64().alpha(), quint16(12345));
    const auto pixel = filtered.pixelColor(0, 0).rgba64();
    QCOMPARE(pixel.red(), pixel.green());
    QCOMPARE(pixel.green(), pixel.blue());
    p.filterPreset = "unknown";
    QCOMPARE(apply(image, p), image);
}

void AdjustmentsTest::colorFilterPromotesGrayscaleWithoutDiscardingTint()
{
    QImage image(1, 1, QImage::Format_Grayscale8);
    image.fill(QColor(100, 100, 100));
    image.setColorSpace(QColorSpace::SRgb);
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p);
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QVERIFY(result.pixelColor(0, 0).red() > result.pixelColor(0, 0).blue());
}

void AdjustmentsTest::floatingFilterPreservesStorage_data()
{
    QTest::addColumn<QImage::Format>("format");
    QTest::newRow("rgba-float") << QImage::Format_RGBA32FPx4;
    QTest::newRow("rgba-half") << QImage::Format_RGBA16FPx4;
    QTest::newRow("rgba-float-premultiplied") << QImage::Format_RGBA32FPx4_Premultiplied;
    QTest::newRow("rgba-half-premultiplied") << QImage::Format_RGBA16FPx4_Premultiplied;
    QTest::newRow("rgbx-float") << QImage::Format_RGBX32FPx4;
    QTest::newRow("rgbx-half") << QImage::Format_RGBX16FPx4;
}

void AdjustmentsTest::floatingFilterPreservesStorage()
{
    QFETCH(QImage::Format, format);
    QImage seed(1, 1, QImage::Format_RGBA32FPx4);
    auto *seedChannels = reinterpret_cast<float *>(seed.bits());
    seedChannels[0] = 0.123456789f;
    seedChannels[1] = 1.23456789f; // Warm does not edit green, even above SDR white.
    seedChannels[2] = 0.234567891f;
    seedChannels[3] = 0.3456780016f;
    const auto image = seed.convertToFormat(format);
    const auto original = image.copy();
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p);
    QCOMPARE(result.format(), format);
    const qsizetype channelBytes = image.depth() / 32;
    QCOMPARE(std::memcmp(result.constBits() + 3 * channelBytes,
                         image.constBits() + 3 * channelBytes, channelBytes), 0);
    QCOMPARE(std::memcmp(result.constBits() + channelBytes,
                         image.constBits() + channelBytes, channelBytes), 0);
    QVERIFY(std::memcmp(result.constBits(), image.constBits(), channelBytes) != 0);
    QCOMPARE(image, original);
    p.filterIntensity = 0;
    QCOMPARE(apply(image, p), original);
}

void AdjustmentsTest::floatingExposurePreservesHdrPrecision()
{
    QImage image(1, 1, QImage::Format_RGBA32FPx4);
    image.setColorSpace(QColorSpace::DisplayP3);
    auto *pixel = reinterpret_cast<float *>(image.bits());
    pixel[0] = 2.1234567f;
    pixel[1] = 0.123456789f;
    pixel[2] = -0.125f;
    pixel[3] = 0.3456780016f;
    Parameters p;
    p.exposure = 1;
    const auto result = apply(image, p);
    QCOMPARE(result.format(), image.format());
    QCOMPARE(result.colorSpace(), image.colorSpace());
    const auto *adjusted = reinterpret_cast<const float *>(result.constBits());
    QCOMPARE(adjusted[0], pixel[0] * 2);
    QCOMPARE(adjusted[1], pixel[1] * 2);
    QCOMPARE(adjusted[2], -0.25f);
    QCOMPARE(std::memcmp(adjusted + 3, pixel + 3, sizeof(float)), 0);
    p.exposure = 0;
    p.filterPreset = "warm";
    p.filterIntensity = 0.5;
    const auto warm = apply(image, p);
    const auto *filtered = reinterpret_cast<const float *>(warm.constBits());
    QCOMPARE(filtered[1], pixel[1]);
    QCOMPARE(filtered[2], -0.0625f); // Blend an explicitly SDR-clamped warm-blue target.
}

void AdjustmentsTest::rgba64FilterHasExactChannels()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(10000, 20000, 30000, 12345));
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(result.red(), quint16(16664));
    QCOMPARE(result.green(), quint16(20000));
    QCOMPARE(result.blue(), quint16(26400));
    QCOMPARE(result.alpha(), quint16(12345));
}

void AdjustmentsTest::floatingVividMatchesIntegerAtPartialIntensity()
{
    QImage image(3, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(60000, 10000, 30000, 12345));
    image.setPixelColor(1, 0, QColor::fromRgba64(5000, 60000, 10000, 23456));
    image.setPixelColor(2, 0, QColor::fromRgba64(10000, 20000, 65000, 34567));
    Parameters p;
    p.filterPreset = "vivid";
    p.filterIntensity = 0.5;
    const auto integerResult = apply(image, p);
    const auto floatingResult = apply(image.convertToFormat(QImage::Format_RGBA32FPx4), p);
    for (int x = 0; x < image.width(); ++x) {
        const auto expected = integerResult.pixelColor(x, 0);
        const auto actual = floatingResult.pixelColor(x, 0);
        // One 16-bit rounding unit, allowing for float conversion on input.
        QVERIFY(std::abs(actual.redF() - expected.redF()) < 2.0 / 65535);
        QVERIFY(std::abs(actual.greenF() - expected.greenF()) < 2.0 / 65535);
        QVERIFY(std::abs(actual.blueF() - expected.blueF()) < 2.0 / 65535);
    }
}

QTEST_GUILESS_MAIN(AdjustmentsTest)
#include "tst_adjustments.moc"
