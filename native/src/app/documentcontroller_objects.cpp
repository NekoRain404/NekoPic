#include "documentcontroller.h"

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

void DocumentController::addText(const QString &text, qreal x, qreal y, qreal fontSize,
                                 const QColor &color, int alignment)
{
    if (text.trimmed().isEmpty()) return;
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(fontSize)) return;
    if (std::abs(x) > 1e7 || std::abs(y) > 1e7) return;
    if (busy_ || !hasImage()) return;

    const qreal size = std::clamp(fontSize, 4.0, 512.0);
    const Qt::Alignment align = static_cast<Qt::Alignment>(alignment);
    const QColor ink = color.isValid() ? color : QColor(Qt::black);

    startObjectEdit([text, x, y, size, ink, align](NekoPic::Document::ObjectLayer &layer) {
        auto object = std::make_unique<NekoPic::Document::TextObject>(text);
        object->setFontPointSize(size);
        object->setColor(ink);
        object->setAlignment(align);

        // Place the selected point of the text box at the requested anchor.
        const QRectF box = object->bounds();
        qreal dx = 0.0;
        if (align & Qt::AlignLeft)
            dx = x - box.left();
        else if (align & Qt::AlignRight)
            dx = x - box.right();
        else
            dx = x - box.center().x();

        qreal dy = 0.0;
        if (align & Qt::AlignTop)
            dy = y - box.top();
        else if (align & Qt::AlignBottom)
            dy = y - box.bottom();
        else
            dy = y - box.center().y();

        object->setTranslation(QPointF(dx, dy));
        return layer.add(std::move(object)) != NekoPic::Document::InvalidObjectId;
    });
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
    return objects_.hitTest(QPointF(x, y), 0.0);
}
