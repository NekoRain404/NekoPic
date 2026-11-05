#include "app/documentcontroller.h"

#include <QColor>
#include <QCoreApplication>
#include <QImage>
#include <QTemporaryDir>
#include <QtTest>

#include <cmath>
#include <limits>

namespace {

QImage whiteImage(int width = 320, int height = 240)
{
    QImage image(width, height, QImage::Format_RGB32);
    image.fill(Qt::white);
    return image;
}

bool openSource(DocumentController &controller, const QString &path)
{
    controller.openImage(QUrl::fromLocalFile(path));
    return QTest::qWaitFor([&controller] { return !controller.busy(); }, 10000);
}

bool waitIdle(DocumentController &controller)
{
    return QTest::qWaitFor([&controller] { return !controller.busy(); }, 10000);
}

quint64 lastObjectId(const DocumentController &controller)
{
    const QVariantList ids = controller.objectIds();
    return ids.isEmpty() ? 0 : ids.last().toULongLong();
}

quint64 addText(DocumentController &controller, const QString &text, qreal x, qreal y)
{
    controller.addText(text, x, y, 28.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    if (!waitIdle(controller))
        return 0;
    return lastObjectId(controller);
}

quint64 addShape(DocumentController &controller, const QRectF &rect)
{
    controller.addShape(QStringLiteral("rectangle"), rect, QColor(Qt::transparent),
                        QColor(Qt::black), 2.0, 0.0);
    if (!waitIdle(controller))
        return 0;
    return lastObjectId(controller);
}

quint64 addStroke(DocumentController &controller)
{
    QVariantList points;
    points.append(QVariant::fromValue(QPointF(30, 30)));
    points.append(QVariant::fromValue(QPointF(90, 60)));
    points.append(QVariant::fromValue(QPointF(120, 90)));
    controller.addBrushStroke(points, 8.0, QColor(Qt::black));
    if (!waitIdle(controller))
        return 0;
    return lastObjectId(controller);
}

QVariantMap summaryFor(const DocumentController &controller, quint64 id)
{
    const QVariantList summaries = controller.objectSummaries();
    for (const QVariant &value : summaries) {
        const QVariantMap summary = value.toMap();
        if (summary.value(QStringLiteral("id")).toULongLong() == id)
            return summary;
    }
    return {};
}

QList<quint64> summaryIds(const DocumentController &controller)
{
    QList<quint64> ids;
    const QVariantList summaries = controller.objectSummaries();
    for (const QVariant &value : summaries)
        ids.append(value.toMap().value(QStringLiteral("id")).toULongLong());
    return ids;
}

bool roughly(qreal a, qreal b, qreal tolerance = 0.01)
{
    return std::abs(a - b) <= tolerance;
}

} // namespace

class ObjectManagementTest final : public QObject {
    Q_OBJECT

private slots:
    void summariesDescribeEveryKindTopmostFirst();
    void visibilityAndLockRoundTrip();
    void zOrderCommandsMoveOneStepOrToEnds();
    void groupMoveIsOneUndoStep();
    void groupRemoveIsOneUndoStep();
    void alignMovesToImageEdgesAndCentre();
    void invalidInputsAreSafeNoOps();
    void busyCommandsDoNotStartEdits();
    void undoRestoresSummaryStateAndOrder();
};

void ObjectManagementTest::summariesDescribeEveryKindTopmostFirst()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    QVERIFY(controller.objectSummaries().isEmpty());

    const quint64 text = addText(controller, QStringLiteral("Hello layer"), 20, 20);
    const quint64 shape = addShape(controller, QRectF(100, 80, 60, 40));
    const quint64 stroke = addStroke(controller);
    QVERIFY(text != 0);
    QVERIFY(shape != 0);
    QVERIFY(stroke != 0);

    // Topmost first: the last added object (stroke) leads the list.
    QCOMPARE(summaryIds(controller), (QList<quint64>{stroke, shape, text}));

    const QVariantMap textSummary = summaryFor(controller, text);
    QCOMPARE(textSummary.value(QStringLiteral("kind")).toString(), QStringLiteral("text"));
    QCOMPARE(textSummary.value(QStringLiteral("name")).toString(),
             QStringLiteral("Hello layer"));
    QCOMPARE(textSummary.value(QStringLiteral("visible")).toBool(), true);
    QCOMPARE(textSummary.value(QStringLiteral("locked")).toBool(), false);
    const QRectF textBounds = textSummary.value(QStringLiteral("bounds")).toRectF();
    QCOMPARE(textBounds, controller.objectBounds(text));

    const QVariantMap shapeSummary = summaryFor(controller, shape);
    QCOMPARE(shapeSummary.value(QStringLiteral("kind")).toString(), QStringLiteral("shape"));
    QCOMPARE(shapeSummary.value(QStringLiteral("name")).toString(),
             QCoreApplication::translate("DocumentController", "Rectangle"));

