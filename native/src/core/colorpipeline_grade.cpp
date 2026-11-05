#include "colorpipeline_internal.h"

namespace NekoPic::Adjustments::Internal {

// ---------------------------------------------------------------------------
// Stage 6: colour grading.
//
// Gaussians weight the shadows, midtones and highlights around the pivots the
// grade balance/blending controls define. The post-stage clamp is preserved
// exactly; dispatch applies it even when grading is neutral.
// ---------------------------------------------------------------------------

void applyGradeStage(Rgb& color, const StageConfig& config)
{
    const Parameters& p = config.parameters;
    double red = color.red;
    double green = color.green;
    double blue = color.blue;

    if (config.anyGrade) {
        const double level = luma(red, green, blue);
        const double shadowWeight = std::exp(-(level * level) * config.gradeInv);
        const double midWeight = std::exp(
            -((level - config.gradePivot) * (level - config.gradePivot)) * config.gradeInv);
        const double highWeight = std::exp(-((level - 1.0) * (level - 1.0)) * config.gradeInv);
        const double sum = shadowWeight + midWeight + highWeight;
        if (sum > 0.0) {
            const auto applyZone = [&](double weight, const GradeZoneAdjustment& zone) {
                if (zone.saturation != 0.0) {
                    double zoneRed;
                    double zoneGreen;
                    double zoneBlue;
                    rgbFromHsv(zone.hue, 1.0, 1.0, zoneRed, zoneGreen, zoneBlue);
                    const double zoneLevel = luma(zoneRed, zoneGreen, zoneBlue);
                    const double amount = zone.saturation * weight * 0.5;
                    red += (zoneRed - zoneLevel) * amount;
                    green += (zoneGreen - zoneLevel) * amount;
                    blue += (zoneBlue - zoneLevel) * amount;
                }
                if (zone.luminance != 0.0) {
                    const double amount = zone.luminance * weight * 0.5;
                    red += amount;
                    green += amount;
                    blue += amount;
                }
            };
            if (config.gradeZoneActive[0])
                applyZone(shadowWeight / sum, p.grade[0]);
            if (config.gradeZoneActive[1])
                applyZone(midWeight / sum, p.grade[1]);
            if (config.gradeZoneActive[2])
                applyZone(highWeight / sum, p.grade[2]);
        }
    }
    red = clamp01(red);
    green = clamp01(green);
    blue = clamp01(blue);

    color.red = red;
    color.green = green;
    color.blue = blue;
}

} // namespace NekoPic::Adjustments::Internal
