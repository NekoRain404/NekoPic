#!/usr/bin/env bash
# Regenerate the hicolor PNG icon set from packaging/nekopic.svg.
#
#   scripts/generate-icons.sh
#
# Requires rsvg-convert (librsvg) or ImageMagick. The generated PNGs are
# committed so release builds do not need an SVG rasterizer.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
svg="${repo_root}/packaging/nekopic.svg"
out_root="${repo_root}/packaging/icons/hicolor"
sizes=(16 24 32 48 64 128 256 512)

if command -v rsvg-convert >/dev/null 2>&1; then
    render() {
        rsvg-convert -w "$1" -h "$1" "${svg}" -o "$2"
    }
elif command -v magick >/dev/null 2>&1; then
    render() {
        magick -background none "${svg}" -resize "$1x$1" "$2"
    }
elif command -v convert >/dev/null 2>&1; then
    render() {
        convert -background none "${svg}" -resize "$1x$1" "$2"
    }
else
    printf 'generate-icons.sh: install rsvg-convert (librsvg) or ImageMagick\n' >&2
    exit 1
fi

[[ -f "${svg}" ]] || {
    printf 'generate-icons.sh: missing %s\n' "${svg}" >&2
    exit 1
}

for size in "${sizes[@]}"; do
    dir="${out_root}/${size}x${size}/apps"
    mkdir -p "${dir}"
    render "${size}" "${dir}/nekopic.png"
    printf 'wrote %s\n' "${dir}/nekopic.png"
done

if command -v identify >/dev/null 2>&1; then
    for size in "${sizes[@]}"; do
        png="${out_root}/${size}x${size}/apps/nekopic.png"
        actual="$(identify -format '%wx%h' "${png}")"
        [[ "${actual}" == "${size}x${size}" ]] || {
            printf 'generate-icons.sh: %s is %s, expected %sx%s\n' \
                "${png}" "${actual}" "${size}" "${size}" >&2
            exit 1
        }
    done
fi

printf 'icon set regenerated in %s\n' "${out_root}"