    const QVariantMap strokeSummary = summaryFor(controller, stroke);
    QCOMPARE(strokeSummary.value(QStringLiteral("kind")).toString(), QStringLiteral("stroke"));
    QCOMPARE(strokeSummary.value(QStringLiteral("name")).toString(),
             QCoreApplication::translate("DocumentController", "Stroke"));

    // Long text is previewed, not dumped in full.
    const quint64 longText = addText(controller,
                                     QStringLiteral("This is a deliberately long object name "
                                                    "that should be truncated"),
                                     20, 120);
    QVERIFY(longText != 0);
    const QString preview = summaryFor(controller, longText)
                                    .value(QStringLiteral("name")).toString();
    QVERIFY(preview.size() <= 32);
    QVERIFY(preview.endsWith(QChar(0x2026)));

    // Summaries are a pure query.
    QCOMPARE(controller.objectSummaries().size(), 4);
    QCOMPARE(controller.objectSummaries().size(), 4);
}

void ObjectManagementTest::visibilityAndLockRoundTrip()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Toggle me"), 30, 30);
    QVERIFY(id != 0);

    QVERIFY(!controller.setObjectVisible(id, true)); // already visible: no edit
    QVERIFY(!controller.busy());
    QVERIFY(controller.setObjectVisible(id, false));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("visible")).toBool(), false);
    // Hidden objects are not hit-testable anymore.
    QCOMPARE(controller.objectAt(40, 40), quint64(0));
    QVERIFY(!controller.setObjectVisible(id, false)); // already hidden: no edit

    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("visible")).toBool(), true);
    QCOMPARE(controller.objectAt(40, 40), id);

    QVERIFY(controller.setObjectVisible(id, false));
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.setObjectVisible(id, true));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("visible")).toBool(), true);

    QVERIFY(!controller.setObjectLocked(id, false)); // already unlocked: no edit
    QVERIFY(controller.setObjectLocked(id, true));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("locked")).toBool(), true);
    QCOMPARE(controller.objectAt(40, 40), quint64(0)); // locked objects are skipped
    QVERIFY(!controller.setObjectLocked(id, true));

    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("locked")).toBool(), false);
    QCOMPARE(controller.objectAt(40, 40), id);
}

void ObjectManagementTest::zOrderCommandsMoveOneStepOrToEnds()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 a = addText(controller, QStringLiteral("A"), 20, 20);
    const quint64 b = addText(controller, QStringLiteral("B"), 20, 70);
    const quint64 c = addText(controller, QStringLiteral("C"), 20, 120);
    QVERIFY(a != 0 && b != 0 && c != 0);

    // objectIds is bottom-to-top; summaries are topmost-first.
    QCOMPARE(controller.objectIds(), (QVariantList{
                 QVariant::fromValue<qulonglong>(a),
                 QVariant::fromValue<qulonglong>(b),
                 QVariant::fromValue<qulonglong>(c)}));
    QCOMPARE(summaryIds(controller), (QList<quint64>{c, b, a}));

    QVERIFY(controller.sendObjectToBack(c));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{b, a, c}));

    QVERIFY(controller.bringObjectToFront(a));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{a, b, c}));

    QVERIFY(controller.raiseObject(c));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{a, c, b}));

    QVERIFY(controller.lowerObject(a));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{c, a, b}));

    // Boundary and unknown-id commands are no-ops without busy/history.
    const bool couldUndo = controller.canUndo();
    QVERIFY(!controller.raiseObject(c));      // already topmost
    QVERIFY(!controller.bringObjectToFront(c));
    QVERIFY(!controller.lowerObject(b));      // already bottom
    QVERIFY(!controller.sendObjectToBack(b));
    QVERIFY(!controller.raiseObject(999999));
    QVERIFY(!controller.lowerObject(0));
    QVERIFY(!controller.busy());
    QCOMPARE(controller.canUndo(), couldUndo);
    QCOMPARE(summaryIds(controller), (QList<quint64>{c, a, b}));
}

