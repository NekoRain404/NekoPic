#include "app/documentcontroller.h"

#include <QImage>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

namespace {
QImage sourceImage()
{
    QImage image(64, 48, QImage::Format_RGBA64);
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            image.setPixelColor(x, y, QColor::fromRgba64(
                quint16(800 + x * 700), quint16(1200 + y * 900), quint16(3000 + (x + y) * 400),
                65535));
        }
    }
    return image;
}
} // namespace

class PreviewContractTest final : public QObject {
    Q_OBJECT
private slots:
    void exposesDistinctBaseAndRenderedUrls()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.imageUrl().toString().contains(QStringLiteral("current")));
        QVERIFY(controller.baseImageUrl().toString().contains(QStringLiteral("base")));
        QVERIFY(controller.baseImageUrl() != controller.imageUrl());
    }

    void pendingValuesTrackInteractiveDrag()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const QImage baseBefore = controller.baseImage();
        QSignalSpy previews(&controller, &DocumentController::adjustmentPreviewChanged);

        controller.beginAdjustment(QStringLiteral("exposure"));
        QVERIFY(previews.count() >= 1);
        QCOMPARE(qRound(controller.pendingAdjustmentValues().value(QStringLiteral("exposure")).toDouble()), 0);

        controller.previewAdjustment(QStringLiteral("exposure"), 50.0);
        QCOMPARE(qRound(controller.pendingAdjustmentValues().value(QStringLiteral("exposure")).toDouble()), 50);
        QCOMPARE(controller.adjustmentValues().value(QStringLiteral("exposure")).toDouble(), 0.0);
        QVERIFY(controller.baseImage() == baseBefore);

        controller.finishAdjustment(QStringLiteral("exposure"), 50.0);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(qRound(controller.adjustmentValues().value(QStringLiteral("exposure")).toDouble()), 50);
        QCOMPARE(qRound(controller.pendingAdjustmentValues().value(QStringLiteral("exposure")).toDouble()), 50);
        QVERIFY(controller.canUndo());
    }

    void baseUrlRevisionChangesAfterEdits()
    {
        QTemporaryDir dir;
        QVERIFY(sourceImage().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const QUrl before = controller.baseImageUrl();
        controller.flipHorizontal();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.baseImageUrl() != before);
    }
};

QTEST_MAIN(PreviewContractTest)
#include "tst_previewcontract.moc"
