#pragma once

#include <QImage>
#include <QList>
#include <QPointF>
#include <QRect>

namespace NekoPic::Mosaic {

struct Stroke {
    QList<QPointF> points;
    double diameter = 24.0;
};

// The grid is anchored at the image origin. Blocks average encoded RGB weighted
// by source alpha; destination alpha and fully transparent pixels are unchanged.
// Only the clipped selection is written. Indexed/mono images become RGBA64.
// blockSize <= 1 is a no-op; larger sizes clamp to 512. Invalid inputs and
// images exceeding 64M pixels / 1 GiB return the unchanged source.
QImage pixelateRect(const QImage &source, const QRect &rectangle, int blockSize);
// Connected round-capped stroke in image coordinates. At most 4096 finite
// points with |coordinate| <= 1e7; positive finite diameter clamps to 4096.
// The hard mask uses a clipped ROI and has a maximum allocation of 256 MiB.
// Strokes with estimated raster work above 256M covered pixels are no-ops.
QImage pixelateStroke(const QImage &source, const Stroke &stroke, int blockSize);

} // namespace NekoPic::Mosaic
