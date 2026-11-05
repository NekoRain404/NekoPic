#include "document/strokeobject.h"

#include <QPainter>
#include <QPainterPath>
#include <QPainterPathStroker>

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

    if (points_.size() == 1) {
        painter.setPen(Qt::NoPen);
        painter.setBrush(color_);
        const qreal radius = diameter_ / 2.0;
        painter.drawEllipse(points_.first(), radius, radius);
        return;
    }

    painter.setPen(QPen(color_, diameter_, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter.setBrush(Qt::NoBrush);
    painter.drawPath(localPath());
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
