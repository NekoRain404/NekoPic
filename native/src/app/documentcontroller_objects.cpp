#include "documentcontroller.h"

#include "document/shapeobject.h"
#include "document/strokeobject.h"
#include "document/textobject.h"

#include <QFutureWatcher>
#include <QtConcurrentRun>

#include <algorithm>
#include <cmath>
#include <memory>
#include <utility>

QImage DocumentController::composeImage(const QImage &base,
                                        const NekoPic::Adjustments::Parameters &parameters,
                                        const NekoPic::Document::ObjectLayer *objects)
{
    QImage rendered = NekoPic::Adjustments::apply(base, parameters);
    if (!rendered.isNull() && objects && !objects->isEmpty())
        objects->renderOnto(rendered);
    return rendered;
}

void DocumentController::startObjectEdit(
    std::function<bool(NekoPic::Document::ObjectLayer &)> mutation)
{
    if (busy_ || !hasImage()) return;

    // The clone is private to this operation: the worker can render it while
    // the live document (and the GUI thread) keep their own state.
    auto layer = objects_.clone();
    if (!mutation(*layer)) return;

    const auto base = baseImage_;
    const auto parameters = parameters_;
    // Object edits never change the base or the adjustment parameters, so the
    // adjusted pixels can be reused. A miss is filled by the worker and stored
    // for the next edit; a hit only repaints the object layer.
    const QImage cachedAdjustedBase =
        hasValidAdjustedBaseCache() ? adjustedBaseCache_ : QImage();
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<ObjectEditResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this,
            [this, watcher, layer, base, parameters] {
        ObjectEditResult result;
        bool failed = false;
        try { result = watcher->result(); } catch (...) { failed = true; }
        watcher->deleteLater();
        if (failed || result.image.isNull() || result.adjustedBase.isNull()) {
            setError(tr("Could not render the object layer."));
        } else {
            adjustedBaseCache_ = std::move(result.adjustedBase);
            adjustedBaseCacheParameters_ = parameters;
            adjustedBaseCacheSourceKey_ = base.cacheKey();
            adjustedBaseCacheValid_ = true;
            applyEdit(std::move(result.image), base, parameters, layer);
        }
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run(
        [base, parameters, layer, cachedAdjustedBase] {
        QImage adjustedBase = cachedAdjustedBase;
        if (adjustedBase.isNull())
            adjustedBase = NekoPic::Adjustments::apply(base, parameters);
        if (adjustedBase.isNull()) return ObjectEditResult{};
        QImage rendered = adjustedBase;
        if (!layer->isEmpty()) layer->renderOnto(rendered);
        return ObjectEditResult{std::move(rendered), std::move(adjustedBase)};
    }));
}

bool DocumentController::removeObject(quint64 id)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId) return false;
    if (!objects_.object(id)) return false;
    startObjectEdit([id](NekoPic::Document::ObjectLayer &layer) {
        return layer.remove(id);
    });
    return true;
}

void DocumentController::clearObjects()
{
    if (busy_ || !hasImage() || objects_.isEmpty()) return;
    startObjectEdit([](NekoPic::Document::ObjectLayer &layer) {
        if (layer.isEmpty()) return false;
        layer.clear();
        return true;
    });
}

void DocumentController::moveObject(quint64 id, qreal dx, qreal dy)
{
    if (!std::isfinite(dx) || !std::isfinite(dy)) return;
    if (std::abs(dx) > 1e7 || std::abs(dy) > 1e7) return;
    if (dx == 0.0 && dy == 0.0) return;
    if (busy_ || !hasImage()) return;
    startObjectEdit([id, dx, dy](NekoPic::Document::ObjectLayer &layer) {
        auto *object = layer.object(id);
        if (!object) return false;
        object->setTranslation(object->translation() + QPointF(dx, dy));
        return true;
    });
}

quint64 DocumentController::objectAt(qreal x, qreal y) const
{
    if (image_.isNull() || !std::isfinite(x) || !std::isfinite(y))
        return NekoPic::Document::InvalidObjectId;
    const QPointF point(x, y);
    // Selection uses bounding boxes (topmost first), which is friendlier for
    // text and transparent shapes; the layer's ink hit test remains available
    // for tools that need precise shape hits.
    const auto &objects = objects_.objects();
    for (auto it = objects.rbegin(); it != objects.rend(); ++it) {
        const auto *object = it->get();
        if (!object->isVisible() || object->isLocked()) continue;
        if (object->bounds().contains(point)) return object->id();
    }
    return NekoPic::Document::InvalidObjectId;
}

QRectF DocumentController::objectBounds(quint64 id) const
{
    if (id == NekoPic::Document::InvalidObjectId) return {};
    const auto *object = objects_.object(id);
    return object ? object->bounds() : QRectF{};
}

