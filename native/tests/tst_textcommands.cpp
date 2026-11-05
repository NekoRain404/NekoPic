#include "app/documentcontroller.h"

#include <QColor>
#include <QFont>
#include <QImage>
#include <QTemporaryDir>
#include <QtTest>

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

QImage whiteImage(int width = 300, int height = 200)
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

int redPixels(const QImage &image)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            const QColor c = image.pixelColor(x, y);
            if (c.red() > 140 && c.green() < 110 && c.blue() < 110)
                ++count;
        }
    }
    return count;
}

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
                || std::abs(a.blue() - b.blue()) > tolerance) {
                ++different;
            }
        }
    }
    return different;
}

quint64 addStyled(DocumentController &controller, const QString &text, qreal x, qreal y,
                  qreal size, int alignment, const QColor &ink, const QColor &outline,
                  qreal outlineWidth, qreal lineHeight, qreal padding)
{
    controller.addTextStyled(text, x, y, QFont().family(), QFont::Normal, size, ink,
                             alignment, outline, outlineWidth, lineHeight, padding);
    if (!waitIdle(controller))
        return NekoPic::Document::InvalidObjectId;
    const QVariantList ids = controller.objectIds();
    if (ids.isEmpty())
        return NekoPic::Document::InvalidObjectId;
    return ids.last().toULongLong();
}

} // namespace

class TextCommandsTest final : public QObject {
    Q_OBJECT

private slots:
    void styledAddRendersAndUndoesOnce();
    void largerFontSizeGrowsBounds();
    void outlineChangesPixels();
    void invalidInputsAreNoOps();
    void anchorSemanticsForAlignments();
    void existingAddTextUnchanged();
};

void TextCommandsTest::styledAddRendersAndUndoesOnce()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));
    QVERIFY(!controller.hasObjects());

    const quint64 id = addStyled(controller, QStringLiteral("Styled"), 40.0, 40.0, 32.0,
                                 Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                 QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(id != NekoPic::Document::InvalidObjectId);
    QVERIFY(controller.hasObjects());
    QVERIFY(controller.dirty());
    QVERIFY(controller.canUndo());
    QCOMPARE(controller.objectIds().size(), 1);
    QVERIFY(controller.image() != source);
    QVERIFY2(darkPixels(controller.image()) > 100, "styled text produced no ink");
    QVERIFY(!controller.objectBounds(id).isEmpty());

    const QImage withText = controller.image();

    // One command, one undo entry.
    controller.undo();
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.image(), source);
    QVERIFY(!controller.canUndo());
    QVERIFY(controller.canRedo());

    controller.redo();
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.image(), withText);
    QCOMPARE(controller.objectIds().size(), 1);
}

void TextCommandsTest::largerFontSizeGrowsBounds()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 small = addStyled(controller, QStringLiteral("SIZE"), 30.0, 30.0, 20.0,
                                   Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                   QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(small != NekoPic::Document::InvalidObjectId);
    const QRectF smallBounds = controller.objectBounds(small);
    QVERIFY(!smallBounds.isEmpty());

    controller.undo();
    QVERIFY(!controller.hasObjects());

    const quint64 large = addStyled(controller, QStringLiteral("SIZE"), 30.0, 30.0, 60.0,
                                   Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                   QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(large != NekoPic::Document::InvalidObjectId);
    const QRectF largeBounds = controller.objectBounds(large);
    QVERIFY(!largeBounds.isEmpty());

    QVERIFY2(largeBounds.width() > smallBounds.width(),
             qPrintable(QStringLiteral("width %1 !> %2")
                            .arg(largeBounds.width()).arg(smallBounds.width())));
    QVERIFY2(largeBounds.height() > smallBounds.height(),
             qPrintable(QStringLiteral("height %1 !> %2")
                            .arg(largeBounds.height()).arg(smallBounds.height())));

    // Line height and padding are reflected in the box geometry too.
    controller.undo();
    const quint64 tall = addStyled(controller, QStringLiteral("SIZE"), 30.0, 30.0, 60.0,
                                   Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                   QColor(Qt::transparent), 0.0, 2.0, 20.0);
    QVERIFY(tall != NekoPic::Document::InvalidObjectId);
    const QRectF tallBounds = controller.objectBounds(tall);
    QVERIFY(tallBounds.height() > largeBounds.height());
    QVERIFY(tallBounds.width() > largeBounds.width());
}

void TextCommandsTest::outlineChangesPixels()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const quint64 plainId = addStyled(controller, QStringLiteral("OUTLINE"), 40.0, 60.0, 48.0,
                                     Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                     QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(plainId != NekoPic::Document::InvalidObjectId);
    const QImage plain = controller.image();
    QCOMPARE(redPixels(plain), 0);
    controller.undo();

    const quint64 outlinedId = addStyled(controller, QStringLiteral("OUTLINE"), 40.0, 60.0, 48.0,
                                        Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                                        QColor(Qt::red), 6.0, 1.0, 4.0);
    QVERIFY(outlinedId != NekoPic::Document::InvalidObjectId);
    const QImage outlined = controller.image();

    QVERIFY2(differentPixels(outlined, plain) > 0, "outline did not change the pixels");
    QVERIFY2(redPixels(outlined) > 0, "outline colour was not rendered");

    // Width 0 never draws the outline even when a colour is set.
    controller.undo();
    addStyled(controller, QStringLiteral("OUTLINE"), 40.0, 60.0, 48.0,
              Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black), QColor(Qt::red), 0.0, 1.0, 4.0);
    QCOMPARE(redPixels(controller.image()), 0);
}

