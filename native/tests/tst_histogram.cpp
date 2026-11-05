#include "core/histogram.h"

#include <QtTest>

using NekoPic::Histogram::compute;

class HistogramTest final : public QObject {
    Q_OBJECT
private slots:
    void countsSolidColours()
    {
        QImage image(8, 8, QImage::Format_RGBA8888);
        image.fill(QColor(255, 0, 0));
        const auto data = compute(image);
        QCOMPARE(data.sampledPixels, quint64(64));
        QCOMPARE(data.totalPixels, quint64(64));
        QCOMPARE(data.red[255], quint32(64));
        QCOMPARE(data.green[0], quint32(64));
        QCOMPARE(data.blue[0], quint32(64));
        QCOMPARE(data.luma[54], quint32(64)); // 0.2126*255 ≈ 54
    }

    void samplesLargeImages()
    {
        QImage image(1024, 1024, QImage::Format_RGBA8888);
        image.fill(Qt::black);
        const auto data = compute(image, 10000);
        QVERIFY(data.sampledPixels <= 10000);
        QVERIFY(data.sampledPixels > 9000);
        QCOMPARE(data.totalPixels, quint64(1024) * 1024);
    }

    void handlesNullOrEmpty()
    {
        QVERIFY(compute(QImage()).sampledPixels == 0);
        QImage empty(0, 0, QImage::Format_RGBA8888);
        QVERIFY(compute(empty).sampledPixels == 0);
    }

    void preservesChannelIndependence()
    {
        QImage image(4, 1, QImage::Format_RGBA8888);
        image.setPixelColor(0, 0, QColor(10, 20, 30));
        image.setPixelColor(1, 0, QColor(200, 100, 50));
        image.setPixelColor(2, 0, QColor(0, 255, 0));
        image.setPixelColor(3, 0, QColor(255, 255, 255));
        const auto data = compute(image);
        QCOMPARE(data.red[0], quint32(1));
        QCOMPARE(data.green[255], quint32(2));
        QCOMPARE(data.blue[0], quint32(1));
        QCOMPARE(data.luma[255], quint32(1));
    }
};

QTEST_MAIN(HistogramTest)
#include "tst_histogram.moc"
