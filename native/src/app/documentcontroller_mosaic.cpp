#include "documentcontroller.h"
#include "core/mosaic.h"

#include <QFutureWatcher>
#include <QtConcurrentRun>
#include <cmath>
#include <utility>

namespace {
bool validCoordinate(double value)
{
    return std::isfinite(value) && std::abs(value) <= 1e7;
}

bool validBlockSize(int blockSize)
{
    return blockSize >= 2 && blockSize <= 512;
}
}

void DocumentController::mosaicRectangle(const QRectF &area, int blockSize)
{
    if (busy_ || !hasImage() || !validBlockSize(blockSize)) return;
    if (!validCoordinate(area.x()) || !validCoordinate(area.y())
        || !validCoordinate(area.width()) || !validCoordinate(area.height())
        || !validCoordinate(area.right()) || !validCoordinate(area.bottom())) return;
    const auto clipped = area.normalized().intersected(QRectF(baseImage_.rect()));
    if (clipped.isEmpty()) return;
    const auto rectangle = clipped.toAlignedRect().intersected(baseImage_.rect());
    startMosaic([rectangle, blockSize](const QImage &base) {
        return NekoPic::Mosaic::pixelateRect(base, rectangle, blockSize);
    });
}

void DocumentController::mosaicStroke(const QVariantList &points, double diameter, int blockSize)
{
    if (busy_ || !hasImage() || !validBlockSize(blockSize) || points.isEmpty()
        || points.size() > 4096 || !std::isfinite(diameter)
        || diameter <= 0.0 || diameter > 4096.0) return;
    NekoPic::Mosaic::Stroke stroke;
    stroke.diameter = diameter;
    stroke.points.reserve(points.size());
    for (const auto &value : points) {
        if (!value.canConvert<QPointF>()) return;
        const auto point = value.toPointF();
        if (!validCoordinate(point.x()) || !validCoordinate(point.y())) return;
        stroke.points.append(point);
    }
    startMosaic([stroke = std::move(stroke), blockSize](const QImage &base) {
        return NekoPic::Mosaic::pixelateStroke(base, stroke, blockSize);
    });
}

void DocumentController::startMosaic(std::function<QImage(const QImage &)> operation)
{
    const auto base = baseImage_;
    if (qint64(base.width()) * base.height() > 64 * 1024 * 1024
        || base.sizeInBytes() > qsizetype(1024) * 1024 * 1024) return;
    const auto parameters = parameters_;
    const auto objects = objects_.clone();
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<EditResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        try {
            auto result = watcher->result();
            if (result.image.isNull() || result.base.isNull())
                setError(tr("Could not apply mosaic to the image."));
            else if (result.base.cacheKey() != baseImage_.cacheKey())
                commitEdit(std::move(result));
        } catch (...) {
            setError(tr("Could not apply mosaic to the image."));
        }
        watcher->deleteLater();
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, parameters, objects, operation = std::move(operation)] {
        auto newBase = operation(base);
        if (newBase.isNull()) return EditResult{};
        if (newBase == base) {
            // Mosaic writes only the base; the live object layer is unchanged.
            EditResult unchanged;
            unchanged.image = base;
            unchanged.base = base;
            unchanged.parameters = parameters;
            return unchanged;
        }
        // Mosaic is a pixel operation; objects remain above the new pixels.
        auto rendered = DocumentController::composeImage(newBase, parameters, objects.get());
        return EditResult{std::move(rendered), std::move(newBase), parameters, nullptr};
    }));
}
