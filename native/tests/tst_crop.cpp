#include "app/documentcontroller.h"

#include <QColorSpace>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QThreadPool>
#include <limits>

class CropTest final : public QObject {
    Q_OBJECT
private slots:
    void clippedFractionalCropAndHistory();
    void rejectsInvalidAndBusyCalls();
    void preservesHighDepthAndAdjustments();
    void destructionDuringCrop();
};

namespace {
bool crop(DocumentController &document, const QRectF &area)
{
    // Invoke through the public QML boundary so the missing API fails at runtime.
    return QMetaObject::invokeMethod(&document, "cropImage", Q_ARG(QRectF, area));
}
QImage sample()
{
    QImage image(12, 8, QImage::Format_RGBA64);
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            image.setPixelColor(x, y, QColor::fromRgbF(x / 12.0, y / 8.0, 0.1234, 0.7));
    image.setColorSpace(QColorSpace::AdobeRgb);
    image.setDotsPerMeterX(4000);
    image.setDotsPerMeterY(5000);
    return image;
}
}

void CropTest::clippedFractionalCropAndHistory()
{
    QTemporaryDir directory;
    QVERIFY(sample().save(directory.filePath("source.png")));
    DocumentController document;
    document.openImage(QUrl::fromLocalFile(directory.filePath("source.png")));
    QTRY_VERIFY(!document.busy());
    const auto original = document.image();
    QSignalSpy busy(&document, &DocumentController::busyChanged);
    // Reversed continuous edges are normalized, clipped and rounded outwards.
    QVERIFY(crop(document, QRectF(7.6, 6.2, -9.0, -4.0)));
    QVERIFY(document.busy());
    QCOMPARE(document.image(), original);
    QTRY_VERIFY(!document.busy());
    QCOMPARE(busy.count(), 2);
    QCOMPARE(document.image(), original.copy(0, 2, 8, 5));
    QVERIFY(document.dirty());
    QVERIFY(document.canUndo());
    document.saveAs(QUrl::fromLocalFile(directory.filePath("saved.png")), "png");
    QTRY_VERIFY(!document.busy());
    QVERIFY(!document.dirty());
    document.undo();
    QCOMPARE(document.image(), original);
    QVERIFY(!document.canUndo());
    QVERIFY(document.dirty());
    document.redo();
    QVERIFY(!document.dirty());
    QCOMPARE(document.image().size(), QSize(8, 5));
    QVERIFY(crop(document, QRectF(1.2, 2.2, 0.1, 0.1)));
    QTRY_VERIFY(!document.busy());
    QCOMPARE(document.image().size(), QSize(1, 1));
}

void CropTest::rejectsInvalidAndBusyCalls()
{
    DocumentController empty;
    QVERIFY(crop(empty, QRectF(0, 0, 2, 2)));
    QVERIFY(!empty.busy());
    QTemporaryDir directory;
    QVERIFY(sample().save(directory.filePath("source.png")));
    DocumentController document;
    document.openImage(QUrl::fromLocalFile(directory.filePath("source.png")));
    QTRY_VERIFY(!document.busy());
    const auto original = document.image();
    const auto nan = std::numeric_limits<double>::quiet_NaN();
    const QList<QRectF> invalid{QRectF(0, 0, 12, 8), QRectF(-20, -20, 50, 50),
        QRectF(40, 40, 3, 3), QRectF(0, 0, 0, 1), QRectF(nan, 0, 1, 1),
        QRectF(0, 0, 1e30, 3), QRectF(0, 0, 1, std::numeric_limits<double>::infinity())};
    for (const auto &area : invalid) {
        QVERIFY(crop(document, area));
        QVERIFY(!document.busy());
        QCOMPARE(document.image(), original);
        QVERIFY(!document.dirty());
    }
    document.rotateClockwise();
    QVERIFY(document.busy());
    QVERIFY(crop(document, QRectF(0, 0, 1, 1)));
    QTRY_VERIFY(!document.busy());
    QCOMPARE(document.image().size(), QSize(8, 12));
}

void CropTest::preservesHighDepthAndAdjustments()
{
    QTemporaryDir directory;
    QVERIFY(sample().save(directory.filePath("source.png")));
    DocumentController document;
    document.openImage(QUrl::fromLocalFile(directory.filePath("source.png")));
    QTRY_VERIFY(!document.busy());
    const auto source = document.image();
    QVERIFY(source.depth() >= 64);
    document.beginAdjustment("brightness");
    document.finishAdjustment("brightness", 15);
    QTRY_VERIFY(!document.busy());
    document.selectFilter("warm");
    QTRY_VERIFY(!document.busy());
    const auto rendered = document.image();
    QVERIFY(crop(document, QRectF(2, 1, 5, 4)));
    QTRY_VERIFY(!document.busy());
    QCOMPARE(document.image(), rendered.copy(2, 1, 5, 4));
    QCOMPARE(document.baseImage(), source.copy(2, 1, 5, 4));
    QCOMPARE(document.baseImage().format(), source.format());
    QCOMPARE(document.baseImage().colorSpace(), source.colorSpace());
    QCOMPARE(document.baseImage().dotsPerMeterX(), source.dotsPerMeterX());
    QCOMPARE(document.baseImage().dotsPerMeterY(), source.dotsPerMeterY());
    QCOMPARE(document.adjustmentValues().value("brightness").toDouble(), 15.0);
    QCOMPARE(document.filterPreset(), QString("warm"));
    document.beginAdjustment("brightness");
    document.finishAdjustment("brightness", 0);
    QTRY_VERIFY(!document.busy());
    NekoPic::Adjustments::Parameters expected;
    expected.filterPreset = "warm";
    QCOMPARE(document.image(), NekoPic::Adjustments::apply(source.copy(2, 1, 5, 4), expected));
}

void CropTest::destructionDuringCrop()
{
    QTemporaryDir directory;
    QVERIFY(sample().save(directory.filePath("source.png")));
    {
        DocumentController document;
        document.openImage(QUrl::fromLocalFile(directory.filePath("source.png")));
        QTRY_VERIFY(!document.busy());
        QVERIFY(crop(document, QRectF(1, 1, 6, 4)));
        QVERIFY(document.busy());
    }
    QVERIFY(QThreadPool::globalInstance()->waitForDone(5000));
    QCoreApplication::processEvents();
}

QTEST_MAIN(CropTest)
#include "tst_crop.moc"
