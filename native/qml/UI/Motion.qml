pragma Singleton
import QtQuick

/*!
    Motion — durations, easing and spring tokens for the whole product.

    Components animate only through these tokens (and through
    Motion.duration()), so a single reduceMotion switch removes motion
    without changing any layout.

    Language: quick, decelerating, never bouncy. 90–280 ms.
*/
QtObject {
    id: motion

    /*! Mirrors Theme.reduceMotion; true collapses every duration to zero. */
    readonly property bool reduceMotion: Theme.reduceMotion

    // ── Durations (ms) ──────────────────────────────────────────────────────
    readonly property int instant: 90
    readonly property int fast: 140
    readonly property int standard: 200
    readonly property int slow: 280

    // ── Easing values ───────────────────────────────────────────────────────
    readonly property int standardEasing: Easing.OutCubic
    readonly property int decelerateEasing: Easing.OutCubic
    readonly property int accelerateEasing: Easing.InCubic
    readonly property int emphasizedEasing: Easing.OutQuint

    // Cubic-bezier control points, available to animations that need a
    // bespoke curve. [x1, y1, x2, y2]
    readonly property var standardCurve: [0.2, 0.0, 0.0, 1.0]
    readonly property var decelerateCurve: [0.0, 0.0, 0.2, 1.0]
    readonly property var accelerateCurve: [0.4, 0.0, 1.0, 1.0]
    readonly property var emphasizedCurve: [0.2, 0.0, 0.0, 1.0]

    // ── Spring parameters ───────────────────────────────────────────────────
    readonly property real springStiffness: 380
    readonly property real springDamping: 34
    readonly property real springMass: 1.0
    readonly property real springEpsilon: 0.001

    /*! Returns 0 when the user prefers reduced motion, otherwise the token. */
    function duration(ms) {
        return reduceMotion ? 0 : ms
    }

    /*! Easing value for a named style. */
    function easing(kind) {
        switch (kind) {
        case "accelerate": return accelerateEasing
        case "emphasized": return emphasizedEasing
        case "standard": return standardEasing
        default: return decelerateEasing
        }
    }
}
