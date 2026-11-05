#include "app/documentcontroller.h"

#include <QImage>
#include <QTemporaryDir>
#include <QtTest>

namespace {
QImage sourceImage()
{
    QImage image(20, 10, QImage::Format_RGBA8888);
    image.fill(QColor(10, 20, 30, 255));
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < 10; ++x) image.setPixelColor(x, y, QColor(220, 30, 30, 255));
        for (int x = 10; x < 20; ++x) image.setPixelColor(x, y, QColor(30, 30, 220, 255));
    }
    return image;
}
}

class ResizeTest final : public QObject {
    Q_OBJECT
private slots:
    void resizeImageScalesAndUndoes()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const int originalWidth = controller.imageWidth();

        controller.resizeImage(40, 20);
        QVERIFY(controller.busy());
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.errorMessage().isEmpty());
        QCOMPARE(controller.imageWidth(), 40);
        QCOMPARE(controller.imageHeight(), 20);
        QCOMPARE(controller.baseImage().size(), QSize(40, 20));
        QVERIFY(controller.dirty());
        QVERIFY(controller.canUndo());

        controller.undo();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(controller.imageWidth(), originalWidth);
        QCOMPARE(controller.baseImage().size(), QSize(20, 10));
    }

    void resizeImagePreservesAdjustments()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.beginAdjustment(QStringLiteral("exposure"));
        controller.previewAdjustment(QStringLiteral("exposure"), 40.0);
        controller.finishAdjustment(QStringLiteral("exposure"), 40.0);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto values = controller.adjustmentValues();

        controller.resizeImage(10, 5);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.errorMessage().isEmpty());
        QCOMPARE(controller.adjustmentValues(), values);
        QCOMPARE(controller.imageWidth(), 10);
    }

    void canvasExpansionUsesAnchorAndBackground()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);

        controller.resizeCanvas(30, 20, Qt::AlignLeft | Qt::AlignTop, QColor(255, 255, 255, 255));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.errorMessage().isEmpty());
        QCOMPARE(controller.imageWidth(), 30);
        QCOMPARE(controller.imageHeight(), 20);
        const auto image = controller.image();
        QCOMPARE(image.pixelColor(0, 0), QColor(220, 30, 30, 255));
        QCOMPARE(image.pixelColor(25, 15), QColor(255, 255, 255, 255));

        controller.undo();
        controller.resizeCanvas(40, 20, Qt::AlignRight | Qt::AlignBottom, QColor(0, 0, 0, 255));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto shifted = controller.image();
        QCOMPARE(shifted.size(), QSize(40, 20));
        QCOMPARE(shifted.pixelColor(39, 19), QColor(30, 30, 220, 255));
        QCOMPARE(shifted.pixelColor(0, 0), QColor(0, 0, 0, 255));
    }

    void canvasCanShrink()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.resizeCanvas(5, 5, Qt::AlignTop | Qt::AlignLeft, Qt::transparent);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.errorMessage().isEmpty());
        QCOMPARE(controller.imageWidth(), 5);
        QCOMPARE(controller.imageHeight(), 5);
    }

    void rejectsInvalidSizes()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.resizeImage(0, 10);
        QVERIFY(!controller.errorMessage().isEmpty());
        controller.clearError();
        controller.resizeCanvas(100000, 100000, Qt::AlignCenter, Qt::white);
        QVERIFY(!controller.errorMessage().isEmpty());
        QCOMPARE(controller.imageWidth(), 20);
    }
};

QTEST_MAIN(ResizeTest)
#include "tst_resize.moc"
