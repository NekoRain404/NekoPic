#include "documentcontroller.h"

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
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<QImage>(this);
    connect(watcher, &QFutureWatcherBase::finished, this,
            [this, watcher, layer, base, parameters] {
        QImage rendered;
        bool failed = false;
        try { rendered = watcher->result(); } catch (...) { failed = true; }
        watcher->deleteLater();
        if (failed || rendered.isNull()) {
            setError(tr("Could not render the object layer."));
        } else {
            applyEdit(std::move(rendered), base, parameters, layer);
        }
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, parameters, layer] {
        return DocumentController::composeImage(base, parameters, layer.get());
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
