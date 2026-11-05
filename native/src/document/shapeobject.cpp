#include "document/shapeobject.h"

#include <QPainter>
#include <QPainterPathStroker>
#include <QPolygonF>
#include <QtMath>

#include <algorithm>
#include <cmath>

namespace NekoPic::Document {

namespace {

constexpr qreal MinArrowHeadLength = 6.0;
constexpr qreal MaxArrowHeadLength = 40.0;

QRectF pointBounds(const QVector<QPointF> &points)
{
    if (points.isEmpty())
        return {};
    qreal minX = points.first().x();
    qreal maxX = minX;
    qreal minY = points.first().y();
    qreal maxY = minY;
    for (const QPointF &point : points) {
        minX = std::min(minX, point.x());
        maxX = std::max(maxX, point.x());
        minY = std::min(minY, point.y());
        maxY = std::max(maxY, point.y());
    }
    return QRectF(QPointF(minX, minY), QPointF(maxX, maxY));
}

} // namespace

namespace ShapeGeometry {

QRectF squareFromDrag(const QPointF &anchor, const QPointF &current)
{
    const qreal dx = current.x() - anchor.x();
    const qreal dy = current.y() - anchor.y();
    const qreal side = std::max(std::abs(dx), std::abs(dy));
    const qreal signX = dx < 0.0 ? -1.0 : 1.0;
    const qreal signY = dy < 0.0 ? -1.0 : 1.0;
    const QPointF corner(anchor.x() + signX * side, anchor.y() + signY * side);
    return QRectF(anchor, corner).normalized();
}

QPointF snapToAngle(const QPointF &anchor, const QPointF &current, qreal stepDegrees)
{
    const qreal dx = current.x() - anchor.x();
    const qreal dy = current.y() - anchor.y();
    const qreal radius = std::hypot(dx, dy);
    if (radius <= 0.0 || stepDegrees <= 0.0)
        return current;

    const qreal stepRadians = qDegreesToRadians(stepDegrees);
    const qreal snapped = std::round(std::atan2(dy, dx) / stepRadians) * stepRadians;
    return anchor + QPointF(radius * std::cos(snapped), radius * std::sin(snapped));
}

} // namespace ShapeGeometry

ShapeObject::ShapeObject()
    : DocumentObject(ObjectKind::Shape)
    , shape_(ShapeKind::Rectangle)
{
}

ShapeObject::ShapeObject(ShapeKind shape)
    : ShapeObject()
{
    shape_ = shape;
}

void ShapeObject::setShape(ShapeKind shape)
{
    shape_ = shape;
}

void ShapeObject::setRect(const QRectF &rect)
{
    rect_ = rect.normalized();
}

void ShapeObject::setPoints(const QVector<QPointF> &points)
{
    points_ = points;
}

void ShapeObject::setStrokeWidth(qreal width)
{
    strokeWidth_ = std::max<qreal>(0.0, width);
}

void ShapeObject::setCornerRadius(qreal radius)
{
    cornerRadius_ = std::max<qreal>(0.0, radius);
}

QPainterPath ShapeObject::fillPath() const
{
    QPainterPath path;
    switch (shape_) {
    case ShapeKind::Rectangle: {
        const QRectF r = rect_.normalized();
        const qreal radius = std::min(cornerRadius_, std::min(r.width(), r.height()) / 2.0);
        if (radius > 0.0)
            path.addRoundedRect(r, radius, radius);
        else
            path.addRect(r);
        break;
    }
    case ShapeKind::Ellipse:
        path.addEllipse(rect_.normalized());
        break;
    case ShapeKind::Polygon:
        if (points_.size() >= 3) {
            QPolygonF polygon;
            polygon.reserve(points_.size());
            for (const QPointF &point : points_)
                polygon.append(point);
            path.addPolygon(polygon);
            path.closeSubpath();
        }
        break;
    case ShapeKind::Line:
    case ShapeKind::Arrow:
        break;
    }
    return path;
}

QPainterPath ShapeObject::shaftPath() const
{
    QPainterPath path;
    if (points_.isEmpty())
        return path;

    path.moveTo(points_.first());
    if (points_.size() >= 2)
        path.lineTo(points_.at(1));
    return path;
}

QPainterPath ShapeObject::strokePath() const
{
    switch (shape_) {
    case ShapeKind::Rectangle:
    case ShapeKind::Ellipse:
        return fillPath();
    case ShapeKind::Polygon:
        if (points_.size() >= 3)
            return fillPath();
        return shaftPath();
    case ShapeKind::Line:
    case ShapeKind::Arrow:
        return shaftPath();
    }
    return {};
}

QPainterPath ShapeObject::arrowHeadPath() const
{
    if (points_.size() < 2)
        return {};

    const QPointF tip = points_.at(1);
    const QPointF delta = tip - points_.at(0);
    const qreal length = std::hypot(delta.x(), delta.y());
    if (length <= 0.0)
        return {};

    const QPointF direction = delta / length;
    const QPointF normal(-direction.y(), direction.x());
    const qreal headLength = std::min(
        length, std::clamp(length * 0.25, MinArrowHeadLength, MaxArrowHeadLength));
    const qreal halfWidth = std::max(headLength * 0.5, strokeWidth_ * 1.5);
    const QPointF base = tip - direction * headLength;

    QPainterPath head;
    head.moveTo(tip);
    head.lineTo(base + normal * halfWidth);
    head.lineTo(base - normal * halfWidth);
    head.closeSubpath();
    return head;
}

QPainterPath ShapeObject::localPath() const
{
    QPainterPath path = strokePath();
    if (shape_ == ShapeKind::Arrow) {
        const QPainterPath head = arrowHeadPath();
        if (!head.isEmpty())
             path = path.isEmpty() ? head : path.united(head);
    }
    return path;
}

QRectF ShapeObject::localBounds() const
{
    QRectF bounds;
    const auto unite = [&bounds](const QRectF &rect) {
        if (rect.isNull())
            return;
        bounds = bounds.isNull() ? rect : bounds.united(rect);
    };

    unite(fillPath().boundingRect());

    const bool hasStroke = strokeWidth_ > 0.0 && strokeColor_.alpha() > 0;
    const QPainterPath outline = strokePath();
    if (hasStroke && !outline.isEmpty()) {
        QPainterPathStroker stroker;
        stroker.setWidth(strokeWidth_);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::MiterJoin);
        unite(stroker.createStroke(outline).boundingRect());
    }

