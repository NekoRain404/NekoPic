#include "app/documentcontroller.h"
#include "core/adjustments.h"

#include <QColor>
#include <QImage>
#include <QPainter>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

QImage whiteImage(int width = 200, int height = 120)
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

int darkPixels(const QImage &image, int threshold = 128)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qGray(image.pixel(x, y)) < threshold)
                ++count;
        }
    }
    return count;
}

// Bounding box of pixels darker than threshold; empty when there is no ink.
QRect inkBounds(const QImage &image, int threshold = 128)
{
    int minX = image.width();
    int minY = image.height();
    int maxX = -1;
    int maxY = -1;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qGray(image.pixel(x, y)) >= threshold)
                continue;
            minX = std::min(minX, x);
            minY = std::min(minY, y);
            maxX = std::max(maxX, x);
            maxY = std::max(maxY, y);
        }
    }
    if (maxX < minX || maxY < minY)
        return {};
    return QRect(QPoint(minX, minY), QPoint(maxX, maxY));
}

int differentPixels(const QImage &actual, const QImage &expected, int tolerance = 1)
{
    if (actual.size() != expected.size())
        return actual.width() * actual.height();
    int different = 0;
    for (int y = 0; y < actual.height(); ++y) {
        for (int x = 0; x < actual.width(); ++x) {
            const QColor a = actual.pixelColor(x, y);
            const QColor b = expected.pixelColor(x, y);
            if (std::abs(a.red() - b.red()) > tolerance
                || std::abs(a.green() - b.green()) > tolerance
                || std::abs(a.blue() - b.blue()) > tolerance
                || std::abs(a.alpha() - b.alpha()) > tolerance) {
                ++different;
            }
        }
    }
    return different;
}

QString diffMessage(int different, int total)
{
    return QStringLiteral("%1 of %2 pixels differ").arg(different).arg(total);
}

bool closeImage(const QImage &actual, const QImage &expected, int tolerance = 1)
{
    const int allowed = std::max(1, (expected.width() * expected.height()) / 500);
    return differentPixels(actual, expected, tolerance) <= allowed;
}

quint64 addText(DocumentController &controller, const QString &text, qreal x, qreal y,
                qreal size, int alignment = Qt::AlignLeft | Qt::AlignTop)
{
    controller.addText(text, x, y, size, QColor(Qt::black), alignment);
    if (!waitIdle(controller))
        return 0;
    return controller.objectAt(x + 10.0, y + 15.0);
}

} // namespace

class ObjectToolsTest final : public QObject {
    Q_OBJECT

private slots:
    void addTextRendersCommitsOnceAndUndoes();
    void objectQueriesAndMutations();
    void textSurvivesAdjustmentsFiltersAndUndo();
    void textAnchorAlignment();
    void fontSizeIsClampedAndInvalidInputIsRejected();
    void rotateAndFlipTransformObjectsWithPixels();
    void resizeImageScalesObjectGeometry();
    void resizeCanvasTranslatesObjectGeometry();
    void cropMovesAndRemovesObjects();
    void saveAsIncludesObjects();
    void historyRestoresExactObjectsAndImages();
    void invalidAndBusyCommandsDoNotEdit();
};

void ObjectToolsTest::addTextRendersCommitsOnceAndUndoes()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.objectAt(50.0, 55.0), quint64(0));

    QSignalSpy busy(&controller, &DocumentController::busyChanged);
    QSignalSpy changed(&controller, &DocumentController::documentChanged);
    controller.addText(QStringLiteral("Hello"), 40.0, 40.0, 36.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(controller.busy());
    QCOMPARE(controller.image(), source); // not committed until the worker finishes
    QVERIFY(!controller.hasObjects());
    QVERIFY(waitIdle(controller));
    QCOMPARE(busy.count(), 2);
    QVERIFY(changed.count() >= 1);

    QVERIFY(controller.hasObjects());
    QVERIFY(controller.dirty());
    QVERIFY(controller.canUndo());
    const QImage withText = controller.image();
    QVERIFY(withText != source);
    QVERIFY2(darkPixels(withText) > 100, "no text ink in the composited image");

    const quint64 id = controller.objectAt(50.0, 55.0);
    QVERIFY(id != NekoPic::Document::InvalidObjectId);
    QCOMPARE(controller.objectAt(190.0, 110.0), NekoPic::Document::InvalidObjectId);

    // One text command is exactly one undo step.
    controller.undo();
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.image(), source);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
    QVERIFY(controller.canRedo());

    controller.redo();
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), withText);
    // Snapshots preserve ids, so a selection made before undo stays valid.
    QCOMPARE(controller.objectAt(50.0, 55.0), id);
}

