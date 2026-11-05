#include "app/documentcontroller.h"

#include <QTemporaryDir>
#include <QtTest>

namespace {
QImage canvas()
{
    QImage image(240, 160, QImage::Format_RGBA8888);
    image.fill(Qt::white);
    return image;
}
}

class DrawCommandsTest final : public QObject {
    Q_OBJECT
private slots:
    void brushStrokeCreatesUndoableInk()
    {
        QTemporaryDir dir;
        QVERIFY(canvas().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto original = controller.image();
        const QVariantList points{QPointF(30, 30), QPointF(90, 70), QPointF(150, 40)};
        controller.addBrushStroke(points, 12.0, QColor(220, 20, 20));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.hasObjects());
        QCOMPARE(controller.objectIds().size(), 1);
        QVERIFY(controller.image() != original);
        const auto id = controller.objectIds().first().toULongLong();
        QVERIFY(controller.objectBounds(id).width() > 0);
        controller.undo();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(!controller.hasObjects());
        QCOMPARE(controller.image(), original);
    }

    void shapesRenderAndUndo()
    {
        QTemporaryDir dir;
        QVERIFY(canvas().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.addShape(QStringLiteral("rectangle"), QRectF(20, 20, 80, 50),
                            QColor(255, 200, 0, 180), QColor(0, 0, 0), 3.0, 8.0);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
        QVERIFY(controller.hasObjects());
        controller.addShape(QStringLiteral("arrow"), QRectF(120, 30, 70, 60),
                            Qt::transparent, QColor(0, 120, 220), 4.0, 0.0);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(controller.objectIds().size(), 2);
        controller.undo();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(controller.objectIds().size(), 1);
    }

    void invalidDrawCommandsAreNoOps()
    {
        QTemporaryDir dir;
        QVERIFY(canvas().save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.addBrushStroke(QVariantList{}, 10, Qt::black);
        QVERIFY(!controller.busy());
        controller.addBrushStroke(QVariantList{QPointF(1, 1)}, 0, Qt::black);
        QVERIFY(!controller.busy());
        controller.addShape(QStringLiteral("triangle"), QRectF(0, 0, 10, 10), Qt::red, Qt::black, 2, 0);
        QVERIFY(!controller.busy());
        controller.addShape(QStringLiteral("rectangle"), QRectF(0, 0, 0, 10), Qt::red, Qt::black, 2, 0);
        QVERIFY(!controller.busy());
        QVERIFY(!controller.hasObjects());
    }
};

QTEST_MAIN(DrawCommandsTest)
#include "tst_drawcommands.moc"