void ObjectManagementTest::groupMoveIsOneUndoStep()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 first = addText(controller, QStringLiteral("First"), 20, 20);
    const quint64 second = addText(controller, QStringLiteral("Second"), 20, 80);
    QVERIFY(first != 0 && second != 0);

    const QRectF beforeFirst = controller.objectBounds(first);
    const QRectF beforeSecond = controller.objectBounds(second);

    // A duplicate id collapses; an unknown id is ignored.
    QVariantList ids;
    ids << QVariant::fromValue<qulonglong>(first)
        << QVariant::fromValue<qulonglong>(second)
        << QVariant::fromValue<qulonglong>(first)
        << 999999;
    QVERIFY(controller.moveObjects(ids, 12.5, -7.0));
    QVERIFY(controller.busy());
    QVERIFY(waitIdle(controller));

    const QRectF afterFirst = controller.objectBounds(first);
    const QRectF afterSecond = controller.objectBounds(second);
    QVERIFY(roughly(afterFirst.x(), beforeFirst.x() + 12.5));
    QVERIFY(roughly(afterFirst.y(), beforeFirst.y() - 7.0));
    QVERIFY(roughly(afterSecond.x(), beforeSecond.x() + 12.5));
    QVERIFY(roughly(afterSecond.y(), beforeSecond.y() - 7.0));
    QCOMPARE(controller.objectSummaries().size(), 2);

    // One undo restores both objects.
    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectBounds(first), beforeFirst);
    QCOMPARE(controller.objectBounds(second), beforeSecond);

    // A zero delta and an empty/unknown-only list never start an edit.
    QVERIFY(!controller.moveObjects(ids, 0.0, 0.0));
    QVERIFY(!controller.moveObjects({}, 5.0, 5.0));
    QVERIFY(!controller.moveObjects(QVariantList{999999}, 5.0, 5.0));
    QVERIFY(!controller.moveObjects(ids, std::numeric_limits<qreal>::infinity(), 0.0));
    QVERIFY(!controller.busy());
}

void ObjectManagementTest::groupRemoveIsOneUndoStep()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 first = addText(controller, QStringLiteral("First"), 20, 20);
    const quint64 second = addShape(controller, QRectF(120, 100, 50, 40));
    const quint64 keep = addStroke(controller);
    QVERIFY(first != 0 && second != 0 && keep != 0);

    QVariantList ids;
    ids << QVariant::fromValue<qulonglong>(first)
        << QVariant::fromValue<qulonglong>(second)
        << QVariant::fromValue<qulonglong>(first);
    QVERIFY(controller.removeObjects(ids));
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectSummaries().size(), 1);
    QCOMPARE(summaryIds(controller), (QList<quint64>{keep}));
    QCOMPARE(controller.objectBounds(first), QRectF());
    QCOMPARE(controller.objectBounds(second), QRectF());

    // One undo brings both objects back; the untouched object is unchanged.
    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectSummaries().size(), 3);
    QVERIFY(controller.objectBounds(first).width() > 0);
    QVERIFY(controller.objectBounds(second).width() > 0);
    QCOMPARE(summaryIds(controller), (QList<quint64>{keep, second, first}));

    QVERIFY(!controller.removeObjects({}));
    QVERIFY(!controller.removeObjects(QVariantList{999999}));
    QVERIFY(!controller.busy());
}

void ObjectManagementTest::alignMovesToImageEdgesAndCentre()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage(320, 240);
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 first = addText(controller, QStringLiteral("First"), 40, 40);
    const quint64 second = addShape(controller, QRectF(180, 140, 60, 40));
    QVERIFY(first != 0 && second != 0);
    const QVariantList ids{QVariant::fromValue<qulonglong>(first),
                           QVariant::fromValue<qulonglong>(second)};

    auto boundsOf = [&controller](quint64 id) { return controller.objectBounds(id); };

    QVERIFY(controller.alignObjects(ids, Qt::AlignLeft));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).left(), 0.0));
    QVERIFY(roughly(boundsOf(second).left(), 0.0));

    QVERIFY(controller.alignObjects(ids, Qt::AlignRight));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).right(), 320.0));
    QVERIFY(roughly(boundsOf(second).right(), 320.0));

    QVERIFY(controller.alignObjects(ids, Qt::AlignHCenter));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).center().x(), 160.0));
    QVERIFY(roughly(boundsOf(second).center().x(), 160.0));

    QVERIFY(controller.alignObjects(ids, Qt::AlignTop));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).top(), 0.0));
    QVERIFY(roughly(boundsOf(second).top(), 0.0));

    QVERIFY(controller.alignObjects(ids, Qt::AlignBottom));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).bottom(), 240.0));
    QVERIFY(roughly(boundsOf(second).bottom(), 240.0));

    QVERIFY(controller.alignObjects(ids, Qt::AlignVCenter));
    QVERIFY(waitIdle(controller));
    QVERIFY(roughly(boundsOf(first).center().y(), 120.0));
    QVERIFY(roughly(boundsOf(second).center().y(), 120.0));

    // No flags, unknown ids and already-aligned objects are no-ops.
    QVERIFY(!controller.alignObjects(ids, 0));
    QVERIFY(!controller.alignObjects(QVariantList{999999}, Qt::AlignLeft));
    QVERIFY(!controller.alignObjects(ids, Qt::AlignHCenter)); // already centred
    QVERIFY(!controller.busy());
}

