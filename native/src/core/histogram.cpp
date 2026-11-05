#include "histogram.h"

#include <QColor>

#include <algorithm>
#include <cmath>

namespace NekoPic::Histogram {

Data compute(const QImage &image, quint64 maxSamples)
{
    Data result;
    if (image.isNull()) return result;
    const auto source = image.convertToFormat(QImage::Format_RGBA8888);
    if (source.isNull()) return result;

    const auto width = source.width();
    const auto height = source.height();
    const quint64 pixels = quint64(width) * quint64(height);
    result.totalPixels = pixels;
    if (pixels == 0) return result;
    const quint64 limit = maxSamples == 0 ? pixels : std::min(pixels, maxSamples);
    const quint64 step = std::max<quint64>(1, (pixels + limit - 1) / limit);

    for (int y = 0; y < height; ++y) {
        const auto *row = reinterpret_cast<const uchar *>(source.constScanLine(y));
        for (int x = 0; x < width; ++x) {
            const quint64 index = quint64(y) * quint64(width) + quint64(x);
            if (index % step != 0) continue;
            const auto *pixel = row + x * 4;
            const int red = pixel[0];
            const int green = pixel[1];
            const int blue = pixel[2];
            const int luma = std::clamp(int(std::lround(0.2126 * red + 0.7152 * green
                                                     + 0.0722 * blue)), 0, 255);
            ++result.red[red];
            ++result.green[green];
            ++result.blue[blue];
            ++result.luma[luma];
            ++result.sampledPixels;
        }
    }
    return result;
}

} // namespace NekoPic::Histogram