QVariantList DocumentController::objectIds() const
{
    QVariantList result;
    const auto ids = objects_.ids();
    result.reserve(ids.size());
    for (const auto id : ids) result.append(QVariant::fromValue<qulonglong>(id));
    return result;
}

namespace {

using namespace NekoPic::Document;

QString kindName(ObjectKind kind)
{
    switch (kind) {
    case ObjectKind::Text:
        return QStringLiteral("text");
    case ObjectKind::Shape:
        return QStringLiteral("shape");
    case ObjectKind::Stroke:
        return QStringLiteral("stroke");
    }
    return QStringLiteral("text");
}

QString shapeKindName(ShapeKind kind)
{
    switch (kind) {
    case ShapeKind::Rectangle:
        return DocumentController::tr("Rectangle");
    case ShapeKind::Ellipse:
        return DocumentController::tr("Ellipse");
    case ShapeKind::Line:
        return DocumentController::tr("Line");
    case ShapeKind::Arrow:
        return DocumentController::tr("Arrow");
    case ShapeKind::Polygon:
        return DocumentController::tr("Polygon");
    }
    return DocumentController::tr("Shape");
}

// Human label for the layer panel: a collapsed, bounded text preview, the
// shape kind, or a generic stroke label.
QString objectDisplayName(const DocumentObject &object)
{
    switch (object.kind()) {
    case ObjectKind::Text: {
        const auto *text = static_cast<const TextObject *>(&object);
        const QString preview = text->text().simplified();
        if (preview.isEmpty())
            return DocumentController::tr("Text");
        constexpr qsizetype MaxPreview = 32;
        return preview.size() > MaxPreview
                ? preview.left(MaxPreview - 1) + QChar(0x2026)
                : preview;
    }
    case ObjectKind::Shape:
        return shapeKindName(static_cast<const ShapeObject *>(&object)->shape());
    case ObjectKind::Stroke:
        return DocumentController::tr("Stroke");
    }
    return DocumentController::tr("Object");
}

// Resolves a QVariantList from QML into live, deduplicated object ids. Values
// that are not finite positive integers or that no longer exist are dropped.
QList<ObjectId> resolvedIds(const ObjectLayer &layer, const QVariantList &values)
{
    QList<ObjectId> result;
    result.reserve(values.size());
    for (const QVariant &value : values) {
        bool ok = false;
        const double number = value.toDouble(&ok);
        // Ids are small monotonic counters; anything outside the exact double
        // integer range cannot have come from objectSummaries().
        if (!ok || !std::isfinite(number) || number < 1.0 || number > 9007199254740992.0)
            continue;
        const auto id = static_cast<ObjectId>(number);
        if (static_cast<double>(id) != number)
            continue;
        if (!layer.object(id) || result.contains(id))
            continue;
        result.append(id);
    }
    return result;
}

// Document-space translation that moves `bounds` to the image edge/centre
// selected by `alignment` on each axis. Unspecified axes produce 0.
QPointF alignmentDelta(const QRectF &bounds, Qt::Alignment alignment,
                       qreal imageWidth, qreal imageHeight)
{
    qreal dx = 0.0;
    if (alignment & Qt::AlignLeft)
        dx = -bounds.left();
    else if (alignment & Qt::AlignRight)
        dx = imageWidth - bounds.right();
    else if (alignment & Qt::AlignHCenter)
        dx = imageWidth / 2.0 - bounds.center().x();

    qreal dy = 0.0;
    if (alignment & Qt::AlignTop)
        dy = -bounds.top();
    else if (alignment & Qt::AlignBottom)
        dy = imageHeight - bounds.bottom();
    else if (alignment & Qt::AlignVCenter)
        dy = imageHeight / 2.0 - bounds.center().y();

    return QPointF(dx, dy);
}

} // namespace

QVariantList DocumentController::objectSummaries() const
{
    QVariantList result;
    const auto &objects = objects_.objects();
    result.reserve(static_cast<qsizetype>(objects.size()));
    // Topmost first: layer panel order.
    for (auto it = objects.rbegin(); it != objects.rend(); ++it) {
        const auto *object = it->get();
        QVariantMap summary;
        summary.insert(QStringLiteral("id"), QVariant::fromValue<qulonglong>(object->id()));
        summary.insert(QStringLiteral("kind"), kindName(object->kind()));
        summary.insert(QStringLiteral("name"), objectDisplayName(*object));
        summary.insert(QStringLiteral("bounds"), QVariant::fromValue(object->bounds()));
        summary.insert(QStringLiteral("visible"), object->isVisible());
        summary.insert(QStringLiteral("locked"), object->isLocked());
        result.append(summary);
    }
    return result;
}

bool DocumentController::setObjectVisible(quint64 id, bool visible)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const auto *object = objects_.object(id);
    if (!object || object->isVisible() == visible)
        return false;
    startObjectEdit([id, visible](NekoPic::Document::ObjectLayer &layer) {
        auto *target = layer.object(id);
        if (!target || target->isVisible() == visible)
            return false;
        target->setVisible(visible);
        return true;
    });
    return true;
}