void ObjectToolsTest::objectQueriesAndMutations()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    QVERIFY(!controller.removeObject(NekoPic::Document::InvalidObjectId));
    QVERIFY(!controller.removeObject(123456));
    controller.clearObjects(); // no objects: no edit, no busy
    controller.moveObject(123456, 5.0, 5.0);
    QVERIFY(!controller.busy());
    QVERIFY(!controller.canUndo());
    QCOMPARE(controller.objectAt(std::numeric_limits<qreal>::quiet_NaN(), 5.0),
             NekoPic::Document::InvalidObjectId);

    const quint64 first = addText(controller, QStringLiteral("First"), 20.0, 20.0, 30.0);
    QVERIFY(first != 0);
    const quint64 second = addText(controller, QStringLiteral("Second"), 20.0, 70.0, 30.0);
    QVERIFY(second != 0);
    QVERIFY(first != second);
    QVERIFY(controller.hasObjects());

    // Unknown ids are rejected without producing history or busy state.
    QVERIFY(!controller.removeObject(999999));
    controller.moveObject(999999, 10.0, 10.0);
    QVERIFY(!controller.busy());

    const QImage beforeMove = controller.image();
    controller.moveObject(first, 100.0, 20.0);
    QVERIFY(controller.busy());
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectAt(30.0, 35.0), NekoPic::Document::InvalidObjectId);
    QCOMPARE(controller.objectAt(130.0, 55.0), first);
    QCOMPARE(controller.objectAt(30.0, 80.0), second);
    QVERIFY(controller.image() != beforeMove);

    controller.undo();
    QCOMPARE(controller.image(), beforeMove);
    QCOMPARE(controller.objectAt(30.0, 35.0), first);
    QCOMPARE(controller.objectAt(130.0, 55.0), NekoPic::Document::InvalidObjectId);

    // Removal leaves the other object intact and is undoable.
    QVERIFY(controller.removeObject(first));
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectAt(30.0, 35.0), NekoPic::Document::InvalidObjectId);
    QCOMPARE(controller.objectAt(30.0, 80.0), second);
    controller.undo();
    QCOMPARE(controller.objectAt(30.0, 35.0), first);

    // clearObjects is a single undo step that restores every object id.
    const QImage withBoth = controller.image();
    controller.clearObjects();
    QVERIFY(controller.busy());
    QVERIFY(waitIdle(controller));
    QVERIFY(!controller.hasObjects());
    controller.undo();
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), withBoth);
    QCOMPARE(controller.objectAt(30.0, 35.0), first);
    QCOMPARE(controller.objectAt(30.0, 80.0), second);
}

void ObjectToolsTest::textSurvivesAdjustmentsFiltersAndUndo()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Persistent"), 30.0, 30.0, 32.0);
    QVERIFY(id != 0);
    const QImage withText = controller.image();

    controller.beginAdjustment(QStringLiteral("brightness"));
    controller.finishAdjustment(QStringLiteral("brightness"), 30.0);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.objectAt(40.0, 45.0), id);
    QVERIFY2(darkPixels(controller.image(), 100) > 100, "text vanished after adjustment");
    const QImage adjusted = controller.image();
    QVERIFY(adjusted != withText);

    controller.selectFilter(QStringLiteral("warm"));
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.objectAt(40.0, 45.0), id);
    QVERIFY2(darkPixels(controller.image(), 100) > 100, "text vanished after filter");
    const QImage filtered = controller.image();
    QVERIFY(filtered != adjusted);

    // Pixel-only edits must not consume the object state.
    controller.undo(); // filter
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), adjusted);
    QCOMPARE(controller.objectAt(40.0, 45.0), id);

    controller.undo(); // adjustment
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), withText);

    controller.undo(); // text
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.image(), source);

    controller.redo();
    controller.redo();
    controller.redo();
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), filtered);
    QCOMPARE(controller.objectAt(40.0, 45.0), id);
}

