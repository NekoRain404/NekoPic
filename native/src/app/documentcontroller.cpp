#include "documentcontroller.h"
#include "core/adjustments.h"
#include "core/filterpresets.h"
#include "core/autoenhance.h"
#include "core/histogram.h"
#include "io/formatregistry.h"
#include "platform/clipboard.h"
#include "io/imageio.h"

#include <QFileInfo>
#include <QFutureWatcher>
#include <QTransform>
#include <QtConcurrentRun>
#include <algorithm>
#include <cmath>

namespace {

// Interactive CPU previews above this size are rendered on a display-sized
// proxy and scaled back, so drag latency stays bounded on large images.
constexpr qint64 PreviewProxyThresholdPixels = 2500000;
constexpr int PreviewProxyMaxWidth = 1600;
constexpr int PreviewProxyMaxHeight = 1000;

bool hslEqual(const NekoPic::Adjustments::HslChannelAdjustment &a,
              const NekoPic::Adjustments::HslChannelAdjustment &b)
{
    return a.hue == b.hue && a.saturation == b.saturation && a.luminance == b.luminance;
}

bool curveEqual(const NekoPic::Adjustments::ToneCurve &a,
                const NekoPic::Adjustments::ToneCurve &b)
{
    for (int point = 0; point < NekoPic::Adjustments::CurvePointCount; ++point) {
        if (a.points[point] != b.points[point]) return false;
    }
    return true;
}

bool gradeEqual(const NekoPic::Adjustments::GradeZoneAdjustment &a,
                const NekoPic::Adjustments::GradeZoneAdjustment &b)
{
    return a.hue == b.hue && a.saturation == b.saturation && a.luminance == b.luminance;
}

} // namespace

DocumentController::DocumentController(QObject *parent) : QObject(parent) {}
DocumentController::~DocumentController() = default;
QString DocumentController::fileName() const { return path_.isEmpty() ? tr("Untitled") : QFileInfo(path_).fileName(); }
QUrl DocumentController::imageUrl() const { return hasImage() ? QUrl(QStringLiteral("image://document/current?revision=%1").arg(revision_)) : QUrl(); }
QUrl DocumentController::baseImageUrl() const { return hasImage() ? QUrl(QStringLiteral("image://document/base?revision=%1").arg(revision_)) : QUrl(); }
bool DocumentController::busy() const { return busy_; }
bool DocumentController::adjusting() const { return adjusting_; }
bool DocumentController::adjustmentInteractive() const
{
    return adjusting_ && adjustmentKey_ != "filter" && adjustmentKey_ != "filter-intensity"
        && !adjustmentFinishing_;
}
bool DocumentController::adjustmentPreviewGpuEligible() const
{
    return adjustmentInteractive()
        && NekoPic::Adjustments::isGpuPreviewKey(adjustmentKey_)
        && NekoPic::Adjustments::isGpuPreviewSupported(pendingParameters_);
}
QVariantMap DocumentController::adjustmentValues() const
{
    return NekoPic::Adjustments::toUiValues(parameters_);
}
QVariantList DocumentController::histogramBins() const
{
    if (image_.isNull()) return {};
    if (histogramCacheRevision_ == revision_ && !histogramCache_.isEmpty())
        return histogramCache_;
    const auto histogram = NekoPic::Histogram::compute(image_, 500000);
    QVariantList bins;
    bins.reserve(256);
    for (const auto count : histogram.luma) bins.append(QVariant::fromValue<qulonglong>(count));
    histogramCache_ = bins;
    histogramCacheRevision_ = revision_;
    return histogramCache_;
}

QVariantMap DocumentController::pendingAdjustmentValues() const
{
    return NekoPic::Adjustments::toUiValues(pendingParameters_);
}
QString DocumentController::filterPreset() const { return parameters_.filterPreset; }
double DocumentController::filterIntensity() const { return parameters_.filterIntensity * 100.0; }
bool DocumentController::filterIntensityInteractive() const
{
    return adjusting_ && adjustmentKey_ == "filter-intensity" && !adjustmentFinishing_;
}
QString DocumentController::errorMessage() const { return error_; }
bool DocumentController::hasImage() const { return !image_.isNull(); }
bool DocumentController::hasObjects() const { return !objects_.isEmpty(); }
int DocumentController::imageWidth() const { return image_.width(); }
int DocumentController::imageHeight() const { return image_.height(); }
bool DocumentController::dirty() const { return hasImage() && currentState_ != savedState_; }
bool DocumentController::hasPath() const { return !path_.isEmpty(); }
bool DocumentController::canUndo() const { return history_.canUndo(); }
bool DocumentController::canRedo() const { return history_.canRedo(); }
QStringList DocumentController::readableImagePatterns() const
{
    return NekoPic::Io::FormatRegistry::instance().readablePatterns();
}

