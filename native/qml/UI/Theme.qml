pragma Singleton
import QtQuick

/*!
    Theme — the single source of truth for NekoPic's visual language.

    Every colour, spacing step, radius, type size, shadow and control metric
    lives here. Components must never inline these values; if a component
    needs a new dimension it should read an existing token or add one here.

    The palette follows the H5 prototype's graphite + warm peach identity,
    tightened for a native desktop editor: calmer chrome, softer borders and
    a more restrained accent.
*/
QtObject {
    id: theme

    // ── Mode ────────────────────────────────────────────────────────────────
    /*! Dark is the default, matching the editor's focus-friendly chrome. */
    property bool dark: true
    /*! When true, Motion.duration() collapses to zero. */
    property bool reduceMotion: false

    // ── Semantic colours ────────────────────────────────────────────────────
    readonly property color background: dark ? "#181a1b" : "#edece8"
    readonly property color canvas: dark ? "#141617" : "#dcded9"
    readonly property color panel: dark ? "#1e2022" : "#f2f1ec"
    readonly property color surface: dark ? "#222426" : "#f7f6f2"
    readonly property color surfaceRaised: dark ? "#2b2d2f" : "#ffffff"
    readonly property color hover: dark ? "#343638" : "#e6e5df"
    readonly property color pressed: dark ? "#3c3f41" : "#dcdbd4"

    readonly property color textPrimary: dark ? "#e9e9e6" : "#303734"
    readonly property color textSecondary: dark ? "#9aa19c" : "#5f6862"
    readonly property color textTertiary: dark ? "#858d89" : "#626c65"

    readonly property color border: dark ? "#343638" : "#d6d7d1"
    readonly property color separator: dark ? "#2a2c2e" : "#e0e1db"

    readonly property color accent: dark ? "#edbc9d" : "#a45934"
    readonly property color accentHover: dark ? "#f7cdb1" : "#b66b46"
    readonly property color accentPressed: dark ? "#e0ab8a" : "#8f4a2a"
    readonly property color accentSoft: dark ? "#1fedbc9d" : "#1aa45934"
    readonly property color accentInk: dark ? "#292420" : "#fff6ed"

    /*! Tinted highlight used behind selected tools, tabs and cards. */
    readonly property color selection: dark ? "#2eedbc9d" : "#24a45934"

    readonly property color danger: dark ? "#e28983" : "#b3564f"
    readonly property color success: dark ? "#9ab8a6" : "#5b7d63"
    readonly property color warning: dark ? "#e3bd84" : "#9a6c2f"
    readonly property color focusRing: dark ? "#f4cdb3" : "#a45934"

    /*! Backdrop behind modal surfaces. */
    readonly property color scrim: dark ? "#cc0a0c0d" : "#aa3a3a34"
    readonly property color shadowColor: dark ? "#000000" : "#2a2a24"
    /*! Knob / handle ink that stays legible on either track colour. */
    readonly property color controlKnob: dark ? "#f4f2ed" : "#ffffff"

    // High-contrast ink/paper used by contrastColor().
    readonly property color contrastInk: "#1b1d1e"
    readonly property color contrastPaper: "#f7f7f4"

    /*! Returns dark or light ink for text placed on an arbitrary colour. */
    function contrastColor(onColor) {
        const luminance = 0.2126 * onColor.r + 0.7152 * onColor.g + 0.0722 * onColor.b
        return luminance > 0.55 ? contrastInk : contrastPaper
    }

    /*! Colour with an explicit alpha, preserving the token's RGB. */
    function alpha(sourceColor, opacity) {
        return Qt.rgba(sourceColor.r, sourceColor.g, sourceColor.b, opacity)
    }

    // ── Spacing (8pt grid with a 4pt half-step) ─────────────────────────────
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 20
    readonly property int spacing2xl: 24
    readonly property int spacing3xl: 32
    readonly property int spacing4xl: 40

    // ── Radii ───────────────────────────────────────────────────────────────
    readonly property int radiusXs: 4
    readonly property int radiusSm: 6
    readonly property int radiusMd: 8
    readonly property int radiusLg: 12
    readonly property int radiusXl: 16
    readonly property int radiusPill: 999

    // ── Type scale ──────────────────────────────────────────────────────────
    readonly property int fontCaption: 10
    readonly property int fontSmall: 11
    readonly property int fontBody: 12
    readonly property int fontTitle: 15
    readonly property int fontHeadline: 19
    readonly property int fontDisplay: 24

    readonly property int fontWeightRegular: Font.Normal
    readonly property int fontWeightMedium: Font.Medium
    readonly property int fontWeightDemiBold: Font.DemiBold
    readonly property int fontWeightBold: Font.Bold

    readonly property real trackingTight: 0.5
    readonly property real trackingWide: 1.4
    readonly property real lineHeightTight: 1.25
    readonly property real lineHeightNormal: 1.5

    // ── Elevation tokens ────────────────────────────────────────────────────
    // Components draw these as offset, low-opacity rectangles so the look is
    // identical under both the GPU and software scenegraph backends.
    readonly property var elevationNone: ({ spread: 0, offsetY: 0, opacity: 0.0 })
    readonly property var elevationLow: ({ spread: 2, offsetY: 2, opacity: 0.20 })
    readonly property var elevationMedium: ({ spread: 6, offsetY: 8, opacity: 0.24 })
    readonly property var elevationHigh: ({ spread: 12, offsetY: 16, opacity: 0.34 })

    // ── Opacity tokens ──────────────────────────────────────────────────────
    readonly property real opacityDisabled: 0.40
    readonly property real opacityMuted: 0.72
    readonly property real opacityHover: 0.08
    readonly property real opacityPressed: 0.14
    readonly property real opacityScrim: 0.55
    readonly property real opacitySubtle: 0.12

    // ── Metrics ─────────────────────────────────────────────────────────────
    // Shared control measurements keep hit targets and rhythm consistent.
    readonly property int borderWidth: 1
    readonly property int focusRingWidth: 2
    readonly property int focusRingOffset: 2

    readonly property int controlHeightSm: 26
    readonly property int controlHeight: 34
    readonly property int controlHeightLg: 40
    readonly property int controlMinWidth: 120

    readonly property int toolButtonWidth: 52
    readonly property int toolButtonHeight: 52
    readonly property int indicatorWidth: 2
    readonly property int indicatorHeight: 18

    readonly property int iconSizeSm: 16
    readonly property int iconSize: 18
    readonly property int iconSizeLg: 20

    readonly property int toggleWidth: 38
    readonly property int toggleHeight: 22
    readonly property int toggleKnobSize: 18

    readonly property int sliderHeight: 24
    readonly property int sliderTrackHeight: 4
    readonly property int sliderHandleSize: 14

    readonly property int scrollBarThickness: 8
    readonly property int segmentInset: 3
    readonly property int segmentMinWidth: 56

    readonly property int panelMinWidth: 160
    readonly property int panelMinHeight: 80
    readonly property int cardMinWidth: 180
    readonly property int dialogWidth: 420
}
