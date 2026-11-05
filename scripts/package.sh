#!/usr/bin/env bash
# Build a clean Release tree and produce distributable NekoPic packages.
#
#   scripts/package.sh                     # native/build-package, TGZ + DEB
#   scripts/package.sh --build-dir /tmp/nekopic-package
#   scripts/package.sh --no-tests          # skip ctest
#   scripts/package.sh --generators "TGZ"  # one or more CPack generators
#   scripts/package.sh --no-build          # package an existing build tree
#   JOBS=8 scripts/package.sh
#
# The script never touches the source tree; packages land in
# <build-dir>/packages and their absolute paths are printed at the end.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
build_dir="${NEKOPIC_PACKAGE_BUILD_DIR:-${repo_root}/native/build-package}"
generators="TGZ;DEB"
run_tests=1
run_build=1
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf 'package.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --build-dir)
            (($# >= 2)) || die "--build-dir needs a value"
            build_dir="$2"
            shift 2
            ;;
        --build-dir=*)
            build_dir="${1#*=}"
            shift
            ;;
        --generators)
            (($# >= 2)) || die "--generators needs a value"
            generators="$2"
            shift 2
            ;;
        --generators=*)
            generators="${1#*=}"
            shift
            ;;
        --jobs|-j)
            (($# >= 2)) || die "$1 needs a value"
            jobs="$2"
            shift 2
            ;;
        --no-tests)
            run_tests=0
            shift
            ;;
        --no-build)
            run_build=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (use --help)"
            ;;
    esac
done

[[ -n "${generators}" ]] || die "--generators must not be empty"
[[ "${jobs}" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"

# Resolve relative build directories against the repository root so the caller
# can run the script from anywhere.
if [[ "${build_dir}" != /* ]]; then
    build_dir="${repo_root}/${build_dir}"
fi
mkdir -p "${build_dir}"
build_dir="$(cd -- "${build_dir}" && pwd -P)"
# Refuse obviously destructive or nonsensical targets, including paths that
# only reach them through ".." or symlinks.
case "${build_dir}" in
    /|"${repo_root}"|"${repo_root}/native")
        die "refusing to use ${build_dir} as a build directory"
        ;;
esac

package_dir="${build_dir}/packages"
rm -rf -- "${package_dir}"
mkdir -p "${package_dir}"

if [[ "${run_build}" == "1" ]]; then
    generator_args=()
    if command -v ninja >/dev/null 2>&1; then
        generator_args=(-G Ninja)
    fi

    testing=OFF
    [[ "${run_tests}" == "1" ]] && testing=ON

    echo "== configure Release (${build_dir}) =="
    configure_args=(
        -S "${repo_root}/native"
        -B "${build_dir}"
        "${generator_args[@]}"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_TESTING="${testing}"
        -DNEKOPIC_BUILD_QML_TESTS=OFF
    )
    # --fresh (CMake >= 3.24) discards stale cache entries, including paths
    # from another machine, without deleting the caller's directory.
    if cmake --help 2>/dev/null | grep -q -- '--fresh'; then
        cmake --fresh "${configure_args[@]}"
    else
        cmake "${configure_args[@]}"
    fi

    echo "== build (-j ${jobs}) =="
    cmake --build "${build_dir}" --parallel "${jobs}"
fi

if [[ "${run_tests}" == "1" && "${run_build}" == "1" ]]; then
    echo "== ctest =="
    ctest --test-dir "${build_dir}" --output-on-failure
fi

[[ -f "${build_dir}/CPackConfig.cmake" ]] \
    || die "missing ${build_dir}/CPackConfig.cmake; run without --no-build first"

echo "== cpack (${generators}) =="
cpack --config "${build_dir}/CPackConfig.cmake" \
    -G "${generators}" \
    -B "${package_dir}"

mapfile -t artifacts < <(find "${package_dir}" -maxdepth 1 -type f -printf '%p\n' | sort)
((${#artifacts[@]} > 0)) || die "cpack produced no artifacts in ${package_dir}"

echo
echo "== artifacts =="
for artifact in "${artifacts[@]}"; do
    printf '%s (%s)\n' "${artifact}" "$(du -h "${artifact}" | cut -f1)"
done