int DocumentController::exportQuality() const { return exportQuality_; }
void DocumentController::setExportQuality(int quality)
{
    const int clamped = std::clamp(quality, -1, 100);
    if (clamped == exportQuality_) return;
    exportQuality_ = clamped;
    emit exportOptionsChanged();
}
QColor DocumentController::jpegBackground() const { return jpegBackground_; }
void DocumentController::setJpegBackground(const QColor &color)
{
    if (!color.isValid()) return;
    QColor opaque = color;
    opaque.setAlpha(255);
    if (opaque == jpegBackground_) return;
    jpegBackground_ = opaque;
    emit exportOptionsChanged();
}

QVariantList DocumentController::writableFormats() const
{
    const auto &registry = NekoPic::Io::FormatRegistry::instance();
    QVariantList result;
    for (const auto &format : registry.formats()) {
        if (format.writeExtensions.isEmpty()) continue;
        QStringList patterns;
        for (const auto &extension : format.writeExtensions) {
            patterns.append(QStringLiteral("*.") + extension);
            patterns.append(QStringLiteral("*.") + extension.toUpper());
        }
        result.append(QVariantMap{
            {QStringLiteral("id"), format.id},
            {QStringLiteral("label"), registry.displayName(format.id)},
            {QStringLiteral("suffix"), registry.preferredSuffix(format.id)},
            {QStringLiteral("patterns"), patterns},
        });
    }
    return result;
}
QImage DocumentController::image() const { return image_; }
QImage DocumentController::baseImage() const { return baseImage_; }
NekoPic::Adjustments::Parameters DocumentController::adjustmentParameters() const { return parameters_; }

bool DocumentController::parametersEqual(const NekoPic::Adjustments::Parameters &a,
                                          const NekoPic::Adjustments::Parameters &b)
{
    // Basic and extended scalar controls.
    if (a.exposure != b.exposure || a.brightness != b.brightness
        || a.contrast != b.contrast || a.saturation != b.saturation
        || a.highlights != b.highlights || a.shadows != b.shadows
        || a.whites != b.whites || a.blacks != b.blacks
        || a.temperature != b.temperature || a.tint != b.tint
        || a.vibrance != b.vibrance || a.fade != b.fade)
        return false;

    // HSL channels.
    for (int channel = 0; channel < NekoPic::Adjustments::HslChannelCount; ++channel) {
        if (!hslEqual(a.hsl[channel], b.hsl[channel])) return false;
    }

    // Tone curves.
    for (int channel = 0; channel < NekoPic::Adjustments::CurveChannelCount; ++channel) {
        if (!curveEqual(a.curves[channel], b.curves[channel])) return false;
    }

    // Colour grading.
    for (int zone = 0; zone < NekoPic::Adjustments::GradeZoneCount; ++zone) {
        if (!gradeEqual(a.grade[zone], b.grade[zone])) return false;
    }
    if (a.gradeBlending != b.gradeBlending || a.gradeBalance != b.gradeBalance)
        return false;

    // Detail and effects.
    if (a.texture != b.texture || a.clarity != b.clarity || a.dehaze != b.dehaze
        || a.sharpen != b.sharpen || a.noise != b.noise || a.colorNoise != b.colorNoise
        || a.vignette != b.vignette || a.feather != b.feather || a.grain != b.grain)
        return false;

    // Filter preset.
    return a.filterPreset == b.filterPreset && a.filterIntensity == b.filterIntensity;
}

