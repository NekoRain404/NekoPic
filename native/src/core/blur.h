#pragma once

#include <QImage>
#include <QList>
#include <QPointF>
#include <QRect>
#include <QString>

namespace NekoPic::Blur {

// Guard rails for a single blur request. The defaults keep one operation
// bounded to a 64 MiB-class image and a 256 px blur reach.
struct Limits
{
    int maxRadius = 256;
    qint64 maxPixels = 64LL * 1024 * 1024;
};

// Validates an image/radius pair before running a blur.
//
// Supported formats: RGB32, ARGB32, ARGB32_Premultiplied, RGBA8888,
// RGBA8888_Premultiplied, RGBA64 and RGBA64_Premultiplied. Indexed, mono,
// grayscale and floating-point formats are rejected.
//
// Returns true when the request can run and clears *error. On failure returns
// false and stores a human-readable reason in *error (when non-null).
bool withinLimits(const QImage& source, int radius, const Limits& limits = {},
                  QString* error = nullptr);

// Blurs `area` (in image pixels, clipped to the image) with a separable
// three-pass box blur that approximates a Gaussian.
//
// `radius` is the approximate blur reach: each of the three passes uses a box
// half-width of ceil(radius / 3), so a source pixel can influence up to
// 3 * ceil(radius / 3) pixels. The blur is computed over the clipped area plus
// that kernel margin (sampling real neighbouring pixels, clamped at the image
// edge), but only the clipped area is written. Pixels outside `area` are
// byte-identical to the source.
//
// Straight-alpha formats are premultiplied before blurring and unpremultiplied
// afterwards, so fully transparent pixels cannot bleed their colour into
// visible ones. Premultiplied formats are blurred in their stored form. The
// result keeps the source format, alpha semantics, colour space, DPI, device
// pixel ratio and text metadata.
//
// Invalid requests (null image, unsupported format, radius < 1 or above the
// limit, image above the pixel limit, invalid/empty area) return the unchanged
// source image. The source is never modified.
QImage applyRect(const QImage& source, const QRect& area, int radius, const Limits& limits = {});

// Blurs a round-capped, round-joined stroke through `points` (image
// coordinates). The painted band is 2 * radius pixels wide: radius is both the
// brush half-width and the blur reach, matching applyRect()'s radius.
//
// The mask uses antialiased coverage, giving a sub-pixel soft edge; there is no
// wider feather. Pixels outside the stroke's clipped bounding box stay
// untouched. At most 4096 points are accepted, each finite with
// |coordinate| <= 1e7. Invalid requests return the unchanged source image.
QImage applyStroke(const QImage& source, const QList<QPointF>& points, int radius,
                   const Limits& limits = {});

} // namespace NekoPic::Blur
