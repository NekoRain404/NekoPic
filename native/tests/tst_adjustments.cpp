#include "adjustments.h"

#include <QColorSpace>
#include <QtTest>

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

QTEST_GUILESS_MAIN(AdjustmentsTest)
#include "tst_adjustments.moc"