QImage DocumentController::previewProxySource(const QImage &source)
{
    const qint64 sourceKey = source.cacheKey();
    const qint64 dragKey = adjustmentSource_.cacheKey();
    if (!previewProxySource_.isNull() && previewProxySourceKey_ == sourceKey
        && previewProxyAdjustmentKey_ == dragKey)
        return previewProxySource_;

    const QSize target = source.size().scaled(
        QSize(PreviewProxyMaxWidth, PreviewProxyMaxHeight), Qt::KeepAspectRatio);
    previewProxySource_ = target.isEmpty()
        ? QImage()
        : source.scaled(target, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    previewProxySourceKey_ = sourceKey;
    previewProxyAdjustmentKey_ = dragKey;
    return previewProxySource_;
}

bool DocumentController::hasValidAdjustedBaseCache() const
{
    return adjustedBaseCacheValid_ && !adjustedBaseCache_.isNull()
        && adjustedBaseCacheSourceKey_ == baseImage_.cacheKey()
        && parametersEqual(adjustedBaseCacheParameters_, parameters_);
}

void DocumentController::invalidateAdjustedBaseCache()
{
    adjustedBaseCache_ = {};
    adjustedBaseCacheParameters_ = {};
    adjustedBaseCacheSourceKey_ = 0;
    adjustedBaseCacheValid_ = false;
}

void DocumentController::setBusy(bool busy)
{
    if (busy_ == busy) return;
    busy_ = busy;
    emit busyChanged();
}

void DocumentController::setError(const QString &error)
{
    if (error_ == error) return;
    error_ = error;
    emit errorChanged();
}

void DocumentController::clearError() { setError({}); }

void DocumentController::copyImageToClipboard()
{
    if (busy_ || !hasImage()) return;
    QString error;
    if (!NekoPic::Platform::copyImage(image_, &error)) {
        setError(error);
        return;
    }
    emit imageCopied();
}

QColor DocumentController::colorAt(qreal x, qreal y) const
{
    if (image_.isNull() || !std::isfinite(x) || !std::isfinite(y)) return {};
    const int px = std::clamp(static_cast<int>(std::floor(x)), 0, image_.width() - 1);
    const int py = std::clamp(static_cast<int>(std::floor(y)), 0, image_.height() - 1);
    return image_.pixelColor(px, py);
}

void DocumentController::beginAdjustment(const QString &key)
{
    if (busy_ || !hasImage()) return;
    if (!NekoPic::Adjustments::isParameterKey(key)) return;
    adjustmentSource_ = image_;
    pendingParameters_ = parameters_;
    adjustmentKey_ = key;
    adjustmentValue_ = 0.0;
    adjustmentFinishing_ = false;
    adjusting_ = true;
    setError({});
    setBusy(true);
    emit adjustingChanged();
    emit adjustmentInteractiveChanged();
    emit adjustmentPreviewChanged();
}

void DocumentController::previewAdjustment(const QString &key, double value)
{
    queueAdjustment(key, value, false);
}

void DocumentController::finishAdjustment(const QString &key, double value)
{
    queueAdjustment(key, value, true);
}

void DocumentController::resetAdjustments()
{
    if (busy_ || !hasImage()) return;
    if (NekoPic::Adjustments::toUiValues(parameters_)
        == NekoPic::Adjustments::toUiValues(NekoPic::Adjustments::Parameters{})) return;
    adjustmentSource_ = image_;
    pendingParameters_ = {};
    pendingParameters_.filterPreset = parameters_.filterPreset;
    pendingParameters_.filterIntensity = parameters_.filterIntensity;
    adjustmentKey_ = "reset";
    adjusting_ = true;
    adjustmentFinishing_ = true;
    setError({});
    setBusy(true);
    emit adjustingChanged();
    emit adjustmentPreviewChanged();
    ++adjustmentSequence_;
    startAdjustmentWorker();
}

void DocumentController::autoEnhance()
{
    if (busy_ || !hasImage()) return;
    const auto suggestion = NekoPic::AutoEnhance::suggest(
        NekoPic::Histogram::compute(baseImage_, 500000));
    if (suggestion.isNoOp()) return;

    adjustmentSource_ = image_;
    pendingParameters_ = parameters_;
    NekoPic::Adjustments::setParameter(pendingParameters_, QStringLiteral("exposure"),
                                       suggestion.exposure);
    NekoPic::Adjustments::setParameter(pendingParameters_, QStringLiteral("contrast"),
                                       suggestion.contrast);
    NekoPic::Adjustments::setParameter(pendingParameters_, QStringLiteral("saturation"),
                                       suggestion.saturation);
    NekoPic::Adjustments::setParameter(pendingParameters_, QStringLiteral("blacks"),
                                       suggestion.blacks);
    NekoPic::Adjustments::setParameter(pendingParameters_, QStringLiteral("whites"),
                                       suggestion.whites);
    adjustmentKey_ = "auto";
    adjusting_ = true;
    adjustmentFinishing_ = true;
    setError({});
    setBusy(true);
    emit adjustingChanged();
    emit adjustmentPreviewChanged();
    ++adjustmentSequence_;
    startAdjustmentWorker();
}

void DocumentController::selectFilter(const QString &preset)
{
    if (busy_ || !hasImage() || !NekoPic::Filters::isValidPreset(preset)
        || preset == parameters_.filterPreset)
        return;
    adjustmentSource_ = image_;
    pendingParameters_ = parameters_;
    pendingParameters_.filterPreset = preset;
    if (preset != "none" && pendingParameters_.filterIntensity <= 0.0)
        pendingParameters_.filterIntensity = 1.0;
    adjustmentKey_ = "filter";
    adjusting_ = true;
    adjustmentFinishing_ = true;
    setError({});
    setBusy(true);
    emit adjustingChanged();
    emit adjustmentPreviewChanged();
    ++adjustmentSequence_;
    startAdjustmentWorker();
}

void DocumentController::beginFilterIntensity()
{
    if (busy_ || !hasImage() || parameters_.filterPreset == "none") return;
    adjustmentSource_ = image_;
    pendingParameters_ = parameters_;
    adjustmentKey_ = "filter-intensity";
    adjusting_ = true;
    adjustmentFinishing_ = false;
    setError({});
    setBusy(true);
    emit adjustingChanged();
    emit filterIntensityInteractiveChanged();
}

void DocumentController::previewFilterIntensity(double value) { queueFilterIntensity(value, false); }
void DocumentController::finishFilterIntensity(double value) { queueFilterIntensity(value, true); }

void DocumentController::queueFilterIntensity(double value, bool finish)
{
    if (!adjusting_ || adjustmentFinishing_ || adjustmentKey_ != "filter-intensity") return;
    pendingParameters_.filterIntensity = std::isfinite(value)
        ? std::clamp(value, 0.0, 100.0) / 100.0 : 0.0;
    adjustmentFinishing_ = finish;
    ++adjustmentSequence_;
    emit adjustmentPreviewChanged();
    if (finish) emit filterIntensityInteractiveChanged();
    if (!adjustmentWorkerRunning_) startAdjustmentWorker();
}

void DocumentController::queueAdjustment(const QString &key, double value, bool finish)
{
    if (!adjusting_ || adjustmentFinishing_ || key != adjustmentKey_) return;
    adjustmentValue_ = std::isfinite(value) ? std::clamp(value, -100.0, 100.0) : 0.0;
    if (!NekoPic::Adjustments::setParameter(pendingParameters_, key, adjustmentValue_)) return;
    adjustmentFinishing_ = finish;
    ++adjustmentSequence_;
    emit adjustmentPreviewChanged();
    if (finish) emit adjustmentInteractiveChanged();
    if (!adjustmentWorkerRunning_) startAdjustmentWorker();
}

void DocumentController::startAdjustmentWorker()
{
    const auto source = baseImage_;
    const auto parameters = pendingParameters_;
    const auto objects = objects_.clone();
    const auto sequence = adjustmentSequence_;

    // Interactive previews render adjustments on a display-resolution proxy
    // and scale the result back to the full canvas, leaving image_ full size so
    // object coordinates stay exact. The finishing pass and the four basic keys
    // mirrored by the QML GPU preview remain full resolution.
    QImage proxySource;
    if (adjusting_ && !adjustmentFinishing_
        && !NekoPic::Adjustments::isGpuPreviewKey(adjustmentKey_)
        && qint64(source.width()) * qint64(source.height()) >= PreviewProxyThresholdPixels) {
        proxySource = previewProxySource(source);
    }

    adjustmentWorkerRunning_ = true;
    auto *watcher = new QFutureWatcher<QImage>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, sequence] {
        QImage result;
        bool failed = false;
        try { result = watcher->result(); } catch (...) { failed = true; }
        watcher->deleteLater();
        adjustmentWorkerRunning_ = false;
        if (sequence != adjustmentSequence_) {
            startAdjustmentWorker();
            return;
        }
        if (failed || result.isNull()) {
            endAdjustment({}, true);
        } else if (adjustmentFinishing_) {
            endAdjustment(result, false);
        } else {
            image_ = std::move(result);
            ++revision_;
            emit documentChanged();
        }
    });
    watcher->setFuture(QtConcurrent::run([source, proxySource, parameters, objects] {
        if (proxySource.isNull())
            return DocumentController::composeImage(source, parameters, objects.get());
        QImage rendered = NekoPic::Adjustments::apply(proxySource, parameters);
        if (rendered.isNull()) return QImage();
        rendered = rendered.scaled(source.size(), Qt::IgnoreAspectRatio,
                                   Qt::SmoothTransformation);
        if (!rendered.isNull() && objects && !objects->isEmpty())
            objects->renderOnto(rendered);
        return rendered;
    }));
}

