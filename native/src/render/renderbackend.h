#pragma once

namespace NekoPic::Render {

// Extension point for future RHI compute / export backends. The CPU path is
// authoritative; GPU backends are preview-only until they pass parity tests.
enum class Backend {
    Cpu,
    Gpu,
};

} // namespace NekoPic::Render
