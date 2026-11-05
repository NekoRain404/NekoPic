#include "colorpipeline_internal.h"

namespace NekoPic::Adjustments::Internal {

// ---------------------------------------------------------------------------
// Stage 5: tone curves.
//
// The RGB composite curve runs first, then the per-channel curves. The clamp
// after the stage is unconditional in the original fused pass and is preserved
// here; dispatch applies the same clamp when the stage itself is neutral.
// ---------------------------------------------------------------------------

void applyCurveStages(Rgb& color, const StageConfig& config)
{
    const Parameters& p = config.parameters;
    double red = color.red;
    double green = color.green;
    double blue = color.blue;

    if (config.anyCurve) {
        if (config.curveActive[0]) {
            red = evaluateCurve(p.curves[0], red);
            green = evaluateCurve(p.curves[0], green);
            blue = evaluateCurve(p.curves[0], blue);
        }
        if (config.curveActive[1])
            red = evaluateCurve(p.curves[1], red);
        if (config.curveActive[2])
            green = evaluateCurve(p.curves[2], green);
        if (config.curveActive[3])
            blue = evaluateCurve(p.curves[3], blue);
    }
    red = clamp01(red);
    green = clamp01(green);
    blue = clamp01(blue);

    color.red = red;
    color.green = green;
    color.blue = blue;
}

} // namespace NekoPic::Adjustments::Internal
