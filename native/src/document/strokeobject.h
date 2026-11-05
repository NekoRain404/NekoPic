#pragma once

#include "document/object.h"

#include <QColor>
#include <QVector>

class QPainterPath;

namespace NekoPic::Document {

// Freehand brush stroke: one sampled point list plus a round brush.
//
// Sampling contract: points are document pixels. The sample budget is a hard
// limit (4096 points per object); tools must split a longer stroke into
// multiple objects or simplify input (the pressure/distance filter that
// produces the samples is a tool concern, not part of this object). Rendering
// uses round caps and joins so single points and segment ends stay circular.
class StrokeObject final : public DocumentObject {
public:
    static constexpr qsizetype MaxSamples = 4096;

    StrokeObject();

    QVector<QPointF> points() const { return points_; }
    void setPoints(QVector<QPointF> points); // truncates to MaxSamples

    // Returns false when the budget is exhausted; the point is not appended.
    bool addPoint(const QPointF &point);
    void clearPoints();
    qsizetype sampleCount() const { return points_.size(); }
    static constexpr qsizetype sampleLimit() { return MaxSamples; }

    qreal diameter() const { return diameter_; }
    void setDiameter(qreal diameter);

    QColor color() const { return color_; }
    void setColor(const QColor &color) { color_ = color; }

protected:
    QRectF localBounds() const override;
    void renderLocal(QPainter &painter) const override;
    bool hitTestLocal(const QPointF &localPoint, qreal localTolerance) const override;
    std::unique_ptr<DocumentObject> cloneImpl() const override;

private:
    QPainterPath localPath() const;

    QVector<QPointF> points_;
    qreal diameter_ = 8.0;
    QColor color_ = QColor(Qt::black);
};

} // namespace NekoPic::Document
