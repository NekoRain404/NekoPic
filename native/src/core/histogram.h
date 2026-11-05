#pragma once

#include <QImage>

#include <array>
#include <cstdint>

namespace NekoPic::Histogram {

struct Data {
    std::array<quint32, 256> red{};
    std::array<quint32, 256> green{};
    std::array<quint32, 256> blue{};
    std::array<quint32, 256> luma{};
    quint64 sampledPixels = 0;
    quint64 totalPixels = 0;
};

// Computes a 256-bin histogram, sampling evenly when the image exceeds
// maxSamples so the GUI thread stays responsive on large images.
Data compute(const QImage &image, quint64 maxSamples = 1u << 20);

} // namespace NekoPic::Histogram