void ObjectManagementTest::invalidInputsAreSafeNoOps()
{
    // No image: every command is a safe no-op.
    DocumentController empty;
    QVERIFY(empty.objectSummaries().isEmpty());
    QVERIFY(!empty.setObjectVisible(1, false));
    QVERIFY(!empty.setObjectLocked(1, true));
    QVERIFY(!empty.raiseObject(1));
    QVERIFY(!empty.lowerObject(1));
    QVERIFY(!empty.bringObjectToFront(1));
    QVERIFY(!empty.sendObjectToBack(1));
    QVERIFY(!empty.removeObjects(QVariantList{1}));
    QVERIFY(!empty.moveObjects(QVariantList{1}, 5.0, 5.0));
    QVERIFY(!empty.alignObjects(QVariantList{1}, Qt::AlignLeft));
    QVERIFY(!empty.busy());

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Object"), 20, 20);
    QVERIFY(id != 0);

    QVERIFY(!controller.setObjectVisible(0, false));
    QVERIFY(!controller.setObjectVisible(999999, false));
    QVERIFY(!controller.setObjectLocked(0, true));
    QVERIFY(!controller.setObjectLocked(999999, true));
    QVERIFY(!controller.raiseObject(999999));
    QVERIFY(!controller.removeObjects(QVariantList{0, -1, 999999}));
    QVERIFY(!controller.moveObjects(QVariantList{0, 999999}, 2.0, 2.0));
    QVERIFY(!controller.moveObjects(QVariantList{id}, std::numeric_limits<qreal>::quiet_NaN(), 1.0));
    QVERIFY(!controller.moveObjects(QVariantList{id}, 1e8, 0.0));
    QVERIFY(!controller.alignObjects(QVariantList{0, 999999}, Qt::AlignLeft));
    QVERIFY(!controller.busy());
    QVERIFY(!controller.objectSummaries().isEmpty());
}

void ObjectManagementTest::busyCommandsDoNotStartEdits()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Existing"), 20, 20);
    QVERIFY(id != 0);
    const QVariantList ids{QVariant::fromValue<qulonglong>(id)};
    const QRectF before = controller.objectBounds(id);

    controller.addText(QStringLiteral("Pending"), 100, 100, 24, Qt::black,
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(controller.busy());
    QVERIFY(!controller.setObjectVisible(id, false));
    QVERIFY(!controller.setObjectLocked(id, true));
    QVERIFY(!controller.raiseObject(id));
    QVERIFY(!controller.lowerObject(id));
    QVERIFY(!controller.bringObjectToFront(id));
    QVERIFY(!controller.sendObjectToBack(id));
    QVERIFY(!controller.removeObjects(ids));
    QVERIFY(!controller.moveObjects(ids, 10.0, 10.0));
    QVERIFY(!controller.alignObjects(ids, Qt::AlignLeft));
    QVERIFY(waitIdle(controller));

    // Only the pending add was committed; the rejected commands left no trace.
    QCOMPARE(controller.objectSummaries().size(), 2);
    QCOMPARE(controller.objectBounds(id), before);
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("visible")).toBool(), true);
    QCOMPARE(summaryFor(controller, id).value(QStringLiteral("locked")).toBool(), false);
}

void ObjectManagementTest::undoRestoresSummaryStateAndOrder()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 bottom = addText(controller, QStringLiteral("Bottom"), 20, 20);
    const quint64 top = addShape(controller, QRectF(80, 60, 50, 40));
    QVERIFY(bottom != 0 && top != 0);
    QCOMPARE(summaryIds(controller), (QList<quint64>{top, bottom}));

    QVERIFY(controller.bringObjectToFront(bottom));
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{bottom, top}));
    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryIds(controller), (QList<quint64>{top, bottom}));

    QVERIFY(controller.setObjectVisible(top, false));
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.setObjectLocked(bottom, true));
    QVERIFY(waitIdle(controller));
    controller.undo(); // unlock bottom
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, bottom).value(QStringLiteral("locked")).toBool(), false);
    QCOMPARE(summaryFor(controller, top).value(QStringLiteral("visible")).toBool(), false);
    controller.undo(); // show top
    QVERIFY(waitIdle(controller));
    QCOMPARE(summaryFor(controller, top).value(QStringLiteral("visible")).toBool(), true);

    // A group move after all that still restores cleanly in one step.
    const QRectF topBefore = controller.objectBounds(top);
    const QRectF bottomBefore = controller.objectBounds(bottom);
    QVERIFY(controller.moveObjects(QVariantList{QVariant::fromValue<qulonglong>(top),
                                                QVariant::fromValue<qulonglong>(bottom)},
                                   4.0, 6.0));
    QVERIFY(waitIdle(controller));
    controller.undo();
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectBounds(top), topBefore);
    QCOMPARE(controller.objectBounds(bottom), bottomBefore);
    QCOMPARE(summaryIds(controller), (QList<quint64>{top, bottom}));
}

QTEST_MAIN(ObjectManagementTest)
#include "tst_objectmanagement.moc"