void ObjectToolsTest::textAnchorAlignment()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(300, 200).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    // Top-left anchor: ink falls to the right and below (100, 100).
    const quint64 topLeft = addText(controller, QStringLiteral("OBJECT"), 100.0, 100.0, 36.0,
                                    Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(topLeft != 0);
    QRect bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(bounds.left() >= 99);
    QVERIFY(bounds.top() >= 99);
    QCOMPARE(controller.objectAt(90.0, 90.0), NekoPic::Document::InvalidObjectId);
    QCOMPARE(controller.objectAt(110.0, 110.0), topLeft);
    controller.undo();

    // Bottom-right anchor: ink falls to the left and above (260, 160).
    controller.addText(QStringLiteral("OBJECT"), 260.0, 160.0, 36.0, QColor(Qt::black),
                       Qt::AlignRight | Qt::AlignBottom);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    const quint64 bottomRight = controller.objectAt(200.0, 140.0);
    QVERIFY(bottomRight != 0);
    bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(bounds.right() <= 260);
    QVERIFY(bounds.bottom() <= 160);
    QCOMPARE(controller.objectAt(280.0, 180.0), NekoPic::Document::InvalidObjectId);
    QVERIFY(controller.objectAt(200.0, 140.0) != NekoPic::Document::InvalidObjectId);
    controller.undo();

    // Centre anchor: the box centre sits on the anchor.
    controller.addText(QStringLiteral("OBJECT"), 150.0, 100.0, 36.0, QColor(Qt::black),
                       Qt::AlignHCenter | Qt::AlignVCenter);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    const quint64 centred = controller.objectAt(150.0, 100.0);
    QVERIFY(centred != 0);
    bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(std::abs(bounds.center().x() - 150) <= 12);
    QVERIFY(std::abs(bounds.center().y() - 100) <= 12);
    QCOMPARE(controller.objectAt(150.0, 100.0), centred);
}

void ObjectToolsTest::fontSizeIsClampedAndInvalidInputIsRejected()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    controller.addText(QStringLiteral("   "), 10.0, 10.0, 20.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    controller.addText(QString(), 10.0, 10.0, 20.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    controller.addText(QStringLiteral("bad"), std::numeric_limits<qreal>::quiet_NaN(),
                       10.0, 20.0, QColor(Qt::black), Qt::AlignLeft | Qt::AlignTop);
    controller.addText(QStringLiteral("bad"), 1e30, 10.0, 20.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(!controller.busy());
    QVERIFY(!controller.canUndo());
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.image(), source);

    // Both extremes are clamped into [4, 512] and still render.
    controller.addText(QStringLiteral("Tiny"), 20.0, 20.0, 1.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    QVERIFY(differentPixels(controller.image(), source) > 0);
    controller.undo();

    controller.addText(QStringLiteral("Huge"), 100.0, 60.0, 10000.0, QColor(Qt::black),
                       Qt::AlignHCenter | Qt::AlignVCenter);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    QVERIFY(darkPixels(controller.image()) > 0);
}

void ObjectToolsTest::rotateAndFlipTransformObjectsWithPixels()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(160, 120).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Turn"), 30.0, 30.0, 36.0);
    QVERIFY(id != 0);
    const QImage original = controller.image();
    QCOMPARE(controller.objectAt(50.0, 55.0), id);

    // 90-degree rotations and flips map the pixel grid onto itself, so the
    // composited result must match transforming the rendered image.
    controller.rotateClockwise();
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.image().size(), QSize(120, 160));
    const QImage rotated = controller.image();
    const QImage expectedRotated = original.transformed(QTransform().rotate(90));
    QVERIFY2(closeImage(rotated, expectedRotated),
             qPrintable(diffMessage(differentPixels(rotated, expectedRotated),
                                    rotated.width() * rotated.height())));
    QCOMPARE(controller.objectAt(65.0, 50.0), id); // (x, y) -> (h - y, x)
    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.objectAt(50.0, 55.0), id);

    controller.flipHorizontal();
    QVERIFY(waitIdle(controller));
    const QImage flipped = controller.image();
    const QImage expectedFlipped = original.transformed(QTransform().scale(-1.0, 1.0));
    QVERIFY2(closeImage(flipped, expectedFlipped),
             qPrintable(diffMessage(differentPixels(flipped, expectedFlipped),
                                    flipped.width() * flipped.height())));
    QCOMPARE(controller.objectAt(110.0, 55.0), id); // (x, y) -> (w - x, y)
    controller.undo();
    QCOMPARE(controller.image(), original);

    controller.flipVertical();
    QVERIFY(waitIdle(controller));
    const QImage flippedVertical = controller.image();
    const QImage expectedVertical = original.transformed(QTransform().scale(1.0, -1.0));
    QVERIFY2(closeImage(flippedVertical, expectedVertical),
             qPrintable(diffMessage(differentPixels(flippedVertical, expectedVertical),
                                    flippedVertical.width() * flippedVertical.height())));
    QCOMPARE(controller.objectAt(50.0, 65.0), id); // (x, y) -> (x, h - y)
    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.objectAt(50.0, 55.0), id);
}

