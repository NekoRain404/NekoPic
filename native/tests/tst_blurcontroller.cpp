#include "app/documentcontroller.h"

#include <QTemporaryDir>
#include <QtTest>

namespace {
QImage pattern()
{
    QImage image(200, 120, QImage::Format_RGBA8888);
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            image.setPixelColor(x, y, ((x / 4 + y / 4) % 2) ? QColor(230, 40, 40) : QColor(30, 40, 230));
        }
    }
    return image;
}
}

class BlurControllerTest final : public QObject {
    Q_OBJECT
private slots:
    void blursRectangleAndUndoes()
    {
        QTemporaryDir dir;
        QVERIFY(pattern().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto original = controller.image();
        const QRect area(40, 30, 80, 60);

        controller.blurRectangle(area, 8);
        QVERIFY(controller.busy());
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
        const auto blurred = controller.image();
        QVERIFY(blurred != original);
        QCOMPARE(blurred.pixelColor(2, 2), original.pixelColor(2, 2));
        QCOMPARE(blurred.pixelColor(180, 100), original.pixelColor(180, 100));
        QVERIFY(controller.canUndo());

        controller.undo();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(controller.image(), original);
    }

    void blurStrokeWorksAndPreservesObjects()
    {
        QTemporaryDir dir;
        QVERIFY(pattern().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.addText(QStringLiteral("Keep"), 20, 20, 24, Qt::black,
                           Qt::AlignLeft | Qt::AlignTop);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.hasObjects());
        const auto ids = controller.objectIds();

        const QVariantList points{QPointF(80, 60), QPointF(120, 60)};
        controller.blurStroke(points, 10);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
        QVERIFY(controller.hasObjects());
        QCOMPARE(controller.objectIds(), ids);
    }

    void rejectsInvalidRadiusAndArea()
    {
        QTemporaryDir dir;
        QVERIFY(pattern().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto original = controller.image();
        controller.blurRectangle(QRectF(10, 10, 20, 20), 0);
        QVERIFY(!controller.busy());
        QCOMPARE(controller.image(), original);
        controller.blurRectangle(QRectF(500, 500, 20, 20), 8);
        QVERIFY(!controller.busy());
        QCOMPARE(controller.image(), original);
        controller.blurStroke(QVariantList{}, 8);
        QVERIFY(!controller.busy());
    }
};

QTEST_MAIN(BlurControllerTest)
#include "tst_blurcontroller.moc"
