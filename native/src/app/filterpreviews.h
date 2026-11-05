#pragma once

#include "core/adjustments.h"
#include <QFutureWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <memory>

class DocumentController;
class QQuickImageProvider;
struct FilterPreviewCache;

// GUI-thread coordinator. The provider reads only a bounded, synchronized cache.
class FilterPreviews final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(quint64 revision READ revision NOTIFY changed)
public:
    explicit FilterPreviews(DocumentController &document, QObject *parent = nullptr);
    ~FilterPreviews() override;
    bool ready() const;
    quint64 revision() const;
    // URLs: image://filterpreview/<preset>/<revision>; engine takes provider ownership.
    std::unique_ptr<QQuickImageProvider> createImageProvider() const;
signals:
    void changed();
private:
    using Batch = QHash<QString, QImage>;
    void schedule(QImage source, NekoPic::Adjustments::Parameters parameters);
    void startWorker();
    std::shared_ptr<FilterPreviewCache> cache_;
    QTimer debounce_;
    QFutureWatcher<Batch> watcher_;
    QImage source_;
    NekoPic::Adjustments::Parameters parameters_;
    quint64 generation_ = 0;
    quint64 revision_ = 0;
    bool ready_ = false;
    bool running_ = false;
};