void ObjectToolsTest::resizeImageScalesObjectGeometry()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(160, 120).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Scale"), 30.0, 30.0, 32.0);
    QVERIFY(id != 0);
    const QImage original = controller.image();

    controller.resizeImage(320, 240);
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.image().size(), QSize(320, 240));
    QVERIFY(controller.hasObjects());
    // Hit point (50, 55) scales to (100, 110).
    QCOMPARE(controller.objectAt(100.0, 110.0), id);
    QCOMPARE(controller.objectAt(50.0, 55.0), NekoPic::Document::InvalidObjectId);
    QVERIFY2(darkPixels(controller.image(), 100) > 100, "text disappeared during resize");

    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.objectAt(50.0, 55.0), id);
}

void ObjectToolsTest::resizeCanvasTranslatesObjectGeometry()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(160, 120).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Canvas"), 20.0, 25.0, 24.0);
    QVERIFY(id != 0);
    const QImage original = controller.image();

    // Centring a 160x120 image in 240x200 offsets it by (40, 40).
    controller.resizeCanvas(240, 200, Qt::AlignCenter, QColor(Qt::white));
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.image().size(), QSize(240, 200));
    QCOMPARE(controller.objectAt(70.0, 80.0), id); // (30, 40) + (40, 40)
    QCOMPARE(controller.objectAt(30.0, 40.0), NekoPic::Document::InvalidObjectId);

    QImage expected(240, 200, original.format());
    expected.fill(Qt::white);
    {
        QPainter painter(&expected);
        painter.drawImage(40, 40, original);
    }
    QVERIFY2(closeImage(controller.image(), expected),
             qPrintable(diffMessage(differentPixels(controller.image(), expected),
                                    expected.width() * expected.height())));

    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.objectAt(30.0, 40.0), id);
}

void ObjectToolsTest::cropMovesAndRemovesObjects()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(160, 120).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 kept = addText(controller, QStringLiteral("Kept"), 30.0, 30.0, 30.0);
    const quint64 dropped = addText(controller, QStringLiteral("Dropped"), 120.0, 95.0, 30.0);
    QVERIFY(kept != 0);
    QVERIFY(dropped != 0);
    const QImage original = controller.image();

    controller.cropImage(QRectF(20.0, 20.0, 80.0, 60.0));
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.image().size(), QSize(80, 60));
    QVERIFY(controller.hasObjects());
    // Survivor translated by -kept.topLeft(); the out-of-crop object is gone.
    QCOMPARE(controller.objectAt(30.0, 35.0), kept); // (50, 55) - (20, 20)
    QCOMPARE(controller.objectAt(110.0, 85.0), NekoPic::Document::InvalidObjectId);

    const QImage expected = original.copy(20, 20, 80, 60);
    QVERIFY2(closeImage(controller.image(), expected),
             qPrintable(diffMessage(differentPixels(controller.image(), expected),
                                    expected.width() * expected.height())));

    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.objectAt(50.0, 55.0), kept);
    QCOMPARE(controller.objectAt(130.0, 110.0), dropped);
}