bool DocumentController::setObjectLocked(quint64 id, bool locked)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const auto *object = objects_.object(id);
    if (!object || object->isLocked() == locked)
        return false;
    startObjectEdit([id, locked](NekoPic::Document::ObjectLayer &layer) {
        auto *target = layer.object(id);
        if (!target || target->isLocked() == locked)
            return false;
        target->setLocked(locked);
        return true;
    });
    return true;
}

bool DocumentController::raiseObject(quint64 id)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const qsizetype index = objects_.indexOf(id);
    if (index < 0 || index + 1 >= objects_.size())
        return false;
    startObjectEdit([id](NekoPic::Document::ObjectLayer &layer) {
        return layer.raise(id);
    });
    return true;
}

bool DocumentController::lowerObject(quint64 id)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const qsizetype index = objects_.indexOf(id);
    if (index <= 0)
        return false;
    startObjectEdit([id](NekoPic::Document::ObjectLayer &layer) {
        return layer.lower(id);
    });
    return true;
}

bool DocumentController::bringObjectToFront(quint64 id)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const qsizetype index = objects_.indexOf(id);
    if (index < 0 || index == objects_.size() - 1)
        return false;
    startObjectEdit([id](NekoPic::Document::ObjectLayer &layer) {
        return layer.bringToFront(id);
    });
    return true;
}

bool DocumentController::sendObjectToBack(quint64 id)
{
    if (busy_ || !hasImage() || id == NekoPic::Document::InvalidObjectId)
        return false;
    const qsizetype index = objects_.indexOf(id);
    if (index <= 0)
        return false;
    startObjectEdit([id](NekoPic::Document::ObjectLayer &layer) {
        return layer.sendToBack(id);
    });
    return true;
}

bool DocumentController::removeObjects(const QVariantList &ids)
{
    if (busy_ || !hasImage())
        return false;
    const QList<NekoPic::Document::ObjectId> targets = resolvedIds(objects_, ids);
    if (targets.isEmpty())
        return false;
    startObjectEdit([targets](NekoPic::Document::ObjectLayer &layer) {
        bool changed = false;
        for (const auto id : targets)
            changed = layer.remove(id) || changed;
        return changed;
    });
    return true;
}

bool DocumentController::moveObjects(const QVariantList &ids, qreal dx, qreal dy)
{
    if (!std::isfinite(dx) || !std::isfinite(dy))
        return false;
    if (std::abs(dx) > 1e7 || std::abs(dy) > 1e7)
        return false;
    if (dx == 0.0 && dy == 0.0)
        return false;
    if (busy_ || !hasImage())
        return false;
    const QList<NekoPic::Document::ObjectId> targets = resolvedIds(objects_, ids);
    if (targets.isEmpty())
        return false;
    startObjectEdit([targets, dx, dy](NekoPic::Document::ObjectLayer &layer) {
        bool changed = false;
        for (const auto id : targets) {
            auto *object = layer.object(id);
            if (!object)
                continue;
            object->setTranslation(object->translation() + QPointF(dx, dy));
            changed = true;
        }
        return changed;
    });
    return true;
}

bool DocumentController::alignObjects(const QVariantList &ids, int alignment)
{
    if (busy_ || !hasImage())
        return false;
    const Qt::Alignment flags = static_cast<Qt::Alignment>(alignment);
    const bool hasHorizontal = flags.testFlag(Qt::AlignLeft)
            || flags.testFlag(Qt::AlignRight)
            || flags.testFlag(Qt::AlignHCenter);
    const bool hasVertical = flags.testFlag(Qt::AlignTop)
            || flags.testFlag(Qt::AlignBottom)
            || flags.testFlag(Qt::AlignVCenter);
    if (!hasHorizontal && !hasVertical)
        return false;

    const QList<NekoPic::Document::ObjectId> targets = resolvedIds(objects_, ids);
    if (targets.isEmpty())
        return false;

    const qreal width = static_cast<qreal>(image_.width());
    const qreal height = static_cast<qreal>(image_.height());
    bool wouldChange = false;
    for (const auto id : targets) {
        const auto *object = objects_.object(id);
        if (!object)
            continue;
        if (!alignmentDelta(object->bounds(), flags, width, height).isNull()) {
            wouldChange = true;
            break;
        }
    }
    if (!wouldChange)
        return false;

    startObjectEdit([targets, flags, width, height](
                        NekoPic::Document::ObjectLayer &layer) {
        bool changed = false;
        for (const auto id : targets) {
            auto *object = layer.object(id);
            if (!object)
                continue;
            const QPointF delta = alignmentDelta(object->bounds(), flags, width, height);
            if (delta.isNull())
                continue;
            object->setTranslation(object->translation() + delta);
            changed = true;
        }
        return changed;
    });
    return true;
}
