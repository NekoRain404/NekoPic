#pragma once

#include "core/adjustments.h"

#include <QImage>
#include <QList>
#include <optional>

namespace NekoPic::Document {

// One undoable document state. QImage is implicitly shared, so storing a
// snapshot is cheap until either side is modified.
struct HistoryEntry {
    QImage image;
    QImage base;
    Adjustments::Parameters parameters;
    quint64 state = 0;
};

// Undo/redo stacks with a byte budget over unique image storage.
// GUI-thread only: entries are recorded when an edit is committed.
class HistoryStore final {
public:
    static constexpr qsizetype DefaultBudgetBytes = 256 * 1024 * 1024;

    explicit HistoryStore(qsizetype budgetBytes = DefaultBudgetBytes);

    void record(HistoryEntry entry);
    std::optional<HistoryEntry> undo(HistoryEntry current);
    std::optional<HistoryEntry> redo(HistoryEntry current);
    void clear();

    bool canUndo() const;
    bool canRedo() const;
    qsizetype undoCount() const;
    qsizetype redoCount() const;
    qsizetype uniqueImageBytes() const;
    qsizetype budgetBytes() const;

private:
    void trim();
    qsizetype uniqueBytes(const QList<HistoryEntry> &entries) const;

    QList<HistoryEntry> undo_;
    QList<HistoryEntry> redo_;
    qsizetype budgetBytes_;
};

} // namespace NekoPic::Document
