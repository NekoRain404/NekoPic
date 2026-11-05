#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:-$root/native/build-sanitize}"
jobs="${JOBS:-2}"

cd "$root"
flags="-fsanitize=address,undefined -fno-omit-frame-pointer -g"

echo "== configure sanitizers =="
cmake -S native -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"

echo "== build (-j $jobs) =="
cmake --build "$build_dir" -j "$jobs"

echo "== c++ tests under ASan/UBSan =="
# The GTK platform theme leaks singleton data at exit; keep ASan focused on us.
export QT_QPA_PLATFORMTHEME=
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
ctest --test-dir "$build_dir" --output-on-failure

echo "== ok =="
