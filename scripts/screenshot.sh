#!/usr/bin/env bash
# Renders the app window offscreen and writes a PNG. Uses the --screenshot
# development hook, so it does not depend on a compositor being awake.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$root/native/build-foundation}"
binary="${BINARY:-$build_dir/nekopic}"
image="${1:-$root/assets/demo.jpg}"
out="${2:-$root/artifacts/nekopic.png}"
theme="${3:-}"

if [[ ! -x "$binary" ]]; then
    echo "missing $binary; build first (cmake --build $build_dir)" >&2
    exit 1
fi
mkdir -p "$(dirname "$out")"

conf="${XDG_CONFIG_HOME:-$HOME/.config}/NekoPic/NekoPic.conf"
backup=""
if [[ -n "$theme" && -f "$conf" ]]; then
    backup="$(mktemp)"
    cp "$conf" "$backup"
    set_theme_key() {
        if grep -q "^${1}=" "$conf"; then
            sed -i "s/^${1}=.*/${1}=${2}/" "$conf"
        else
            sed -i "/^\[ui\]/a ${1}=${2}" "$conf"
        fi
    }
    case "$theme" in
        dark) set_theme_key themeMode dark;;
        light) set_theme_key themeMode light;;
        system) set_theme_key followSystemTheme true; set_theme_key themeMode system;;
        *) echo "theme must be dark|light|system" >&2; exit 1 ;;
    esac
fi

QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=opengl "$binary" "$image" --screenshot "$out"
[[ -n "$backup" ]] && cp "$backup" "$conf" && rm -f "$backup"
echo "wrote $out"