void DocumentController::endAdjustment(const QImage &result, bool failed)
{
    const bool wasInteractive = adjustmentInteractive();
    const bool wasFilterInteractive = filterIntensityInteractive();
    image_ = adjustmentSource_;
    adjustmentSource_ = {};
    adjusting_ = false;
    adjustmentFinishing_ = false;
    adjustmentKey_.clear();
    if (wasInteractive) emit adjustmentInteractiveChanged();
    if (wasFilterInteractive) emit filterIntensityInteractiveChanged();
    emit adjustmentPreviewChanged();
    const bool changed = NekoPic::Adjustments::toUiValues(parameters_)
            != NekoPic::Adjustments::toUiValues(pendingParameters_)
        || parameters_.filterPreset != pendingParameters_.filterPreset
        || parameters_.filterIntensity != pendingParameters_.filterIntensity;
    if (!failed && changed) {
        applyEdit(result, baseImage_, pendingParameters_);
    } else {
        ++revision_;
        emit documentChanged();
        if (failed) setError(tr("Could not adjust the image."));
    }
    emit adjustingChanged();
    setBusy(false);
}

void DocumentController::openImage(const QUrl &url)
{
    if (busy_) return;
    if (dirty()) { setError(tr("Save or discard your changes before opening another image.")); return; }
    openImageDiscardingChanges(url);
}

