#!/usr/bin/env bash
# Build a single-file NekoPic AppImage from a Release build.
#
#   scripts/build-appimage.sh                 # native/build-appimage
#   scripts/build-appimage.sh --build-dir /tmp/nekopic-appimage
#   scripts/build-appimage.sh --output-dir /tmp/nekopic-artifacts
#   scripts/build-appimage.sh --no-build      # reuse an existing build tree
#   scripts/build-appimage.sh --stage-only    # AppDir only, no AppImage tools
#
# Dependency deployment needs linuxdeploy and linuxdeploy-plugin-qt (Qt 6).
# appimagetool is used when present; otherwise linuxdeploy's AppImage output
# plugin is used. If the tools are missing the script still stages and
# validates an AppDir, prints installation instructions and produces no
# AppImage rather than a broken artifact.
set -euo pipefail

# AppImage tools ship an old binutils; on rolling distros their strip cannot
# read newer .relr.dyn sections. Keep the libraries intact by default, and use
# the extract-and-run fallback when FUSE is unavailable.
export NO_STRIP="${NO_STRIP:-1}"
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
build_dir="${NEKOPIC_APPIMAGE_BUILD_DIR:-${repo_root}/native/build-appimage}"
output_dir=""
run_build=1
stage_only=0
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf 'build-appimage.sh: %s\n' "$*" >&2
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
        --output-dir)
            (($# >= 2)) || die "--output-dir needs a value"
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#*=}"
            shift
            ;;
        --jobs|-j)
            (($# >= 2)) || die "$1 needs a value"
            jobs="$2"
            shift 2
            ;;
        --no-build)
            run_build=0
            shift
            ;;
        --stage-only)
            stage_only=1
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

[[ "${jobs}" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"

if [[ "${build_dir}" != /* ]]; then
    build_dir="${repo_root}/${build_dir}"
fi
mkdir -p "${build_dir}"
build_dir="$(cd -- "${build_dir}" && pwd -P)"
case "${build_dir}" in
    /|"${repo_root}"|"${repo_root}/native")
        die "refusing to use ${build_dir} as a build directory"
        ;;
esac

if [[ -z "${output_dir}" ]]; then
    output_dir="${build_dir}/packages"
elif [[ "${output_dir}" != /* ]]; then
    output_dir="${repo_root}/${output_dir}"
fi
mkdir -p "${output_dir}"
output_dir="$(cd -- "${output_dir}" && pwd -P)"
case "${output_dir}" in
    /|"${repo_root}"|"${repo_root}/native"|"${build_dir}")
        die "refusing to use ${output_dir} as an output directory"
        ;;
esac

version="$(sed -n 's/^project(NekoPic VERSION \([0-9][0-9.]*\).*/\1/p' \
    "${repo_root}/native/CMakeLists.txt" | head -n 1)"
[[ -n "${version}" ]] || die "could not read the project version from native/CMakeLists.txt"
arch="$(uname -m)"
appdir="${build_dir}/AppDir"

if [[ "${run_build}" == "1" ]]; then
    generator_args=()
    if command -v ninja >/dev/null 2>&1; then
        generator_args=(-G Ninja)
    fi
    echo "== configure Release (${build_dir}) =="
    configure_args=(
        -S "${repo_root}/native"
        -B "${build_dir}"
        "${generator_args[@]}"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_TESTING=OFF
        -DNEKOPIC_BUILD_QML_TESTS=OFF
    )
    if cmake --help 2>/dev/null | grep -q -- '--fresh'; then
        cmake --fresh "${configure_args[@]}"
    else
        cmake "${configure_args[@]}"
    fi
    echo "== build (-j ${jobs}) =="
    cmake --build "${build_dir}" --parallel "${jobs}"
fi

[[ -f "${build_dir}/CMakeCache.txt" ]] \
    || die "missing ${build_dir}/CMakeCache.txt; run without --no-build first"

echo "== stage AppDir (${appdir}) =="
rm -rf -- "${appdir}"
mkdir -p "${appdir}"
DESTDIR="${appdir}" cmake --install "${build_dir}" --prefix /usr

# appimagetool expects the desktop file and icon at the AppDir root.
install -m644 "${repo_root}/packaging/nekopic.desktop" "${appdir}/nekopic.desktop"
install -m644 "${repo_root}/packaging/icons/hicolor/512x512/apps/nekopic.png" \
    "${appdir}/nekopic.png"
cp "${appdir}/nekopic.png" "${appdir}/.DirIcon"
install -m644 "${repo_root}/packaging/nekopic.svg" "${appdir}/nekopic.svg"
install -m755 "${repo_root}/packaging/appimage/AppRun" "${appdir}/AppRun"

# Basic AppDir checks that do not require linuxdeploy.
[[ -x "${appdir}/AppRun" ]] || die "AppRun is not executable"
[[ -f "${appdir}/nekopic.desktop" ]] || die "missing AppDir desktop file"
[[ -f "${appdir}/nekopic.png" ]] || die "missing AppDir root icon"
grep -q '^Icon=nekopic$' "${appdir}/nekopic.desktop" \
    || die "AppDir desktop file does not reference Icon=nekopic"
for size in 16 24 32 48 64 128 256 512; do
    [[ -f "${appdir}/usr/share/icons/hicolor/${size}x${size}/apps/nekopic.png" ]] \
        || die "missing ${size}x${size} hicolor icon in AppDir"
done
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "${appdir}/nekopic.desktop"
fi
if command -v identify >/dev/null 2>&1; then
    actual="$(identify -format '%wx%h' "${appdir}/nekopic.png")"
    [[ "${actual}" == "512x512" ]] || die "AppDir icon is ${actual}, expected 512x512"
fi

if [[ "${stage_only}" == "1" ]]; then
    echo
    echo "AppDir staged and validated: ${appdir}"
    echo "No AppImage was produced (--stage-only)."
    exit 0
fi

missing_tools=()
command -v linuxdeploy >/dev/null 2>&1 || missing_tools+=(linuxdeploy)
command -v linuxdeploy-plugin-qt >/dev/null 2>&1 || missing_tools+=(linuxdeploy-plugin-qt)
if ((${#missing_tools[@]} > 0)); then
    cat >&2 <<EOF

AppImage tooling is incomplete; no AppImage was produced.
Missing: ${missing_tools[*]}

Install linuxdeploy and linuxdeploy-plugin-qt (Qt 6), make them executable
and put both on PATH:
  https://github.com/linuxdeploy/linuxdeploy/releases
  https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases
appimagetool is optional:
  https://github.com/AppImage/appimagetool/releases

The staged AppDir is available at:
  ${appdir}
Re-run with --stage-only to validate staging without packaging.
EOF
    exit 1
fi

echo "== deploy Qt dependencies =="
export QMAKE="${QMAKE:-qmake6}"
# The app embeds QML in its qrc, so qmlimportscanner cannot see imports from
# the binary alone. Point the Qt plugin at the source tree so QtQuick,
# Controls, Layouts and their transitive modules are bundled.
export QML_SOURCES_PATHS="${QML_SOURCES_PATHS:-$repo_root/native/qml}"
# Platform plugins are loaded dynamically, so the plugin cannot infer them
# from the executable. Wayland is required on the target desktop; xcb and
# offscreen keep XWayland and CI/offscreen verification working.
export EXTRA_PLATFORM_PLUGINS="${EXTRA_PLATFORM_PLUGINS:-libqwayland.so;libqxcb.so;libqoffscreen.so}"
export EXTRA_QT_MODULES="${EXTRA_QT_MODULES:-waylandclient}"
linuxdeploy --appdir "${appdir}" \
    --executable "${appdir}/usr/bin/nekopic" \
    --desktop-file "${appdir}/nekopic.desktop" \
    --icon-file "${appdir}/nekopic.png" \
    --plugin qt

# The Qt plugin does not always copy the Wayland graphics integration
# plugins (EGL/shm), but the Wayland platform plugin needs them to map a
# window. Copy the host plugin directory when present.
qt_plugins="$("$QMAKE" -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
if [ -n "$qt_plugins" ] && [ -d "$qt_plugins/wayland-graphics-integration-client" ]; then
    mkdir -p "$appdir/usr/plugins/wayland-graphics-integration-client"
    cp -a "$qt_plugins/wayland-graphics-integration-client/." \
        "$appdir/usr/plugins/wayland-graphics-integration-client/"
fi

# Use our AppRun template even if linuxdeploy generated its own.
install -m755 "${repo_root}/packaging/appimage/AppRun" "${appdir}/AppRun"

rm -rf -- "${output_dir}"
mkdir -p "${output_dir}"
output_file="${output_dir}/NekoPic-${version}-${arch}.AppImage"

echo "== package AppImage =="
if command -v appimagetool >/dev/null 2>&1; then
    ARCH="${arch}" appimagetool "${appdir}" "${output_file}"
else
    echo "appimagetool not found; falling back to linuxdeploy --output appimage"
    (
        cd "${output_dir}"
        linuxdeploy --appdir "${appdir}" --output appimage
    )
    generated="$(find "${output_dir}" -maxdepth 1 -type f -name '*.AppImage' \
        -printf '%p\n' | head -n 1)"
    [[ -n "${generated}" ]] || die "linuxdeploy did not produce an AppImage"
    mv -- "${generated}" "${output_file}"
fi

[[ -f "${output_file}" ]] || die "missing expected AppImage ${output_file}"
mapfile -t images < <(find "${output_dir}" -maxdepth 1 -type f -name '*.AppImage' \
    -printf '%p\n')
((${#images[@]} == 1)) || die "expected exactly one .AppImage, found ${#images[@]}"

(
    cd "${output_dir}"
    sha256sum -- "$(basename "${output_file}")" > SHA256SUMS
)

echo
echo "== artifact =="
ls -lh "${output_file}"
echo
echo "== checksum =="
cat "${output_dir}/SHA256SUMS"
