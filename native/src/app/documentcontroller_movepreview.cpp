#include "documentcontroller.h"

#include <QFutureWatcher>
#include <QMutexLocker>
#include <QPainter>
#include <QSet>
#include <QtConcurrentRun>

#include <algorithm>
#include <cmath>
#include <utility>

namespace {

// The drag preview crops are expanded slightly so antialiased edges and text
// padding are not clipped by the exact object bounds.
constexpr int MovePreviewMargin = 2;

bool previewId(const QVariant &value, quint64 *id)
{
    bool ok = false;
    const double number = value.toDouble(&ok);
    if (!ok || !std::isfinite(number) || number < 1.0
        || number > 9007199254740992.0)
        return false;
    const auto candidate = static_cast<quint64>(number);
    if (static_cast<double>(candidate) != number)
        return false;
    *id = candidate;
    return true;
}

} // namespace

QImage DocumentController::objectMoveBaseImage() const
{
    QMutexLocker locker(&movePreviewMutex_);
    return movePreviewBaseCrop_;
}

QImage DocumentController::objectMoveObjectImage() const
{
    QMutexLocker locker(&movePreviewMutex_);
    return movePreviewObjectCrop_;
}

QUrl DocumentController::objectMoveBaseUrl() const
{
    QMutexLocker locker(&movePreviewMutex_);
    if (!movePreviewReady_ || movePreviewBaseCrop_.isNull())
        return {};
    return QUrl(QStringLiteral("image://document/movebase?revision=%1")
                    .arg(movePreviewRevision_));
}

QUrl DocumentController::objectMoveObjectUrl() const
{
    QMutexLocker locker(&movePreviewMutex_);
    if (!movePreviewReady_ || movePreviewObjectCrop_.isNull())
        return {};
    return QUrl(QStringLiteral("image://document/moveobject?revision=%1")
                    .arg(movePreviewRevision_));
}

QRectF DocumentController::objectMoveBounds() const
{
    QMutexLocker locker(&movePreviewMutex_);
    return movePreviewBounds_;
}

bool DocumentController::objectMovePreviewReady() const
{
    QMutexLocker locker(&movePreviewMutex_);
    return movePreviewReady_;
}

bool DocumentController::beginObjectMovePreview(const QVariantList &ids)
{
    if (busy_ || !hasImage() || ids.isEmpty())
        return false;

    QList<quint64> requested;
    QRectF bounds;
    for (const auto &value : ids) {
        quint64 id = 0;
        if (!previewId(value, &id) || requested.contains(id))
            continue;
        const auto *object = objects_.object(id);
        if (!object)
            continue;
        const QRectF objectBounds = object->bounds();
        if (objectBounds.isEmpty())
            continue;
        bounds = bounds.isNull() ? objectBounds : bounds.united(objectBounds);
        requested.append(id);
    }
    if (requested.isEmpty() || bounds.isEmpty())
        return false;

    // A whole-image selection still produces a bounded crop; clamp to pixels.
    QRect crop = bounds.toAlignedRect().adjusted(-MovePreviewMargin, -MovePreviewMargin,
                                                 MovePreviewMargin, MovePreviewMargin);
    crop = crop.intersected(baseImage_.rect());
    if (crop.isEmpty())
        return false;

    const quint64 revision = ++movePreviewRevision_;
    {
        QMutexLocker locker(&movePreviewMutex_);
        movePreviewIds_ = requested;
        movePreviewBounds_ = QRectF(crop);
        movePreviewBaseCrop_ = {};
        movePreviewObjectCrop_ = {};
        movePreviewReady_ = false;
    }
    emit objectMovePreviewChanged();

    const QImage base = baseImage_;
    const auto parameters = parameters_;
    const QImage cached = hasValidAdjustedBaseCache() ? adjustedBaseCache_ : QImage();

    auto *watcher = new QFutureWatcher<QImage>(this);
    connect(watcher, &QFutureWatcherBase::finished, this,
            [this, watcher, revision, crop, requested, base, parameters] {
        QImage adjusted;
        try {
            adjusted = watcher->result();
        } catch (...) {
            adjusted = {};
        }
        watcher->deleteLater();
        if (revision != movePreviewRevision_ || adjusted.isNull()
            || !hasImage() || crop.isEmpty())
            return;

        // Base crop: the adjusted image with the selected objects removed, but
        // with every unselected object kept so overlapping objects do not
        // disappear under the moving selection.
        QImage baseCrop = adjusted.copy(crop);
        if (baseCrop.isNull())
            return;
        QSet<quint64> selected;
        for (const auto id : requested)
            selected.insert(id);
        {
            QPainter painter(&baseCrop);
            painter.setRenderHint(QPainter::Antialiasing, true);
            painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
            painter.translate(-crop.left(), -crop.top());
            for (const auto &object : objects_.objects()) {
                if (object->isVisible() && !selected.contains(object->id()))
                    object->render(painter);
            }
        }

        // Moving crop: only the selected objects, in layer order.
        QImage objectCrop(crop.size(), QImage::Format_ARGB32_Premultiplied);
        if (objectCrop.isNull())
            return;
        objectCrop.fill(Qt::transparent);
        {
            QPainter painter(&objectCrop);
            painter.setRenderHint(QPainter::Antialiasing, true);
            painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
            painter.translate(-crop.left(), -crop.top());
            for (const auto &object : objects_.objects()) {
                if (object->isVisible() && selected.contains(object->id()))
                    object->render(painter);
            }
        }

        // The worker computed the same adjusted base the object-edit cache
        // wants; retain it so the release commit does not repeat the work.
        if (base.cacheKey() == baseImage_.cacheKey()
            && parametersEqual(parameters, parameters_)) {
            adjustedBaseCache_ = adjusted;
            adjustedBaseCacheParameters_ = parameters_;
            adjustedBaseCacheSourceKey_ = base.cacheKey();
            adjustedBaseCacheValid_ = true;
        }

        {
            QMutexLocker locker(&movePreviewMutex_);
            if (revision != movePreviewRevision_)
                return;
            movePreviewBaseCrop_ = std::move(baseCrop);
            movePreviewObjectCrop_ = std::move(objectCrop);
            movePreviewReady_ = true;
        }
        emit objectMovePreviewChanged();
    });

    watcher->setFuture(QtConcurrent::run([base, parameters, cached] {
        if (!cached.isNull())
            return cached;
        return NekoPic::Adjustments::apply(base, parameters);
    }));
    return true;
}

void DocumentController::clearObjectMovePreview()
{
    {
        QMutexLocker locker(&movePreviewMutex_);
        ++movePreviewRevision_;
        movePreviewIds_.clear();
        movePreviewBounds_ = {};
        movePreviewBaseCrop_ = {};
        movePreviewObjectCrop_ = {};
        movePreviewReady_ = false;
    }
    emit objectMovePreviewChanged();
}