    if (shape_ == ShapeKind::Arrow) {
        const QPainterPath head = arrowHeadPath();
        if (!head.isEmpty() && strokeColor_.alpha() > 0)
            unite(head.boundingRect());
    }

    // Degenerate shapes still get a usable selection box.
    if (bounds.isNull()) {
        if (shape_ == ShapeKind::Rectangle || shape_ == ShapeKind::Ellipse)
            unite(rect_.normalized());
        else
            unite(pointBounds(points_));
    }

    return bounds;
}

void ShapeObject::renderLocal(QPainter &painter) const
{
    painter.setRenderHint(QPainter::Antialiasing, true);

    const bool hasStroke = strokeWidth_ > 0.0 && strokeColor_.alpha() > 0;
    const QPen strokePen = hasStroke
        ? QPen(strokeColor_, strokeWidth_, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin)
        : QPen(Qt::NoPen);
    const QBrush fillBrush = fillColor_.alpha() > 0 ? QBrush(fillColor_) : QBrush(Qt::NoBrush);

    switch (shape_) {
    case ShapeKind::Arrow: {
        const QPainterPath shaft = shaftPath();
        if (!shaft.isEmpty()) {
            painter.setPen(strokePen);
            painter.setBrush(Qt::NoBrush);
            painter.drawPath(shaft);
        }
        const QPainterPath head = arrowHeadPath();
        if (!head.isEmpty() && strokeColor_.alpha() > 0) {
            painter.setPen(Qt::NoPen);
            painter.setBrush(strokeColor_);
            painter.drawPath(head);
        }
        break;
    }
    case ShapeKind::Line:
        painter.setPen(strokePen);
        painter.setBrush(Qt::NoBrush);
        painter.drawPath(shaftPath());
        break;
    case ShapeKind::Rectangle:
    case ShapeKind::Ellipse:
    case ShapeKind::Polygon:
        painter.setPen(strokePen);
        painter.setBrush(fillBrush);
        painter.drawPath(fillPath());
        break;
    }
}

bool ShapeObject::hitTestLocal(const QPointF &localPoint, qreal localTolerance) const
{
    const auto strokedContains = [&](const QPainterPath &path, qreal width) {
        if (path.isEmpty())
            return false;
        QPainterPathStroker stroker;
        stroker.setWidth(std::max<qreal>(width, 0.0) + 2.0 * localTolerance);
        stroker.setCapStyle(Qt::RoundCap);
        stroker.setJoinStyle(Qt::RoundJoin);
        return stroker.createStroke(path).contains(localPoint);
    };

    if (shape_ == ShapeKind::Line || shape_ == ShapeKind::Arrow) {
        if (strokedContains(shaftPath(), strokeWidth_))
            return true;
        if (shape_ == ShapeKind::Arrow && strokeColor_.alpha() > 0) {
            const QPainterPath head = arrowHeadPath();
            if (head.contains(localPoint) || strokedContains(head, 0.0))
                return true;
        }
        return false;
    }

    if (fillColor_.alpha() > 0) {
        const QPainterPath fill = fillPath();
        if (!fill.isEmpty() && fill.contains(localPoint))
            return true;
    }

    return strokedContains(strokePath(), strokeWidth_);
}

std::unique_ptr<DocumentObject> ShapeObject::cloneImpl() const
{
    return std::make_unique<ShapeObject>(*this);
}

} // namespace NekoPic::Document
