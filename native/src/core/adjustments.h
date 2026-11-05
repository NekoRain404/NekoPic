#pragma once

#include <QImage>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include <array>

namespace NekoPic::Adjustments {

// Fixed topology of the extended colour controls. The key/value API below is
// the stable contract used by the QML panel; the arrays keep the by-value
// Parameters object cheap to copy into history entries.
inline constexpr int HslChannelCount = 8;
inline constexpr int CurveChannelCount = 4;
inline constexpr int CurvePointCount = 5;
inline constexpr int GradeZoneCount = 3;

struct HslChannelAdjustment {
    double hue = 0.0;        // Stored [-1, 1]; UI [-100, 100].
    double saturation = 0.0; // Stored [-1, 1]; UI [-100, 100].
    double luminance = 0.0;  // Stored [-1, 1]; UI [-100, 100].
};

// Five fixed input positions (0, 25, 50, 75, 100). Values are stored output
// levels in [0, 1]; the UI exposes them as percentages 0..100. The default is
// the identity curve.
struct ToneCurve {
    std::array<double, CurvePointCount> points{0.0, 0.25, 0.5, 0.75, 1.0};
};

struct GradeZoneAdjustment {
    double hue = 0.0;        // Stored degrees [0, 360); UI [0, 360].
    double saturation = 0.0; // Stored [0, 1]; UI [0, 100].
    double luminance = 0.0;  // Stored [-1, 1]; UI [-100, 100].
};

struct Parameters {
    // --- Basic controls (existing storage contract) -----------------------
    double exposure = 0.0;   // Stops, clamped to [-4, 4]. UI -100..100.
    double brightness = 0.0; // Clamped to [-1, 1]. UI -100..100.
    double contrast = 0.0;   // Clamped to [-1, 1]. UI -100..100.
    double saturation = 0.0; // Clamped to [-1, 1]. UI -100..100.

    // --- Extended basic controls -----------------------------------------
    double highlights = 0.0;  // [-1, 1]
    double shadows = 0.0;     // [-1, 1]
    double whites = 0.0;      // [-1, 1]
    double blacks = 0.0;      // [-1, 1]
    double temperature = 0.0; // [-1, 1]
    double tint = 0.0;        // [-1, 1]
    double vibrance = 0.0;    // [-1, 1]
    double fade = 0.0;        // [0, 1]

    // --- HSL: red, orange, yellow, green, aqua, blue, purple, magenta ----
    std::array<HslChannelAdjustment, HslChannelCount> hsl{};

    // --- Curves: RGB, R, G, B --------------------------------------------
    std::array<ToneCurve, CurveChannelCount> curves{};

    // --- Colour grading: shadows, midtones, highlights -------------------
    // Hue defaults follow the H5 panel, but a zone is pixel-neutral until its
    // saturation (or luminance) is non-zero.
    std::array<GradeZoneAdjustment, GradeZoneCount> grade{
        {{220.0, 0.0, 0.0}, {35.0, 0.0, 0.0}, {45.0, 0.0, 0.0}}};
    double gradeBlending = 0.5; // [0, 1], UI 0..100
    double gradeBalance = 0.0;  // [-1, 1], UI -100..100

    // --- Detail and effects ----------------------------------------------
    double texture = 0.0;    // [0, 1]
    double clarity = 0.0;    // [0, 1]
    double dehaze = 0.0;     // [0, 1]
    double sharpen = 0.0;    // [0, 1]
    double noise = 0.0;      // [0, 1]
    double colorNoise = 0.0; // [0, 1]
    double vignette = 0.0;   // [-1, 1]
    double feather = 0.5;    // [0, 1], UI 0..100
    double grain = 0.0;      // [0, 1]

    // --- Existing filter preset contract ---------------------------------
    QString filterPreset = QStringLiteral("none");
    double filterIntensity = 1.0; // Clamped to [0, 1].
};

// Always apply preview parameters to the same unmodified source image.
QImage apply(const QImage &source, const Parameters &parameters);

// ---------------------------------------------------------------------------
// Generic key/value API for the QML panel.
//
// Keys and UI ranges:
//   exposure brightness contrast saturation            -100..100
//   highlights shadows whites blacks                     -100..100
//   temperature tint vibrance                            -100..100
//   fade                                                   0..100
//   hsl.<channel>.hue|saturation|luminance              -100..100
//     channels: red orange yellow green aqua blue purple magenta
//   curve.<channel>.<0..4>                                 0..100
//     channels: RGB R G B ; fixed inputs 0, 25, 50, 75, 100
//   grade.<zone>.hue                                       0..360
//   grade.<zone>.saturation                                0..100
//   grade.<zone>.luminance                              -100..100
//     zones: shadows midtones highlights
//   grade.blending 0..100 ; grade.balance -100..100
//   texture clarity dehaze sharpen noise colorNoise        0..100
//   vignette -100..100 ; feather 0..100 ; grain 0..100
//
// setParameter() returns false for an unknown key and otherwise clamps the
// value to its UI range. parameterValue() returns UI units and NaN for an
// unknown key. toUiValues() returns every key.
// ---------------------------------------------------------------------------
bool isParameterKey(const QString &key);
QStringList parameterKeys();
bool setParameter(Parameters &parameters, const QString &key, double uiValue);
double parameterValue(const Parameters &parameters, const QString &key);
QVariantMap toUiValues(const Parameters &parameters);

// True only for the four basic keys the interactive GPU shader mirrors.
bool isGpuPreviewKey(const QString &key);

} // namespace NekoPic::Adjustments
