#include "document/history.h"

#include <QImage>
#include <QtTest>

using NekoPic::Document::HistoryEntry;
using NekoPic::Document::HistoryStore;

namespace {
QImage solidImage(int size, QRgb color)
{
    QImage image(size, size, QImage::Format_RGBA8888);
    image.fill(color);
    return image;
}

HistoryEntry entry(const QImage &image, quint64 state)
{
    HistoryEntry result;
    result.image = image;
    result.state = state;
    return result;
}
} // namespace

class HistoryStoreTest final : public QObject {
    Q_OBJECT
private slots:
    void recordsUndoAndRedoStates()
    {
        HistoryStore history;
        history.record(entry(solidImage(8, qRgba(10, 0, 0, 255)), 1));
        history.record(entry(solidImage(8, qRgba(20, 0, 0, 255)), 2));
        QVERIFY(history.canUndo());
        QVERIFY(!history.canRedo());
        QCOMPARE(history.undoCount(), qsizetype(2));

        auto previous = history.undo(entry(solidImage(8, qRgba(30, 0, 0, 255)), 3));
        QVERIFY(previous);
        QCOMPARE(previous->state, quint64(2));
        QVERIFY(history.canRedo());
        QCOMPARE(history.redoCount(), qsizetype(1));

        auto next = history.redo(*previous);
        QVERIFY(next);
        QCOMPARE(next->state, quint64(3));
        QCOMPARE(history.undoCount(), qsizetype(2));
    }

    void newEditClearsRedoBranch()
    {
        HistoryStore history;
        history.record(entry(solidImage(8, qRgba(10, 0, 0, 255)), 1));
        history.record(entry(solidImage(8, qRgba(20, 0, 0, 255)), 2));
        auto previous = history.undo(entry(solidImage(8, qRgba(30, 0, 0, 255)), 3));
        QVERIFY(previous);
        QVERIFY(history.canRedo());
        history.record(entry(solidImage(8, qRgba(40, 0, 0, 255)), 4));
        QVERIFY(!history.canRedo());
        QCOMPARE(history.redoCount(), qsizetype(0));
    }

    void budgetEvictsOldestUndoEntries()
    {
        constexpr qsizetype imageBytes = 512 * 512 * 4;
        HistoryStore history(imageBytes * 2);
        history.record(entry(solidImage(512, qRgba(10, 0, 0, 255)), 1));
        history.record(entry(solidImage(512, qRgba(20, 0, 0, 255)), 2));
        QCOMPARE(history.undoCount(), qsizetype(2));
        history.record(entry(solidImage(512, qRgba(30, 0, 0, 255)), 3));
        QCOMPARE(history.undoCount(), qsizetype(2));
        QVERIFY(history.uniqueImageBytes() <= history.budgetBytes());
    }

    void sharedImagesCountOnce()
    {
        HistoryStore history;
        const QImage shared = solidImage(64, qRgba(10, 0, 0, 255));
        history.record(entry(shared, 1));
        history.record(entry(shared, 2));
        QCOMPARE(history.uniqueImageBytes(), shared.sizeInBytes());
    }

    void clearDropsBothStacks()
    {
        HistoryStore history;
        history.record(entry(solidImage(8, qRgba(10, 0, 0, 255)), 1));
        history.clear();
        QVERIFY(!history.canUndo());
        QVERIFY(!history.canRedo());
        QCOMPARE(history.uniqueImageBytes(), qsizetype(0));
    }
};

QTEST_MAIN(HistoryStoreTest)
#include "tst_history.moc"