void DocumentController::openImageDiscardingChanges(const QUrl &url)
{
    if (busy_) return;
    if (!url.isLocalFile()) { setError(tr("Please choose a local image file.")); return; }
    const auto path = url.toLocalFile();
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<NekoPic::ImageIO::LoadResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, path, url] {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (!result.error.isEmpty()) setError(result.error);
        else {
            image_ = result.image;
            baseImage_ = result.image;
            parameters_ = {};
            objects_.clear();
            path_ = path;
            history_.clear();
            invalidateAdjustedBaseCache();
            currentState_ = savedState_ = ++nextState_;
            ++revision_;
            emit documentChanged();
            emit imageOpened(url);
        }
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([path] { return NekoPic::ImageIO::load(path); }));
}

void DocumentController::saveImage()
{
    // Avoid lossy re-encoding an unchanged file.
    if (hasImage() && !dirty()) return;
    if (path_.isEmpty()) { setError(tr("Choose a destination with Save As.")); return; }
    const auto suffix = QFileInfo(path_).suffix().toLower();
    saveAs(QUrl::fromLocalFile(path_), suffix == "jpg" ? QStringLiteral("jpeg") : suffix);
}

void DocumentController::saveAs(const QUrl &url, const QString &format)
{
    if (busy_) return;
    if (!hasImage()) { setError(tr("There is no image to save.")); return; }
    if (!url.isLocalFile()) { setError(tr("Please choose a local destination.")); return; }
    const auto &registry = NekoPic::Io::FormatRegistry::instance();
    auto normalized = format.trimmed().toLower();
    if (normalized == QLatin1String("jpg")) normalized = QStringLiteral("jpeg");
    const auto capability = registry.capability(normalized);
    if (!capability || capability->writeExtensions.isEmpty()) {
        setError(tr("The selected format is not available for export."));
        return;
    }
    auto path = url.toLocalFile();
    const auto suffix = QFileInfo(path).suffix().toLower();
    if (suffix.isEmpty()) {
        path += QLatin1Char('.') + registry.preferredSuffix(normalized);
        if (QFileInfo::exists(path)) {
            setError(tr("The destination already exists. Enter its full filename to confirm replacement."));
            return;
        }
    } else if (!capability->writeExtensions.contains(suffix)) {
        setError(tr("The filename extension does not match the selected format."));
        return;
    }
    const auto image = image_;
    const int quality = exportQuality_;
    const auto background = jpegBackground_;
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<NekoPic::ImageIO::SaveResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, path, url] {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (!result.success) setError(result.error);
        else {
            path_ = path;
            savedState_ = currentState_;
            emit documentChanged();
            emit imageSaved();
        }
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([path, image, format, quality, background] {
        NekoPic::ImageIO::SaveOptions options;
        options.format = format.toLatin1();
        options.quality = quality;
        options.jpegBackground = background;
        return NekoPic::ImageIO::save(path, image, options);
    }));
}


