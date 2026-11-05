#pragma once

// Internal scanline-parallelism helper for core image algorithms.
//
// It deliberately uses std::thread rather than Qt's thread pool so that the
// core library stays framework-light and gains no link dependency. Each worker
// owns a disjoint half-open range of scanlines, writes only its own rows, and
// the calling thread participates. `apply`'s controller serializes adjustment
// workers, while filter previews can run concurrently; a per-call cap of eight
// workers keeps that worst case bounded.

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <exception>
#include <thread>
#include <vector>

namespace NekoPic::Detail {

// Images below this size (or with a single scanline) stay on the serial path;
// thread start-up would cost more than it saves.
constexpr std::int64_t kRowParallelMinPixels = 1024 * 1024;
// Very narrow images would put several workers on the same cache line even
// though their rows are disjoint, so they also stay serial.
constexpr std::int64_t kRowParallelMinWidth = 64;
constexpr int kRowParallelMaxWorkers = 8;

inline int hardwareWorkerLimit()
{
    const unsigned hardware = std::thread::hardware_concurrency();
    if (hardware <= 1)
        return 1;
    return static_cast<int>(std::min<unsigned>(hardware, kRowParallelMaxWorkers));
}

// Worker count used by `parallelRows`; 1 selects the serial path.
inline int rowWorkerCount(std::int64_t width, std::int64_t height)
{
    if (width < kRowParallelMinWidth || height < 2)
        return 1;
    if (width * height < kRowParallelMinPixels)
        return 1;
    const int limit = hardwareWorkerLimit();
    if (limit <= 1)
        return 1;
    return std::min<int>(limit, static_cast<int>(height));
}

// Runs fn(begin, end) over disjoint half-open scanline ranges. Worker
// exceptions are captured and rethrown on the calling thread after all
// workers have joined, so none can escape a worker thread. If thread creation
// fails, the remaining rows are finished on the calling thread.
template <typename Fn>
void parallelRows(int height, int workers, Fn &&fn)
{
    if (height <= 0)
        return;
    if (workers <= 1 || height < 2) {
        fn(0, height);
        return;
    }

    workers = std::min(workers, height);
    const int chunk = (height + workers - 1) / workers;

    std::atomic<bool> failed{false};
    std::exception_ptr failure;

    auto run = [&](int begin, int end) {
        try {
            fn(begin, end);
        } catch (...) {
            if (!failed.exchange(true, std::memory_order_acq_rel))
                failure = std::current_exception();
        }
    };

    std::vector<std::thread> threads;
    threads.reserve(static_cast<std::size_t>(workers - 1));
    int begin = 0;
    for (int worker = 1; worker < workers && begin < height; ++worker) {
        const int end = std::min(height, begin + chunk);
        try {
            threads.emplace_back(run, begin, end);
        } catch (...) {
            break; // finish the remainder on the calling thread
        }
        begin = end;
    }

    run(begin, height);
    for (auto &thread : threads)
        thread.join();

    if (failure)
        std::rethrow_exception(failure);
}

} // namespace NekoPic::Detail
