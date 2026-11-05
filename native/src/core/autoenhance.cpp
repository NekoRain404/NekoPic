#include "autoenhance.h"

#include <algorithm>
#include <cmath>

namespace NekoPic::AutoEnhance {
namespace {

double percentile(const Histogram::Data &histogram, double fraction)
{
    quint64 total = 0;
    for (const auto count : histogram.luma) total += count;
    if (total == 0) return 128.0;
    const auto target = static_cast<quint64>(std::llround(fraction * double(total)));
    quint64 seen = 0;
    for (int i = 0; i < 256; ++i) {
        seen += histogram.luma[i];
        if (seen >= target) return i;
    }
    return 255.0;
}

double median(const Histogram::Data &histogram)
{
    return percentile(histogram, 0.5);
}

} // namespace

bool Suggestion::isNoOp() const
{
    return std::abs(exposure) < 0.5 && std::abs(contrast) < 0.5
        && std::abs(saturation) < 0.5 && std::abs(blacks) < 0.5 && std::abs(whites) < 0.5;
}

Suggestion suggest(const Histogram::Data &histogram)
{
    Suggestion result;
    if (histogram.sampledPixels == 0) return result;

    const double low = percentile(histogram, 0.01);
    const double high = percentile(histogram, 0.99);
    const double mid = median(histogram);
    const double spread = std::max(0.0, high - low);

    // Pull the midtone toward a comfortable target without clipping extremes.
    const double targetMid = 128.0;
    const double exposureStops = std::clamp((targetMid - mid) / 255.0 * 1.2, -0.6, 0.6);
    result.exposure = std::clamp(exposureStops * 50.0, -35.0, 35.0);

    // Low dynamic range benefits from contrast; already-wide images do not.
    if (spread < 180.0) result.contrast = std::clamp((180.0 - spread) / 2.4, 0.0, 28.0);
    if (spread > 235.0) result.contrast = -std::clamp((spread - 235.0) * 0.6, 0.0, 12.0);

    // Recover crushed/extended endpoints conservatively.
    if (low > 12.0) result.blacks = -std::clamp((low - 12.0) * 0.8, 0.0, 20.0);
    if (high < 243.0) result.whites = std::clamp((243.0 - high) * 0.8, 0.0, 20.0);

    // A washed-out image (narrow spread around the middle) gets a gentle lift.
    if (spread < 120.0) result.saturation = std::clamp((120.0 - spread) * 0.25, 0.0, 18.0);

    return result;
}

} // namespace NekoPic::AutoEnhance
