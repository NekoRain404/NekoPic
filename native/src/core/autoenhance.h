#pragma once

#include "core/histogram.h"

namespace NekoPic::AutoEnhance {

// Conservative suggestions in UI units (-100..100). The controller applies
// them as one undoable adjustment transaction.
struct Suggestion {
    double exposure = 0.0;
    double contrast = 0.0;
    double saturation = 0.0;
    double blacks = 0.0;
    double whites = 0.0;
    bool isNoOp() const;
};

Suggestion suggest(const Histogram::Data &histogram);

} // namespace NekoPic::AutoEnhance
