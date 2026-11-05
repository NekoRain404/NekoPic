#!/usr/bin/env bash
# Validate the packaging surface without building a package.
#
#   scripts/validate-packaging.sh           # allow the known placeholder items
#   scripts/validate-packaging.sh --strict  # release gate: no known exceptions
#
# The placeholder project license and missing AppStream homepage are reported
# but not fatal in the default mode so development CI stays useful. Use
# --strict (and fix the two TODOs) before publishing a release.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
strict=0
[[ "${1:-}" == "--strict" ]] && strict=1
fail=0
warn() { printf 'warning: %s\n' "$*" >&2; }
error() { printf 'error: %s\n' "$*" >&2; fail=1; }

desktop="$root/packaging/nekopic.desktop"
metainfo="$root/packaging/nekopic.metainfo.xml"
svg="$root/packaging/nekopic.svg"
icons="$root/packaging/icons/hicolor"

for path in "$desktop" "$metainfo" "$svg"; do
    [[ -f "$path" ]] || error "missing ${path#"$root"/}"
done

if [[ -f "$desktop" ]]; then
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$desktop" || error "desktop-file-validate failed"
    else
        warn "desktop-file-validate not installed"
    fi
    grep -q '^Exec=nekopic %f$' "$desktop" || error "desktop Exec must be 'nekopic %f'"
    grep -q '^Icon=nekopic$' "$desktop" || error "desktop Icon must be nekopic"
    grep -q '^StartupWMClass=nekopic$' "$desktop" || error "desktop StartupWMClass must be nekopic"
    for locale in zh_CN ja_JP de_DE; do
        grep -q "^Name\\[$locale\\]=" "$desktop" || warn "desktop Name[$locale] missing"
        grep -q "^Comment\\[$locale\\]=" "$desktop" || warn "desktop Comment[$locale] missing"
    done
fi

if [[ -f "$metainfo" ]]; then
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$metainfo" || error "metainfo is not valid XML"
    fi
    if command -v appstreamcli >/dev/null 2>&1; then
        out="$(appstreamcli validate --no-net --pedantic "$metainfo" 2>&1 || true)"
        known="$(printf '%s\n' "$out" | grep -E 'metadata-license-invalid|url-homepage-missing|cid-contains-uppercase-letter' || true)"
        unknown="$(printf '%s\n' "$out" | grep -E '^[EWP]:' | grep -vE 'metadata-license-invalid|url-homepage-missing|cid-contains-uppercase-letter' || true)"
        if [[ -n "$known" ]]; then
            printf '%s\n' "$known" >&2
            if (( strict )); then
                error "AppStream still has known release blockers (license/homepage)"
            else
                warn "AppStream known placeholders: choose a license and add a homepage before release"
            fi
        fi
        [[ -z "$unknown" ]] || { printf '%s\n' "$unknown" >&2; error "unexpected AppStream findings"; }
    else
        warn "appstreamcli not installed"
    fi
fi

if [[ -f "$svg" ]] && command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$svg" || error "SVG icon is not valid XML"
fi

for size in 16 24 32 48 64 128 256 512; do
    icon="$icons/${size}x${size}/apps/nekopic.png"
    [[ -f "$icon" ]] || { error "missing ${icon#"$root"/}"; continue; }
    if command -v identify >/dev/null 2>&1; then
        actual="$(identify -format '%w' "$icon" 2>/dev/null || true)"
        [[ "$actual" == "$size" ]] || error "$icon is ${actual:-unreadable}px, expected ${size}px"
    fi
done

# The AppDir is an optional local build output; validate it when present.
appdir="$root/native/build-appimage/AppDir"
if [[ -d "$appdir" ]]; then
    [[ -x "$appdir/AppRun" ]] || error "AppDir is missing an executable AppRun"
    [[ -f "$appdir/nekopic.desktop" ]] || error "AppDir is missing nekopic.desktop"
    [[ -f "$appdir/nekopic.png" ]] || error "AppDir is missing nekopic.png"
    [[ -f "$appdir/usr/plugins/platforms/libqwayland.so" ]] || warn "AppDir lacks the Wayland platform plugin"
    [[ -d "$appdir/usr/qml/QtQuick" ]] || error "AppDir lacks bundled QtQuick QML modules"
fi

if [[ ! -f "$root/LICENSE" ]]; then
    warn "no LICENSE file: project license is still a release blocker"
fi

if (( fail )); then
    echo "packaging validation failed" >&2
    exit 1
fi
label=""
(( strict )) && label=" (strict)"
echo "packaging validation passed${label}"