void TextCommandsTest::invalidInputsAreNoOps()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    const qreal nan = std::numeric_limits<qreal>::quiet_NaN();
    const qreal inf = std::numeric_limits<qreal>::infinity();
    const QColor black(Qt::black);
    const QColor clear(Qt::transparent);
    const QString family = QFont().family();
    const int align = Qt::AlignLeft | Qt::AlignTop;

    const auto styled = [&](const QString &text, qreal x, qreal y, qreal size,
                            qreal outlineWidth, qreal lineHeight, qreal padding) {
        controller.addTextStyled(text, x, y, family, QFont::Normal, size, black, align,
                                 clear, outlineWidth, lineHeight, padding);
    };

    styled(QStringLiteral("   "), 10, 10, 20, 0, 1.0, 4.0);
    styled(QString(), 10, 10, 20, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), nan, 10, 20, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, inf, 20, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 1e30, 10, 20, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, -1e30, 20, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, 10, nan, 0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, -1.0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 65.0, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, nan, 1.0, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, 0.4, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, 4.1, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, nan, 4.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, 1.0, -1.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, 1.0, 257.0);
    styled(QStringLiteral("bad"), 10, 10, 20, 0, 1.0, nan);

    QVERIFY(!controller.busy());
    QVERIFY(!controller.canUndo());
    QVERIFY(!controller.hasObjects());
    QCOMPARE(controller.image(), source);

    // An invalid text colour falls back to black; an invalid outline colour
    // means no outline. The command itself is still valid.
    controller.addTextStyled(QStringLiteral("Fallback"), 30, 30, QString(), QFont::Normal,
                             36.0, QColor(), Qt::AlignLeft | Qt::AlignTop, QColor(), 2.0,
                             1.0, 4.0);
    QVERIFY(waitIdle(controller));
    QCOMPARE(controller.objectIds().size(), 1);
    QVERIFY(darkPixels(controller.image()) > 100);
    QCOMPARE(redPixels(controller.image()), 0);
}

void TextCommandsTest::anchorSemanticsForAlignments()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(whiteImage().save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    // Top-left anchor: ink falls to the right and below (100, 100).
    quint64 id = addStyled(controller, QStringLiteral("OBJECT"), 100.0, 100.0, 36.0,
                           Qt::AlignLeft | Qt::AlignTop, QColor(Qt::black),
                           QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(id != NekoPic::Document::InvalidObjectId);
    QRect bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(bounds.left() >= 99);
    QVERIFY(bounds.top() >= 99);
    QCOMPARE(controller.objectAt(90.0, 90.0), NekoPic::Document::InvalidObjectId);
    QVERIFY(controller.objectAt(110.0, 110.0) != NekoPic::Document::InvalidObjectId);
    controller.undo();

    // Bottom-right anchor: ink falls to the left and above (260, 160).
    id = addStyled(controller, QStringLiteral("OBJECT"), 260.0, 160.0, 36.0,
                   Qt::AlignRight | Qt::AlignBottom, QColor(Qt::black),
                   QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(id != NekoPic::Document::InvalidObjectId);
    bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(bounds.right() <= 260);
    QVERIFY(bounds.bottom() <= 160);
    QCOMPARE(controller.objectAt(280.0, 180.0), NekoPic::Document::InvalidObjectId);
    controller.undo();

    // Centre anchor: the box centre sits on (150, 100).
    id = addStyled(controller, QStringLiteral("OBJECT"), 150.0, 100.0, 36.0,
                   Qt::AlignHCenter | Qt::AlignVCenter, QColor(Qt::black),
                   QColor(Qt::transparent), 0.0, 1.0, 4.0);
    QVERIFY(id != NekoPic::Document::InvalidObjectId);
    bounds = inkBounds(controller.image());
    QVERIFY(!bounds.isEmpty());
    QVERIFY(std::abs(bounds.center().x() - 150) <= 12);
    QVERIFY(std::abs(bounds.center().y() - 100) <= 12);
    QCOMPARE(controller.objectAt(150.0, 100.0), id);
}

void TextCommandsTest::existingAddTextUnchanged()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = whiteImage();
    QVERIFY(source.save(dir.filePath(QStringLiteral("source.png"))));
    DocumentController controller;
    QVERIFY(openSource(controller, dir.filePath(QStringLiteral("source.png"))));

    controller.addText(QStringLiteral("Legacy"), 40.0, 40.0, 36.0, QColor(Qt::black),
                       Qt::AlignLeft | Qt::AlignTop);
    QVERIFY(waitIdle(controller));
    QVERIFY(controller.hasObjects());
    QCOMPARE(controller.objectIds().size(), 1);
    QVERIFY(darkPixels(controller.image()) > 100);
    QVERIFY(!controller.objectBounds(controller.objectIds().first().toULongLong()).isEmpty());

    controller.undo();
    QCOMPARE(controller.image(), source);
    QVERIFY(!controller.hasObjects());
}

QTEST_MAIN(TextCommandsTest)
#include "tst_textcommands.moc"
