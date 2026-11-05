#include "documentcontroller.h"

#include "core/blur.h"

#include <cmath>
#include <utility>

namespace {
bool validCoordinate(double value)
{
    return std::isfinite(value) && std::abs(value) <= 1e7;
}

bool validRadius(int radius)
{
    return radius >= 1 && radius <= NekoPic::Blur::Limits{}.maxRadius;
}
}

void DocumentController::blurRectangle(const QRectF &area, int radius)
{
    if (busy_ || !hasImage() || !validRadius(radius)) return;
    if (!validCoordinate(area.x()) || !validCoordinate(area.y())
        || !validCoordinate(area.width()) || !validCoordinate(area.height())
        || !validCoordinate(area.right()) || !validCoordinate(area.bottom())) return;
    const auto clipped = area.normalized().intersected(QRectF(baseImage_.rect()));
    if (clipped.isEmpty()) return;
    const auto rectangle = clipped.toAlignedRect().intersected(baseImage_.rect());
    if (rectangle.isEmpty()) return;
    startPixelEdit([rectangle, radius](const QImage &base) {
        return NekoPic::Blur::applyRect(base, rectangle, radius);
    }, tr("Could not blur the image."));
}

void DocumentController::blurStroke(const QVariantList &points, int radius)
{
    if (busy_ || !hasImage() || !validRadius(radius) || points.isEmpty() || points.size() > 4096)
        return;
    QList<QPointF> path;
    path.reserve(points.size());
    for (const auto &value : points) {
        if (!value.canConvert<QPointF>()) return;
        const auto point = value.toPointF();
        if (!validCoordinate(point.x()) || !validCoordinate(point.y())) return;
        path.append(point);
    }
    startPixelEdit([path = std::move(path), radius](const QImage &base) {
        return NekoPic::Blur::applyStroke(base, path, radius);
    }, tr("Could not blur the image."));
}
