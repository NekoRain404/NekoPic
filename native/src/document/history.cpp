#include "history.h"

#include <QSet>

namespace NekoPic::Document {

HistoryStore::HistoryStore(qsizetype budgetBytes)
    : budgetBytes_(budgetBytes > 0 ? budgetBytes : DefaultBudgetBytes)
{
}

void HistoryStore::record(HistoryEntry entry)
{
    undo_.append(std::move(entry));
    redo_.clear();
    trim();
}

std::optional<HistoryEntry> HistoryStore::undo(HistoryEntry current)
{
    if (undo_.isEmpty()) return std::nullopt;
    redo_.append(std::move(current));
    auto previous = undo_.takeLast();
    return previous;
}

std::optional<HistoryEntry> HistoryStore::redo(HistoryEntry current)
{
    if (redo_.isEmpty()) return std::nullopt;
    undo_.append(std::move(current));
    auto next = redo_.takeLast();
    return next;
}

void HistoryStore::clear()
{
    undo_.clear();
    redo_.clear();
}

bool HistoryStore::canUndo() const { return !undo_.isEmpty(); }
bool HistoryStore::canRedo() const { return !redo_.isEmpty(); }
qsizetype HistoryStore::undoCount() const { return undo_.size(); }
qsizetype HistoryStore::redoCount() const { return redo_.size(); }
qsizetype HistoryStore::budgetBytes() const { return budgetBytes_; }

qsizetype HistoryStore::uniqueImageBytes() const
{
    return uniqueBytes(undo_) + uniqueBytes(redo_);
}

qsizetype HistoryStore::uniqueBytes(const QList<HistoryEntry> &entries) const
{
    QSet<qint64> seen;
    qsizetype bytes = 0;
    const auto count = [&seen, &bytes](const QImage &image) {
        if (!image.isNull() && !seen.contains(image.cacheKey())) {
            seen.insert(image.cacheKey());
            bytes += image.sizeInBytes();
        }
    };
    for (const auto &entry : entries) {
        count(entry.image);
        count(entry.base);
    }
    return bytes;
}

void HistoryStore::trim()
{
    // Redo is cleared before trimming, so only the undo stack can overflow.
    while (uniqueImageBytes() > budgetBytes_ && !undo_.isEmpty())
        undo_.removeFirst();
}

} // namespace NekoPic::Document
