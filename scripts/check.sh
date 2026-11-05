#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:-$root/native/build-check}"
jobs="${JOBS:-2}"
qmltestrunner="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

cd "$root"

echo "== configure =="
cmake -S native -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=Debug

echo "== build (-j $jobs) =="
cmake --build "$build_dir" -j "$jobs"

echo "== c++ tests =="
ctest --test-dir "$build_dir" --output-on-failure

if [[ -x "$qmltestrunner" ]]; then
    echo "== qml tests =="
    QT_QPA_PLATFORM=offscreen "$qmltestrunner" -input native/qml/tests -silent
else
    echo "!! qmltestrunner not found at $qmltestrunner (set QMLTESTRUNNER)" >&2
    exit 1
fi

echo "== whitespace =="
git diff --check

echo "== ok =="