void DocumentController::applyEdit(QImage image, QImage base,
                                   NekoPic::Adjustments::Parameters parameters,
                                   std::shared_ptr<NekoPic::Document::ObjectLayer> objects)
{
    if (image.isNull() || base.isNull()) { setError(tr("Could not transform the image.")); return; }
    // Keep the adjusted-base cache only when this edit leaves the base pixels
    // and every parameter untouched (the object-edit path). Any transform,
    // crop, resize, pixel edit or adjustment commit invalidates it.
    const qint64 newBaseKey = base.cacheKey();
    const bool keepAdjustedCache = hasValidAdjustedBaseCache()
        && newBaseKey == baseImage_.cacheKey()
        && parametersEqual(parameters, parameters_);

    // Snapshot the state being replaced. The clone is never mutated afterwards,
    // so undo can restore the exact ids and geometry.
    history_.record({image_, baseImage_, parameters_, objects_.clone(), currentState_});
    image_ = std::move(image);
    baseImage_ = std::move(base);
    parameters_ = parameters;
    if (!keepAdjustedCache) invalidateAdjustedBaseCache();
    if (objects)
        objects_ = std::move(*objects);
    currentState_ = ++nextState_;
    ++revision_;
    setError({});
    emit documentChanged();
}

void DocumentController::commitEdit(EditResult result)
{
    applyEdit(std::move(result.image), std::move(result.base), result.parameters,
              std::move(result.objects));
}

void DocumentController::rotateClockwise()
{
    startTransform(Transform::RotateClockwise);
}

void DocumentController::rotateCounterClockwise()
{
    startTransform(Transform::RotateCounterClockwise);
}

void DocumentController::flipHorizontal()
{
    startTransform(Transform::FlipHorizontal);
}

void DocumentController::flipVertical()
{
    startTransform(Transform::FlipVertical);
}

void DocumentController::startTransform(Transform transform)
{
    if (busy_ || !hasImage()) return;
    const auto base = baseImage_;
    const auto parameters = parameters_;
    const auto objects = objects_.clone();
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<EditResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        try {
            auto result = watcher->result();
            if (result.image.isNull() || result.base.isNull())
                setError(tr("Could not transform the image."));
            else
                commitEdit(std::move(result));
        } catch (...) {
            setError(tr("Could not transform the image."));
        }
        watcher->deleteLater();
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, parameters, objects, transform] {
        QTransform raw;
        switch (transform) {
        case Transform::RotateClockwise:
            raw.rotate(90);
            break;
        case Transform::RotateCounterClockwise:
            raw.rotate(-90);
            break;
        case Transform::FlipHorizontal:
            raw.scale(-1.0, 1.0);
            break;
        case Transform::FlipVertical:
            raw.scale(1.0, -1.0);
            break;
        }
        // QImage::transformed() shifts the mapped image back to the origin so
        // the result is not clipped. Reproduce that translation for the objects;
        // a raw negative scale or rotation alone would leave them off-canvas.
        const QRectF mapped = raw.mapRect(QRectF(0, 0, base.width(), base.height()));
        const QTransform effective = raw * QTransform::fromTranslate(-mapped.x(), -mapped.y());
        auto transformedBase = base.transformed(raw);
        if (transformedBase.isNull()) return EditResult{};
        objects->applyTransform(effective);
        auto rendered = DocumentController::composeImage(transformedBase, parameters, objects.get());
        return EditResult{std::move(rendered), std::move(transformedBase), parameters, objects};
    }));
}

void DocumentController::undo()
{
    if (busy_) return;
    auto previous = history_.undo({image_, baseImage_, parameters_, objects_.clone(), currentState_});
    if (!previous) return;
    image_ = std::move(previous->image);
    baseImage_ = std::move(previous->base);
    parameters_ = previous->parameters;
    if (previous->objects)
        objects_.restoreFrom(*previous->objects);
    else
        objects_.clear();
    currentState_ = previous->state;
    invalidateAdjustedBaseCache();
    ++revision_;
    emit documentChanged();
}

void DocumentController::redo()
{
    if (busy_) return;
    auto next = history_.redo({image_, baseImage_, parameters_, objects_.clone(), currentState_});
    if (!next) return;
    image_ = std::move(next->image);
    baseImage_ = std::move(next->base);
    parameters_ = next->parameters;
    if (next->objects)
        objects_.restoreFrom(*next->objects);
    else
        objects_.clear();
    currentState_ = next->state;
    invalidateAdjustedBaseCache();
    ++revision_;
    emit documentChanged();
}
