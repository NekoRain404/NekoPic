#pragma once

#include <QImage>
#include <QString>

namespace NekoPic::Adjustments {

struct Parameters {
    double exposure = 0.0;   // Stops, clamped to [-4, 4].
    double brightness = 0.0; // Clamped to [-1, 1].
    double contrast = 0.0;   // Clamped to [-1, 1].
    double saturation = 0.0; // Clamped to [-1, 1].
    QString filterPreset;
    double filterIntensity = 1.0; // Clamped to [0, 1].
};

// Always apply preview parameters to the same unmodified source image.
QImage apply(const QImage &source, const Parameters &parameters);

} // namespace NekoPic::Adjustments
