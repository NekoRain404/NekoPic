#include "filterpreviews.h"
#include "documentcontroller.h"
#include "core/filterpresets.h"
#include <QQuickImageProvider>
#include <QReadWriteLock>
#include <QtConcurrentRun>
#include <utility>

struct FilterPreviewCache {
    QReadWriteLock lock;
    QHash<QString, QImage> images;
    quint64 revision = 0;
};

namespace {
class PreviewImageProvider final : public QQuickImageProvider {
public:
    explicit PreviewImageProvider(std::shared_ptr<FilterPreviewCache> cache)
        : QQuickImageProvider(Image), cache_(std::move(cache)) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &) override
    {
        const auto parts = id.split('/');
        QImage image;
        {
            QReadLocker locker(&cache_->lock);
            bool valid = false;
            const auto revision = parts.value(1).toULongLong(&valid);
            if (parts.size() == 2 && valid && revision == cache_->revision)
                image = cache_->images.value(parts.first());
        }
        if (size) *size = image.size();
        return image;
    }
private:
    const std::shared_ptr<FilterPreviewCache> cache_;
};
}

FilterPreviews::FilterPreviews(DocumentController &document, QObject *parent)
    : QObject(parent), cache_(std::make_shared<FilterPreviewCache>())
{
    debounce_.setSingleShot(true);
    debounce_.setInterval(60);
    connect(&debounce_, &QTimer::timeout, this, &FilterPreviews::startWorker);
    connect(&document, &DocumentController::documentChanged, this, [this, &document] {
        schedule(document.baseImage(), document.adjustmentParameters());
    });
    connect(&document, &QObject::destroyed, this, [this] { schedule({}, {}); });
    schedule(document.baseImage(), document.adjustmentParameters());
}
FilterPreviews::~FilterPreviews() = default;
bool FilterPreviews::ready() const { return ready_; }
quint64 FilterPreviews::revision() const { return revision_; }
std::unique_ptr<QQuickImageProvider> FilterPreviews::createImageProvider() const
{
    return std::make_unique<PreviewImageProvider>(cache_);
}

void FilterPreviews::schedule(QImage source, NekoPic::Adjustments::Parameters parameters)
{
    // All tiles share the same base and tone settings; ignore current look/strength.
    parameters.filterPreset = QStringLiteral("none");
    parameters.filterIntensity = 1.0;
    if (source.cacheKey() == source_.cacheKey()
        && parameters.exposure == parameters_.exposure
        && parameters.brightness == parameters_.brightness
        && parameters.contrast == parameters_.contrast
        && parameters.saturation == parameters_.saturation) return;
    source_ = std::move(source);
    parameters_ = std::move(parameters);
    ++generation_;
    ready_ = false;
    {
        QWriteLocker locker(&cache_->lock);
        cache_->images.clear();
    }
    emit changed();
    if (source_.isNull()) debounce_.stop();
    else debounce_.start();
}

void FilterPreviews::startWorker()
{
    if (running_ || source_.isNull()) return;
    const auto generation = generation_;
    const auto source = source_;
    const auto parameters = parameters_;
    running_ = true;
    // One worker per document, with at most one newer snapshot pending.
    disconnect(&watcher_, nullptr, this, nullptr);
    connect(&watcher_, &QFutureWatcherBase::finished, this, [this, generation] {
        running_ = false;
        Batch images;
        try { images = watcher_.result(); } catch (...) { /* Leave swatch fallback visible. */ }
        if (generation != generation_) {
            if (!debounce_.isActive()) startWorker();
            return;
        }
        if (images.size() != NekoPic::Filters::presetIds().size()) return;
        {
            QWriteLocker locker(&cache_->lock);
            cache_->images = std::move(images);
            cache_->revision = generation;
        }
        revision_ = generation;
        ready_ = true;
        emit changed();
    });
    watcher_.setFuture(QtConcurrent::run([source, parameters] {
        // Downsample before effects; only these small results enter the cache.
        const auto small = (source.width() > 192 || source.height() > 144)
            ? source.scaled(192, 144, Qt::KeepAspectRatio, Qt::SmoothTransformation) : source;
        Batch images;
        const auto presets = NekoPic::Filters::presetIds();
        for (const auto &preset : presets) {
            auto tileParameters = parameters;
            tileParameters.filterPreset = preset;
            auto image = NekoPic::Adjustments::apply(small, tileParameters)
                             .convertToFormat(QImage::Format_RGBA8888);
            if (image.isNull()) return Batch{};
            images.insert(tileParameters.filterPreset, std::move(image));
        }
        return images;
    }));
}
