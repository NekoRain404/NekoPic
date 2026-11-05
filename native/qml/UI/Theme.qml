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
    /*!
        Optional palette id. Empty keeps the original light/dark pair so older
        tests and integrations that only toggle `dark` remain valid. Known ids:
        midnight, warm, graphite, contrast.
    */
    property string themeId: ""
    /*! When true, Motion.duration() collapses to zero. */
    property bool reduceMotion: false

    readonly property var _palettes: ({
        midnight: {
            background: "#0c1118", canvas: "#080b10", panel: "#111821",
            surface: "#151d27", surfaceRaised: "#1d2733", hover: "#26313d",
            pressed: "#303d4b", textPrimary: "#e7edf4", textSecondary: "#9aa8b7",
            textTertiary: "#7d8b9b", border: "#2b3745", separator: "#1e2833",
            accent: "#edbc9d", accentHover: "#f7cdb1", accentPressed: "#dfa985",
            accentSoft: "#22edbc9d", accentInk: "#1a222c", selection: "#30edbc9d",
            danger: "#e28983", success: "#9ab8a6", warning: "#e3bd84",
            focusRing: "#f4cdb3", scrim: "#d0080b10", shadowColor: "#000000",
            controlKnob: "#f4f2ed", contrastInk: "#0b1016", contrastPaper: "#f7f7f4"
        },
        warm: {
            background: "#eee5d7", canvas: "#e2d5c1", panel: "#f6efe3",
            surface: "#fbf6ec", surfaceRaised: "#fffdf8", hover: "#e8ddca",
            pressed: "#dccdb7", textPrimary: "#392f25", textSecondary: "#6f6152",
            textTertiary: "#867668", border: "#d6c6b1", separator: "#e5d7c4",
            accent: "#a9562b", accentHover: "#bd6538", accentPressed: "#8b421e",
            accentSoft: "#20a9562b", accentInk: "#fff7ee", selection: "#2aa9562b",
            danger: "#a94f47", success: "#53745c", warning: "#946526",
            focusRing: "#a9562b", scrim: "#b0443528", shadowColor: "#3a2d20",
            controlKnob: "#ffffff", contrastInk: "#2a221a", contrastPaper: "#fffaf2"
        },
        graphite: {
            background: "#151515", canvas: "#101010", panel: "#1b1b1b",
            surface: "#212121", surfaceRaised: "#282828", hover: "#313131",
            pressed: "#3b3b3b", textPrimary: "#ececec", textSecondary: "#a2a2a2",
            textTertiary: "#838383", border: "#363636", separator: "#282828",
            accent: "#d9b08c", accentHover: "#e7c2a2", accentPressed: "#c59c78",
            accentSoft: "#1fd9b08c", accentInk: "#26221e", selection: "#2cd9b08c",
            danger: "#df8a84", success: "#9bb7a6", warning: "#dfbb8b",
            focusRing: "#e7c2a2", scrim: "#cc0b0b0b", shadowColor: "#000000",
            controlKnob: "#f2f2f2", contrastInk: "#161616", contrastPaper: "#f7f7f7"
        },
        contrast: {
            background: "#000000", canvas: "#000000", panel: "#0a0a0a",
            surface: "#111111", surfaceRaised: "#191919", hover: "#262626",
            pressed: "#353535", textPrimary: "#ffffff", textSecondary: "#d7d7d7",
            textTertiary: "#bdbdbd", border: "#7a7a7a", separator: "#4a4a4a",
            accent: "#ffb86b", accentHover: "#ffd09a", accentPressed: "#e69a45",
            accentSoft: "#33ffb86b", accentInk: "#000000", selection: "#55ffb86b",
            danger: "#ff8f88", success: "#8fe0a8", warning: "#ffd166",
            focusRing: "#ffffff", scrim: "#e6000000", shadowColor: "#000000",
            controlKnob: "#ffffff", contrastInk: "#000000", contrastPaper: "#ffffff"
        }
    })
    readonly property var _palette: _palettes[themeId] || null

    // ── Semantic colours ────────────────────────────────────────────────────
    readonly property color background: _palette ? _palette.background
                                                  : dark ? "#181a1b" : "#edece8"
    readonly property color canvas: _palette ? _palette.canvas
                                              : dark ? "#141617" : "#dcded9"
    readonly property color panel: _palette ? _palette.panel
                                             : dark ? "#1e2022" : "#f2f1ec"
    readonly property color surface: _palette ? _palette.surface
                                               : dark ? "#222426" : "#f7f6f2"
    readonly property color surfaceRaised: _palette ? _palette.surfaceRaised
                                                    : dark ? "#2b2d2f" : "#ffffff"
    readonly property color hover: _palette ? _palette.hover
                                             : dark ? "#343638" : "#e6e5df"
    readonly property color pressed: _palette ? _palette.pressed
                                               : dark ? "#3c3f41" : "#dcdbd4"

    readonly property color textPrimary: _palette ? _palette.textPrimary
                                                  : dark ? "#e9e9e6" : "#303734"
    readonly property color textSecondary: _palette ? _palette.textSecondary
                                                    : dark ? "#9aa19c" : "#5f6862"
    readonly property color textTertiary: _palette ? _palette.textTertiary
                                                   : dark ? "#858d89" : "#626c65"

    readonly property color border: _palette ? _palette.border
                                             : dark ? "#343638" : "#d6d7d1"
    readonly property color separator: _palette ? _palette.separator
                                                : dark ? "#2a2c2e" : "#e0e1db"

    readonly property color accent: _palette ? _palette.accent
                                             : dark ? "#edbc9d" : "#a45934"
    readonly property color accentHover: _palette ? _palette.accentHover
                                                  : dark ? "#f7cdb1" : "#b66b46"
    readonly property color accentPressed: _palette ? _palette.accentPressed
                                                    : dark ? "#e0ab8a" : "#8f4a2a"
    readonly property color accentSoft: _palette ? _palette.accentSoft
                                                 : dark ? "#1fedbc9d" : "#1aa45934"
    readonly property color accentInk: _palette ? _palette.accentInk
                                                : dark ? "#292420" : "#fff6ed"

    /*! Tinted highlight used behind selected tools, tabs and cards. */
    readonly property color selection: _palette ? _palette.selection
                                                : dark ? "#2eedbc9d" : "#24a45934"

    readonly property color danger: _palette ? _palette.danger
                                             : dark ? "#e28983" : "#b3564f"
    readonly property color success: _palette ? _palette.success
                                              : dark ? "#9ab8a6" : "#5b7d63"
    readonly property color warning: _palette ? _palette.warning
                                              : dark ? "#e3bd84" : "#9a6c2f"
    readonly property color focusRing: _palette ? _palette.focusRing
                                                : dark ? "#f4cdb3" : "#a45934"

    /*! Backdrop behind modal surfaces. */
    readonly property color scrim: _palette ? _palette.scrim
                                            : dark ? "#cc0a0c0d" : "#aa3a3a34"
    readonly property color shadowColor: _palette ? _palette.shadowColor
                                                  : dark ? "#000000" : "#2a2a24"
    /*! Knob / handle ink that stays legible on either track colour. */
    readonly property color controlKnob: _palette ? _palette.controlKnob
                                                  : dark ? "#f4f2ed" : "#ffffff"

    // High-contrast ink/paper used by contrastColor().
    readonly property color contrastInk: _palette ? _palette.contrastInk : "#1b1d1e"
    readonly property color contrastPaper: _palette ? _palette.contrastPaper : "#f7f7f4"

    /*! Theme ids/names for the settings picker; `system` is resolved by Main. */
    readonly property var themeOptions: [
        { id: "system", label: qsTr("System"), dark: false },
        { id: "light", label: qsTr("Light"), dark: false },
        { id: "dark", label: qsTr("Dark"), dark: true },
        { id: "midnight", label: qsTr("Midnight"), dark: true },
        { id: "warm", label: qsTr("Warm paper"), dark: false },
        { id: "graphite", label: qsTr("Graphite"), dark: true },
        { id: "contrast", label: qsTr("High contrast"), dark: true }
    ]

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
