#include "documentcontroller.h"
#include "core/adjustments.h"
#include "io/formatregistry.h"
#include "io/imageio.h"

#include <QFileInfo>
#include <QFutureWatcher>
#include <QTransform>
#include <QtConcurrentRun>
#include <algorithm>
#include <cmath>

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
QVariantMap DocumentController::adjustmentValues() const
{
    return {{"exposure", parameters_.exposure * 50.0}, {"brightness", parameters_.brightness * 100.0},
            {"contrast", parameters_.contrast * 100.0}, {"saturation", parameters_.saturation * 100.0}};
}
QVariantMap DocumentController::pendingAdjustmentValues() const
{
    return {{"exposure", pendingParameters_.exposure * 50.0},
            {"brightness", pendingParameters_.brightness * 100.0},
            {"contrast", pendingParameters_.contrast * 100.0},
            {"saturation", pendingParameters_.saturation * 100.0}};
}
QString DocumentController::filterPreset() const { return parameters_.filterPreset; }
double DocumentController::filterIntensity() const { return parameters_.filterIntensity * 100.0; }
bool DocumentController::filterIntensityInteractive() const
{
    return adjusting_ && adjustmentKey_ == "filter-intensity" && !adjustmentFinishing_;
}
QString DocumentController::errorMessage() const { return error_; }
bool DocumentController::hasImage() const { return !image_.isNull(); }
int DocumentController::imageWidth() const { return image_.width(); }
int DocumentController::imageHeight() const { return image_.height(); }
bool DocumentController::dirty() const { return hasImage() && currentState_ != savedState_; }
bool DocumentController::canUndo() const { return history_.canUndo(); }
bool DocumentController::canRedo() const { return history_.canRedo(); }
QStringList DocumentController::readableImagePatterns() const
{
    return NekoPic::Io::FormatRegistry::instance().readablePatterns();
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

void DocumentController::beginAdjustment(const QString &key)
{
    if (busy_ || !hasImage()) return;
    if (key != "exposure" && key != "brightness" && key != "contrast" && key != "saturation") return;
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
    if (parameters_.exposure == 0.0 && parameters_.brightness == 0.0
        && parameters_.contrast == 0.0 && parameters_.saturation == 0.0) return;
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

void DocumentController::selectFilter(const QString &preset)
{
    static const QSet<QString> presets{"none", "vivid", "warm", "cool", "mono", "vintage"};
    if (busy_ || !hasImage() || !presets.contains(preset) || preset == parameters_.filterPreset) return;
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
    if (key == "exposure") pendingParameters_.exposure = adjustmentValue_ / 50.0;
    else if (key == "brightness") pendingParameters_.brightness = adjustmentValue_ / 100.0;
    else if (key == "contrast") pendingParameters_.contrast = adjustmentValue_ / 100.0;
    else if (key == "saturation") pendingParameters_.saturation = adjustmentValue_ / 100.0;
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
    const auto sequence = adjustmentSequence_;
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
    watcher->setFuture(QtConcurrent::run([source, parameters] {
        return NekoPic::Adjustments::apply(source, parameters);
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
    const bool changed = parameters_.exposure != pendingParameters_.exposure
        || parameters_.brightness != pendingParameters_.brightness
        || parameters_.contrast != pendingParameters_.contrast
        || parameters_.saturation != pendingParameters_.saturation
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
            path_ = path;
            history_.clear();
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
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<NekoPic::ImageIO::SaveResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, path, url] {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (!result.success) setError(result.error);
        else { path_ = path; savedState_ = currentState_; emit documentChanged(); }
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([path, image, format] {
        NekoPic::ImageIO::SaveOptions options;
        options.format = format.toLatin1();
        return NekoPic::ImageIO::save(path, image, options);
    }));
}


void DocumentController::applyEdit(QImage image, QImage base, NekoPic::Adjustments::Parameters parameters)
{
    if (image.isNull() || base.isNull()) { setError(tr("Could not transform the image.")); return; }
    history_.record({image_, baseImage_, parameters_, currentState_});
    image_ = std::move(image);
    baseImage_ = std::move(base);
    parameters_ = parameters;
    currentState_ = ++nextState_;
    ++revision_;
    setError({});
    emit documentChanged();
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
    const auto source = image_;
    const auto base = baseImage_;
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<QPair<QImage, QImage>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        try {
            auto result = watcher->result();
            if (result.first.isNull() || result.second.isNull())
                setError(tr("Could not transform the image."));
            else
                applyEdit(std::move(result.first), std::move(result.second), parameters_);
        } catch (...) {
            setError(tr("Could not transform the image."));
        }
        watcher->deleteLater();
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([source, base, transform] {
        const auto applyTransform = [transform](const QImage &source) -> QImage {
        switch (transform) {
        case Transform::RotateClockwise:
            return source.transformed(QTransform().rotate(90));
        case Transform::RotateCounterClockwise:
            return source.transformed(QTransform().rotate(-90));
        case Transform::FlipHorizontal:
#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
            return source.flipped(Qt::Horizontal);
#else
            return source.mirrored(true, false);
#endif
        case Transform::FlipVertical:
#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
            return source.flipped(Qt::Vertical);
#else
            return source.mirrored(false, true);
#endif
        }
        return {};
        };
        auto transformed = applyTransform(source);
        auto transformedBase = source.cacheKey() == base.cacheKey() ? transformed : applyTransform(base);
        return qMakePair(std::move(transformed), std::move(transformedBase));
    }));
}

void DocumentController::undo()
{
    if (busy_) return;
    auto previous = history_.undo({image_, baseImage_, parameters_, currentState_});
    if (!previous) return;
    image_ = std::move(previous->image);
    baseImage_ = std::move(previous->base);
    parameters_ = previous->parameters;
    currentState_ = previous->state;
    ++revision_;
    emit documentChanged();
}

void DocumentController::redo()
{
    if (busy_) return;
    auto next = history_.redo({image_, baseImage_, parameters_, currentState_});
    if (!next) return;
    image_ = std::move(next->image);
    baseImage_ = std::move(next->base);
    parameters_ = next->parameters;
    currentState_ = next->state;
    ++revision_;
    emit documentChanged();
}
