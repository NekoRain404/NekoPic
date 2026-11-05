#!/usr/bin/env bash
# Enforce the source-size budget from CONTRIBUTING.md.
#
#   scripts/check-source-size.sh          # warnings only for the tracked exception
#   scripts/check-source-size.sh --strict # fail on any file above the hard stop
#
# Tests, generated QML fixtures and the H5 prototype are excluded: the policy
# applies to product engine and UI sources.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
strict=0
[[ "${1:-}" == "--strict" ]] && strict=1
max=800
fail=0

# Main.qml is the composition root; it is explicitly tracked for a follow-up
# split. Remove this exception once it drops below the hard stop.
exceptions=(
    "native/qml/Main.qml"          # composition root; second split in progress
    "native/qml/dialogs/TextDialog.qml"
    "native/qml/overlays/SelectionOverlay.qml"
)

is_exception() {
    local file="$1"
    for allowed in "${exceptions[@]}"; do
        [[ "$file" == "$allowed" ]] && return 0
    done
    return 1
}

cd "$root"
while IFS= read -r file; do
    case "$file" in
        native/qml/tests/*) continue ;;
        native/src/*.cpp|native/src/*.h|native/qml/*.qml) ;;
        *) continue ;;
    esac
    lines=$(wc -l < "$file")
    (( lines > max )) || continue
    if is_exception "$file"; then
        if (( strict )); then
            printf 'error: %s has %d lines (limit %d; exception requires split)\n' "$file" "$lines" "$max" >&2
            fail=1
        else
            printf 'warning: %s has %d lines (limit %d; tracked exception)\n' "$file" "$lines" "$max" >&2
        fi
    else
        printf 'error: %s has %d lines (limit %d)\n' "$file" "$lines" "$max" >&2
        fail=1
    fi
done < <(git ls-files 'native/src/*.cpp' 'native/src/*.h' 'native/qml/*.qml')

if (( fail )); then
    echo "source-size check failed" >&2
    exit 1
fi
echo "source-size check passed"
