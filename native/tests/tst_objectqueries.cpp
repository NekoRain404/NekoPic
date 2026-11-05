#include "app/documentcontroller.h"

#include <QTemporaryDir>
#include <QtTest>

class ObjectQueriesTest final : public QObject {
    Q_OBJECT
private slots:
    void reportsIdsAndBoundsForText()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(320, 200, QImage::Format_RGBA8888);
        image.fill(Qt::white);
        QVERIFY(image.save(dir.filePath(QStringLiteral("source.png"))));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath(QStringLiteral("source.png"))));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(!controller.hasObjects());
        QVERIFY(controller.objectIds().isEmpty());

        controller.addText(QStringLiteral("Hello"), 40, 30, 32, Qt::black,
                           Qt::AlignLeft | Qt::AlignTop);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.hasObjects());
        QCOMPARE(controller.objectIds().size(), 1);
        const auto id = controller.objectIds().first().toULongLong();
        QVERIFY(id != 0);
        const QRectF bounds = controller.objectBounds(id);
        QVERIFY(bounds.width() > 0);
        QVERIFY(bounds.height() > 0);
        QVERIFY(bounds.contains(QPointF(41, 31)));
        QCOMPARE(controller.objectAt(41, 31), id);
        QCOMPARE(controller.objectAt(200, 150), quint64(0));
        QVERIFY(controller.objectBounds(99999).isEmpty());

        QVERIFY(controller.removeObject(id));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(!controller.hasObjects());
        controller.undo();
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.hasObjects());
        QCOMPARE(controller.objectIds().size(), 1);
    }
};

QTEST_MAIN(ObjectQueriesTest)
#include "tst_objectqueries.moc"
