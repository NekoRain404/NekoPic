#include "io/imageio.h"

#include <QColorSpace>
#include <QFile>
#include <QImageReader>
#include <QTemporaryDir>
#include <QtTest>

using namespace NekoPic::ImageIO;

class ImageIoTest : public QObject {
    Q_OBJECT
private slots:
    void pngRoundTripPreservesAlphaAndDepth();
    void jpegCompositesOnChosenBackground();
    void jpegCompositePreservesResolution();
    void wideGamutProfileRoundTrip();
    void failuresAreReported();
    void dimensionsAreLimited();
    void reportsRuntimeFormats();
};

void ImageIoTest::pngRoundTripPreservesAlphaAndDepth()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    image.setPixelColor(1, 0, QColor::fromRgba64(65535, 0, 11111, 0));
    image.setColorSpace(QColorSpace::SRgb);
    const QString path = dir.filePath("image.png");
    QVERIFY2(save(path, image).success, "PNG save failed");
    const auto result = load(path);
    QVERIFY2(result.error.isEmpty(), qPrintable(result.error));
    QCOMPARE(result.image.size(), image.size());
    QVERIFY(result.image.depth() > 32);
    QCOMPARE(result.image.pixelColor(0, 0).rgba64(), image.pixelColor(0, 0).rgba64());
    QCOMPARE(result.image.pixelColor(1, 0).rgba64(), image.pixelColor(1, 0).rgba64());
    QCOMPARE(result.image.colorSpace(), image.colorSpace());
}

void ImageIoTest::wideGamutProfileRoundTrip()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(16, 16, QImage::Format_RGBA64);
    image.fill(QColor::fromRgba64(30000, 20000, 10000, 32768));
    image.setColorSpace(QColorSpace::DisplayP3);
    for (const auto &format : {QByteArray("png"), QByteArray("jpeg")}) {
        SaveOptions options;
        options.format = format;
        const auto path = dir.filePath(QStringLiteral("wide.") + QString::fromLatin1(format));
        const auto saved = save(path, image, options);
        QVERIFY2(saved.success, qPrintable(saved.error));
        const auto result = load(path);
        QVERIFY2(result.error.isEmpty(), qPrintable(result.error));
        QCOMPARE(result.image.colorSpace(), image.colorSpace());
    }
}

void ImageIoTest::jpegCompositesOnChosenBackground()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(16, 16, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    SaveOptions options;
    options.format = "jpeg";
    options.jpegBackground = Qt::red;
    options.quality = 100;
    const QString path = dir.filePath("image.jpg");
    const auto saved = save(path, image, options);
    QVERIFY2(saved.success, qPrintable(saved.error));
    const auto result = load(path);
    QVERIFY2(result.error.isEmpty(), qPrintable(result.error));
    const QColor pixel = result.image.pixelColor(8, 8);
    QVERIFY(pixel.red() > 245);
    QVERIFY(pixel.green() < 10);
    QVERIFY(pixel.blue() < 10);
    QCOMPARE(pixel.alpha(), 255);
}

void ImageIoTest::jpegCompositePreservesResolution()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(16, 16, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    image.setDotsPerMeterX(11811);
    image.setDotsPerMeterY(11811);
    const auto saved = save(dir.filePath("resolution.jpg"), image);
    QVERIFY2(saved.success, qPrintable(saved.error));
    const auto result = load(dir.filePath("resolution.jpg"));
    QVERIFY2(result.error.isEmpty(), qPrintable(result.error));
    QCOMPARE(result.image.dotsPerMeterX(), 11811);
    QCOMPARE(result.image.dotsPerMeterY(), 11811);
}

void ImageIoTest::failuresAreReported()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const auto missing = load(dir.filePath("missing.png"));
    QVERIFY(missing.image.isNull());
    QVERIFY(!missing.error.isEmpty());
    const auto empty = save(dir.filePath("empty.png"), QImage());
    QVERIFY(!empty.success);
    QVERIFY(!empty.error.isEmpty());
    QImage image(1, 1, QImage::Format_RGB32);
    const auto badPath = save(dir.filePath("missing/image.png"), image);
    QVERIFY(!badPath.success);
    QVERIFY(!badPath.error.isEmpty());
    SaveOptions options;
    options.format = "gif";
    const auto badFormat = save(dir.filePath("image.gif"), image, options);
    QVERIFY(!badFormat.success);
    QVERIFY(!badFormat.error.isEmpty());
}

void ImageIoTest::dimensionsAreLimited()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(10, 8, QImage::Format_RGB32);
    image.fill(Qt::blue);
    const QString path = dir.filePath("large.png");
    QVERIFY(image.save(path));
    Limits limits;
    limits.maxPixels = 79;
    const auto result = load(path, limits);
    QVERIFY(result.image.isNull());
    QVERIFY(!result.error.isEmpty());
}

void ImageIoTest::reportsRuntimeFormats()
{
    QCOMPARE(supportedReadFormats(), QImageReader::supportedImageFormats());
}

QTEST_GUILESS_MAIN(ImageIoTest)
#include "tst_imageio.moc"
