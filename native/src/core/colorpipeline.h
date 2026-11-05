#pragma once

#include "adjustments.h"

namespace NekoPic::Adjustments::Internal {

// True when any extended field can change pixels. Non-default but inactive
// fields (for example feather without a vignette, a grade hue with zero
// saturation, or a linear curve) are deliberately reported as neutral so the
// optimised legacy path stays byte-identical.
bool hasExtendedParameters(const Parameters &parameters);

// Extended pipeline. Callers must have checked hasExtendedParameters().
// Supports every QImage format handled by apply(): integer formats are
// processed in a normalized RGBA64 working buffer, floating formats use the
// same normalized buffer and are converted back to their original format.
QImage applyExtended(const QImage &source, const Parameters &parameters);

} // namespace NekoPic::Adjustments::Internal
