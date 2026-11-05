#include "filterpreviews.h"
#include "documentcontroller.h"
#include "core/colorpipeline.h"
#include "core/filterpresets.h"
#include <QQuickImageProvider>
#include <QReadWriteLock>
#include <QtConcurrentRun>

#include <algorithm>
#include <atomic>
#include <thread>
#include <utility>
#include <vector>

struct FilterPreviewCache {
    QReadWriteLock lock;
    QHash<QString, QImage> images;
    quint64 revision = 0;
};

namespace {
// Keep the fan-out bounded: four to six workers is enough to hide the per-tile
// setup cost without competing with the UI or the row-parallel core path.
int defaultPreviewWorkers()
{
    const unsigned hardware = std::thread::hardware_concurrency();
    if (hardware == 0)
        return 4;
    return static_cast<int>(std::clamp<unsigned>(hardware, 4u, 6u));
}

bool isFloatingFormat(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

// The shared-base split is bit-exact for integer formats when the extended
// pipeline is inactive: tone/saturation run once and each preset then applies
// to the same quantized RGBA64 values it would have seen in a full apply().
// Floating-point sources and extended controls fall back to a full apply per
// preset so the output stays identical to the historical serial path.
bool canShareBase(const QImage &image, const NekoPic::Adjustments::Parameters &parameters)
{
    return !isFloatingFormat(image.format())
        && !NekoPic::Adjustments::Internal::hasExtendedParameters(parameters);
}
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
        return FilterPreviews::generateBatch(source, parameters);
    }));
}

QHash<QString, QImage> FilterPreviews::generateBatch(
    const QImage &source, const NekoPic::Adjustments::Parameters &parameters, int workerCount)
{
    if (source.isNull())
        return {};
    // Downsample before effects; only these small results enter the cache.
    const auto small = (source.width() > 192 || source.height() > 144)
        ? source.scaled(192, 144, Qt::KeepAspectRatio, Qt::SmoothTransformation) : source;
    const auto presets = NekoPic::Filters::presetIds();
    if (presets.isEmpty())
        return {};

    // Apply shared tone/base parameters once when that is provably exact.
    QImage base;
    if (canShareBase(small, parameters)) {
        auto baseParameters = parameters;
        baseParameters.filterPreset = QStringLiteral("none");
        baseParameters.filterIntensity = 1.0;
        base = NekoPic::Adjustments::apply(small, baseParameters);
        if (base.isNull())
            return {};
    }
    // Keep the conversion chained onto the temporary returned by apply(): Qt
    // selects the rvalue convertToFormat() overload for it, and the historical
    // serial path (apply(...).convertToFormat(...)) produced slightly
    // different 8-bit results for floating-point sources on the other
    // overload. Chaining preserves byte-identical previews.
    const auto renderTile = [](const QImage &input,
                               const NekoPic::Adjustments::Parameters &tileParameters) {
        return NekoPic::Adjustments::apply(input, tileParameters)
            .convertToFormat(QImage::Format_RGBA8888);
    };

    const int count = int(presets.size());
    const int workers = std::clamp(
        workerCount > 0 ? workerCount : defaultPreviewWorkers(), 1, count);
    std::vector<QImage> tiles(static_cast<std::size_t>(count));
    std::atomic<int> next{0};
    std::atomic<bool> failed{false};

    // Threads write disjoint slots; the calling thread participates and joins
    // before returning, so no task ever outlives its captured source.
    const auto run = [&] {
        for (;;) {
            const int index = next.fetch_add(1, std::memory_order_relaxed);
            if (index >= count)
                return;
            try {
                const auto &preset = presets.at(index);
                QImage image;
                if (base.isNull()) {
                    auto tileParameters = parameters;
                    tileParameters.filterPreset = preset;
                    image = renderTile(small, tileParameters);
                } else {
                    // The base already carries tone/saturation; run only the
                    // preset so all 13 tiles share that work.
                    auto filterParameters = NekoPic::Adjustments::Parameters{};
                    filterParameters.filterPreset = preset;
                    filterParameters.filterIntensity = parameters.filterIntensity;
                    image = renderTile(base, filterParameters);
                }
                if (image.isNull()) {
                    failed.store(true, std::memory_order_relaxed);
                    return;
                }
                tiles[std::size_t(index)] = std::move(image);
            } catch (...) {
                failed.store(true, std::memory_order_relaxed);
                return;
            }
        }
    };

    if (workers <= 1) {
        run();
    } else {
        std::vector<std::thread> threads;
        threads.reserve(std::size_t(workers - 1));
        for (int worker = 1; worker < workers; ++worker) {
            try {
                threads.emplace_back(run);
            } catch (...) {
                break; // finish the remainder on the calling thread
            }
        }
        run();
        for (auto &thread : threads)
            thread.join();
    }
    if (failed.load(std::memory_order_relaxed))
        return {};

    QHash<QString, QImage> images;
    images.reserve(count);
    for (int index = 0; index < count; ++index) {
        if (tiles[std::size_t(index)].isNull())
            return {};
        images.insert(presets.at(index), std::move(tiles[std::size_t(index)]));
    }
    return images;
}
