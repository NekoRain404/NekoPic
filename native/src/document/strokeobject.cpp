#include "document/strokeobject.h"

#include <QPainter>
#include <QPainterPath>
#include <QPainterPathStroker>
#include <QRadialGradient>

#include <algorithm>
#include <cmath>
#include <utility>

namespace NekoPic::Document {

StrokeObject::StrokeObject()
    : DocumentObject(ObjectKind::Stroke)
{
}

void StrokeObject::setPoints(QVector<QPointF> points)
{
    if (points.size() > MaxSamples)
        points.resize(MaxSamples);
    points_ = std::move(points);
}

bool StrokeObject::addPoint(const QPointF &point)
{
    if (points_.size() >= MaxSamples)
        return false;
    points_.append(point);
    return true;
}

void StrokeObject::clearPoints()
{
    points_.clear();
}

void StrokeObject::setDiameter(qreal diameter)
{
    diameter_ = std::max<qreal>(0.0, diameter);
}

void StrokeObject::setSoftness(qreal softness)
{
    if (!std::isfinite(softness)) {
        softness_ = 0.0;
        return;
    }
    softness_ = std::clamp<qreal>(softness, 0.0, 1.0);
}

QPainterPath StrokeObject::localPath() const
{
    QPainterPath path;
    if (points_.isEmpty())
        return path;

    path.moveTo(points_.first());
    for (qsizetype i = 1; i < points_.size(); ++i)
        path.lineTo(points_.at(i));
    return path;
}

QRectF StrokeObject::localBounds() const
{
    if (points_.isEmpty())
        return {};

    if (points_.size() == 1) {
        const qreal radius = diameter_ / 2.0;
        return QRectF(points_.first() - QPointF(radius, radius),
                      QSizeF(diameter_, diameter_));
    }

    QPainterPathStroker stroker;
    stroker.setWidth(std::max<qreal>(diameter_, 0.0));
    stroker.setCapStyle(Qt::RoundCap);
    stroker.setJoinStyle(Qt::RoundJoin);
    return stroker.createStroke(localPath()).boundingRect();
}

void StrokeObject::renderLocal(QPainter &painter) const
{
    if (points_.isEmpty() || diameter_ <= 0.0 || color_.alpha() <= 0)
        return;

    painter.setRenderHint(QPainter::Antialiasing, true);

    const qreal softness = std::clamp<qreal>(softness_, 0.0, 1.0);

    if (points_.size() == 1) {
        const qreal radius = diameter_ / 2.0;
        if (softness <= 0.0) {
            painter.setPen(Qt::NoPen);
            painter.setBrush(color_);
            painter.drawEllipse(points_.first(), radius, radius);
            return;
        }
        QRadialGradient gradient(points_.first(), radius);
        QColor edge = color_;
        edge.setAlpha(0);
        gradient.setColorAt(0.0, color_);
        gradient.setColorAt(1.0 - softness, color_);
        gradient.setColorAt(1.0, edge);
        painter.setPen(Qt::NoPen);
        painter.setBrush(gradient);
        painter.drawEllipse(points_.first(), radius, radius);
        return;
    }

    const QPainterPath path = localPath();

    if (softness <= 0.0) {
        painter.setPen(QPen(color_, diameter_, Qt::SolidLine, Qt::RoundCap,
                            Qt::RoundJoin));
        painter.setBrush(Qt::NoBrush);
        painter.drawPath(path);
        return;
    }

    // Feather by compositing concentric round-capped strokes. The core keeps
    // the width fraction (1 - 0.9 * softness), so a fully soft brush still has
    // a small solid centre; each ring adds coverage outward while staying
    // inside the hard-brush bounds. Per-layer alpha is chosen so the centre
    // accumulates to the requested ink alpha; capping it at 0.5 keeps a 100%
    // opaque brush visibly soft at the rim.
    constexpr int kLayers = 10;
    // Mean of the (0.25 + 0.75 * t) weights below; dividing by it keeps the
    // centre coverage equal to the requested alpha while the rim receives only
    // a quarter of the per-layer ink.
    constexpr qreal kMeanWeight = 0.625;
    const qreal alpha = std::clamp<qreal>(color_.alphaF(), 0.0, 1.0);
    const qreal baseAlpha = std::min<qreal>(
        0.5, 1.0 - std::pow(1.0 - alpha, 1.0 / kLayers));
    const qreal core = 1.0 - softness * 0.9;
    painter.setBrush(Qt::NoBrush);
    for (int i = 0; i < kLayers; ++i) {
        const qreal t = kLayers > 1 ? qreal(i) / qreal(kLayers - 1) : 1.0;
        const qreal width = diameter_ * (1.0 - (1.0 - core) * t);
        // Softness changes only how far each ring reaches; the weights keep
        // the centre coverage equal to the requested ink alpha at every level.
        const qreal layerAlpha = std::min<qreal>(
            1.0, baseAlpha * (0.25 + 0.75 * t) / kMeanWeight);
        QColor layer = color_;
        layer.setAlphaF(layerAlpha);
        painter.setPen(QPen(layer, width, Qt::SolidLine, Qt::RoundCap,
                            Qt::RoundJoin));
        painter.drawPath(path);
    }
}

bool StrokeObject::hitTestLocal(const QPointF &localPoint, qreal localTolerance) const
{
    if (points_.isEmpty())
        return false;

    if (points_.size() == 1) {
        const QPointF delta = localPoint - points_.first();
        const qreal reach = diameter_ / 2.0 + localTolerance;
        return std::hypot(delta.x(), delta.y()) <= reach;
    }

    QPainterPathStroker stroker;
    stroker.setWidth(std::max<qreal>(diameter_, 0.0) + 2.0 * localTolerance);
    stroker.setCapStyle(Qt::RoundCap);
    stroker.setJoinStyle(Qt::RoundJoin);
    return stroker.createStroke(localPath()).contains(localPoint);
}

std::unique_ptr<DocumentObject> StrokeObject::cloneImpl() const
{
    return std::make_unique<StrokeObject>(*this);
}

} // namespace NekoPic::Document
