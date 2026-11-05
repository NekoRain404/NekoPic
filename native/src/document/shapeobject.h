#pragma once

#include "document/object.h"

#include <QColor>
#include <QPainterPath>
#include <QVector>

namespace NekoPic::Document {

enum class ShapeKind { Rectangle, Ellipse, Line, Arrow, Polygon };

// Reusable Shift-key constraints for shape drawing tools. Both helpers take
// document-space anchor/current points and return document-space results.
namespace ShapeGeometry {

// Equal-side rectangle: the longer drag axis determines the square's side,
// preserving the pointer's quadrant.
QRectF squareFromDrag(const QPointF &anchor, const QPointF &current);

// Snaps the vector anchor -> current to the nearest multiple of stepDegrees
// (45 by default for horizontal/vertical/diagonal lines), preserving length.
QPointF snapToAngle(const QPointF &anchor, const QPointF &current,
                    qreal stepDegrees = 45.0);

} // namespace ShapeGeometry

// Rectangle, ellipse, line, arrow or polygon in local document coordinates.
// Closed shapes use rect() (rectangle/ellipse) or points() (polygon); lines
// and arrows use the first two points.
class ShapeObject final : public DocumentObject {
public:
    ShapeObject();
    explicit ShapeObject(ShapeKind shape);

    ShapeKind shape() const { return shape_; }
    void setShape(ShapeKind shape);

    QRectF rect() const { return rect_; }
    void setRect(const QRectF &rect);

    QVector<QPointF> points() const { return points_; }
    void setPoints(const QVector<QPointF> &points);

    QColor fillColor() const { return fillColor_; }
    void setFillColor(const QColor &color) { fillColor_ = color; }

    QColor strokeColor() const { return strokeColor_; }
    void setStrokeColor(const QColor &color) { strokeColor_ = color; }

    qreal strokeWidth() const { return strokeWidth_; }
    void setStrokeWidth(qreal width);

    // Corner radius for rectangles, clamped to half the shorter side.
    qreal cornerRadius() const { return cornerRadius_; }
    void setCornerRadius(qreal radius);

    // Local (untransformed) outline useful for tools that need the geometry.
    QPainterPath localPath() const;

protected:
    QRectF localBounds() const override;
    void renderLocal(QPainter &painter) const override;
    bool hitTestLocal(const QPointF &localPoint, qreal localTolerance) const override;
    std::unique_ptr<DocumentObject> cloneImpl() const override;

private:
    QPainterPath fillPath() const;
    QPainterPath strokePath() const;
    QPainterPath shaftPath() const;
    QPainterPath arrowHeadPath() const;

    ShapeKind shape_;
    QRectF rect_;
    QVector<QPointF> points_;
    QColor fillColor_ = QColor(Qt::transparent);
    QColor strokeColor_ = QColor(Qt::black);
    qreal strokeWidth_ = 2.0;
    qreal cornerRadius_ = 0.0;
};

} // namespace NekoPic::Document
