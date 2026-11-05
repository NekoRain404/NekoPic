#include "documentcontroller.h"

#include "document/shapeobject.h"
#include "document/strokeobject.h"

#include <QPointF>
#include <QVariantList>
#include <cmath>
#include <memory>

namespace {

bool validPoint(const QPointF &point)
{
    return std::isfinite(point.x()) && std::isfinite(point.y())
        && std::abs(point.x()) <= 1e7 && std::abs(point.y()) <= 1e7;
}

bool shapeKindFromString(const QString &kind, NekoPic::Document::ShapeKind &out)
{
    using NekoPic::Document::ShapeKind;
    if (kind == QLatin1String("rectangle")) out = ShapeKind::Rectangle;
    else if (kind == QLatin1String("ellipse")) out = ShapeKind::Ellipse;
    else if (kind == QLatin1String("line")) out = ShapeKind::Line;
    else if (kind == QLatin1String("arrow")) out = ShapeKind::Arrow;
    else return false;
    return true;
}

} // namespace

void DocumentController::addBrushStroke(const QVariantList &points, double diameter,
                                        const QColor &color)
{
    if (busy_ || !hasImage() || points.isEmpty()
        || points.size() > NekoPic::Document::StrokeObject::MaxSamples
        || !std::isfinite(diameter) || diameter <= 0.0 || diameter > 512.0)
        return;
    QVector<QPointF> path;
    path.reserve(points.size());
    for (const auto &value : points) {
        if (!value.canConvert<QPointF>()) return;
        const auto point = value.toPointF();
        if (!validPoint(point)) return;
        path.append(point);
    }
    const QColor ink = color.isValid() ? color : QColor(Qt::black);
    startObjectEdit([path = std::move(path), diameter, ink](NekoPic::Document::ObjectLayer &layer) {
        auto object = std::make_unique<NekoPic::Document::StrokeObject>();
        object->setPoints(std::move(path));
        object->setDiameter(diameter);
        object->setColor(ink);
        return layer.add(std::move(object)) != NekoPic::Document::InvalidObjectId;
    });
}

void DocumentController::addPolygon(const QVariantList &points, const QColor &fillColor,
                                    const QColor &strokeColor, double strokeWidth)
{
    if (busy_ || !hasImage() || points.size() < 3 || points.size() > 512)
        return;
    if (!std::isfinite(strokeWidth) || strokeWidth < 0.0 || strokeWidth > 200.0)
        return;
    QVector<QPointF> path;
    path.reserve(points.size());
    for (const auto &value : points) {
        if (!value.canConvert<QPointF>()) return;
        const auto point = value.toPointF();
        if (!validPoint(point)) return;
        path.append(point);
    }
    const QColor fill = fillColor.isValid() ? fillColor : QColor(Qt::transparent);
    const QColor stroke = strokeColor.isValid() ? strokeColor : QColor(Qt::black);
    startObjectEdit([path = std::move(path), fill, stroke, strokeWidth](
                        NekoPic::Document::ObjectLayer &layer) {
        auto object = std::make_unique<NekoPic::Document::ShapeObject>(
            NekoPic::Document::ShapeKind::Polygon);
        object->setPoints(path);
        object->setFillColor(fill);
        object->setStrokeColor(stroke);
        object->setStrokeWidth(strokeWidth);
        return layer.add(std::move(object)) != NekoPic::Document::InvalidObjectId;
    });
}

void DocumentController::addShape(const QString &kind, const QRectF &rect,
                                  const QColor &fillColor, const QColor &strokeColor,
                                  double strokeWidth, double cornerRadius)
{
    if (busy_ || !hasImage()) return;
    NekoPic::Document::ShapeKind shapeKind;
    if (!shapeKindFromString(kind, shapeKind)) return;
    if (!std::isfinite(rect.x()) || !std::isfinite(rect.y())
        || !std::isfinite(rect.width()) || !std::isfinite(rect.height())
        || !std::isfinite(strokeWidth) || !std::isfinite(cornerRadius))
        return;
    if (rect.width() <= 0.0 || rect.height() <= 0.0
        || strokeWidth < 0.0 || strokeWidth > 200.0 || cornerRadius < 0.0)
        return;
    if (std::abs(rect.x()) > 1e7 || std::abs(rect.y()) > 1e7
        || std::abs(rect.width()) > 1e7 || std::abs(rect.height()) > 1e7)
        return;
    const auto normalized = rect.normalized();
    const QColor fill = fillColor.isValid() ? fillColor : QColor(Qt::transparent);
    const QColor stroke = strokeColor.isValid() ? strokeColor : QColor(Qt::black);
    using NekoPic::Document::ShapeKind;
    startObjectEdit([=](NekoPic::Document::ObjectLayer &layer) {
        auto object = std::make_unique<NekoPic::Document::ShapeObject>(shapeKind);
        if (shapeKind == ShapeKind::Line || shapeKind == ShapeKind::Arrow) {
            object->setPoints({normalized.topLeft(), normalized.bottomRight()});
        } else {
            object->setRect(normalized);
            object->setCornerRadius(cornerRadius);
        }
        object->setFillColor(fill);
        object->setStrokeColor(stroke);
        object->setStrokeWidth(strokeWidth);
        return layer.add(std::move(object)) != NekoPic::Document::InvalidObjectId;
    });
}