void ObjectToolsTest::saveAsIncludesObjects()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 id = addText(controller, QStringLiteral("Saved"), 25.0, 25.0, 40.0);
    QVERIFY(id != 0);
    const QImage composited = controller.image();
    const int inkBeforeSave = darkPixels(composited);
    QVERIFY(inkBeforeSave > 100);

    const QString target = dir.filePath(QStringLiteral("saved.png"));
    controller.saveAs(QUrl::fromLocalFile(target), QStringLiteral("png"));
    QVERIFY(waitIdle(controller));
    QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
    QVERIFY(!controller.dirty());
    QVERIFY(controller.canUndo());

    QImage saved(target);
    QVERIFY(!saved.isNull());
    QCOMPARE(saved.size(), composited.size());
    QVERIFY2(darkPixels(saved) > 100, "saved file does not contain the text ink");
    QVERIFY2(closeImage(saved, composited),
             qPrintable(diffMessage(differentPixels(saved, composited),
                                    composited.width() * composited.height())));

    // Saving is a history checkpoint, not an object reset.
    controller.undo();
    QVERIFY(!controller.hasObjects());
    QVERIFY(controller.dirty());
    controller.redo();
    QVERIFY(controller.hasObjects());
    QVERIFY(!controller.dirty());
    QCOMPARE(controller.image(), composited);
}

void ObjectToolsTest::historyRestoresExactObjectsAndImages()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage(220, 140).save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 first = addText(controller, QStringLiteral("Alpha"), 20.0, 20.0, 30.0);
    const quint64 second = addText(controller, QStringLiteral("Beta"), 20.0, 80.0, 30.0);
    QVERIFY(first != 0);
    QVERIFY(second != 0);
    QVERIFY(first != second);
    const QImage both = controller.image();

    QVERIFY(controller.removeObject(first));
    QVERIFY(waitIdle(controller));
    const QImage onlySecond = controller.image();
    QVERIFY(onlySecond != both);

    // Repeated undo/redo cycles exercise the shared immutable snapshots.
    for (int cycle = 0; cycle < 3; ++cycle) {
        controller.undo();
        QCOMPARE(controller.image(), both);
        QCOMPARE(controller.objectAt(30.0, 35.0), first);
        QCOMPARE(controller.objectAt(30.0, 95.0), second);
        controller.redo();
        QCOMPARE(controller.image(), onlySecond);
        QCOMPARE(controller.objectAt(30.0, 35.0), NekoPic::Document::InvalidObjectId);
        QCOMPARE(controller.objectAt(30.0, 95.0), second);
    }

    controller.undo();
    controller.moveObject(second, 100.0, 0.0);
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectAt(130.0, 95.0), second);
    controller.undo();
    QCOMPARE(controller.objectAt(30.0, 95.0), second);
    QCOMPARE(controller.objectAt(130.0, 95.0), NekoPic::Document::InvalidObjectId);
}

void ObjectToolsTest::invalidAndBusyCommandsDoNotEdit()
{
    // No image: every command is a safe no-op.
    DocumentController empty;
    empty.addText(QStringLiteral("x"), 0.0, 0.0, 20.0, QColor(Qt::black),
                  Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(!empty.removeObject(1));
    empty.clearObjects();
    empty.moveObject(1, 1.0, 1.0);
    QCOMPARE(empty.objectAt(0.0, 0.0), NekoPic::Document::InvalidObjectId);
    QVERIFY(!empty.busy());

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    // A second command while the first renders is ignored; the first remains
    // exactly one undo step.
    controller.addText(QStringLiteral("First"), 20.0, 20.0, 30.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(controller.busy());
    controller.addText(QStringLiteral("Second"), 120.0, 20.0, 30.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    controller.undo();
    QVERIFY(!controller.hasObjects());
    QVERIFY(!controller.canUndo());
    QCOMPARE(controller.image(), source);

    QVERIFY(!controller.removeObject(NekoPic::Document::InvalidObjectId));
    controller.moveObject(NekoPic::Document::InvalidObjectId, 3.0, 4.0);
    controller.moveObject(42, std::numeric_limits<qreal>::infinity(), 0.0);
    QVERIFY(!controller.busy());
    QVERIFY(!controller.canUndo());
    QCOMPARE(controller.image(), source);
}

QTEST_MAIN(ObjectToolsTest)
#include "tst_objecttools.moc"
