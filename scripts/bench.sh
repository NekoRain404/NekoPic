#!/usr/bin/env bash
# Build and run the NekoPic pipeline benchmark.
#
#   scripts/bench.sh                 # full run (default)
#   scripts/bench.sh --quick         # smoke-sized run
#   scripts/bench.sh --csv native/bench/results.csv
#   NEKOPIC_BENCH_BUILD_DIR=/tmp/bench scripts/bench.sh --quick
#   scripts/bench.sh --no-build --json native/bench/results.json
#
# The script configures a Release build in native/build-bench (ignored by Git),
# builds only the bench target, then runs the harness. Extra arguments are
# forwarded unchanged.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_dir="${NEKOPIC_BENCH_BUILD_DIR:-${repo_root}/native/build-bench}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

build=1
if [[ "${1:-}" == "--no-build" ]]; then
    build=0
    shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [[ "${build}" == "1" ]]; then
    cmake -S "${repo_root}/native" -B "${build_dir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "${build_dir}" --target bench_pipeline -j "${jobs}"
fi

exec "${build_dir}/bench_pipeline" "$@"
