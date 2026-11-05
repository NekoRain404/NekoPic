#include "colorpipeline.h"

#include "rowparallel.h"

#include <QColorSpace>
#include <QHash>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <numbers>
#include <vector>

// ---------------------------------------------------------------------------
// Extended colour pipeline.
//
// Order (documented contract for the panel and for future GPU parity):
//   1. white balance            temperature/tint channel gains
//   2. tonal                    exposure, brightness, contrast, highlights,
//                               shadows, whites, blacks
//   3. saturation + vibrance
//   4. HSL                      8 hue bands with smooth cosine weights
//   5. tone curves              RGB composite, then R, G and B
//   6. colour grading           shadow/midtone/highlight masks
//   7. detail                   texture, clarity, dehaze, sharpen, luminance
//                               and colour noise reduction
//   8. effects                  vignette (+feather), grain, fade
//   9. existing filter preset   unchanged preset formulas and intensity blend
//
// Approximations:
//  - Extended work happens in a normalized, straight-alpha RGBA64 buffer.
//    Floating-point sources therefore lose HDR/negative excursions when an
//    extended control is active; the output is converted back to the source
//    format and alpha is copied from the source verbatim. Basic-only
//    parameters keep the original floating path and its HDR precision.
//  - Luminance noise reduction and clarity use a separable box blur restricted
//    to the image (edge-clamped). Colour noise reduction uses a 3x3 box
//    average of the chroma-carrying RGB neighbourhood.
//  - Grain is a deterministic per-pixel hash, not a stateful RNG, so parallel
//    rows produce identical output.
//  - Intermediate stages clamp to SDR after each cross-channel stage.
// ---------------------------------------------------------------------------

namespace NekoPic::Adjustments {

namespace {

// ---------------------------------------------------------------------------
// Key registry
// ---------------------------------------------------------------------------

enum class Field {
    Scalar,
    HslHue,
    HslSaturation,
    HslLuminance,
    CurvePoint,
    GradeHue,
    GradeSaturation,
    GradeLuminance,
};

struct KeyInfo {
    Field field = Field::Scalar;
    int index = 0;
    int sub = 0;
    double uiMin = 0.0;
    double uiMax = 0.0;
    double storedPerUi = 1.0;
    double uiPerStored = 1.0;
    double Parameters::*member = nullptr;
};

struct Registry {
    QStringList keys;
    QHash<QString, int> lookup;
    std::vector<KeyInfo> infos;
};

Registry buildRegistry()
{
    Registry registry;

    const auto add = [&](const QString &key, Field field, int index, int sub, double uiMin,
                         double uiMax, double storedPerUi, double uiPerStored,
                         double Parameters::*member) {
        const int position = static_cast<int>(registry.infos.size());
        registry.infos.push_back(
            {field, index, sub, uiMin, uiMax, storedPerUi, uiPerStored, member});
        registry.keys.append(key);
        registry.lookup.insert(key, position);
    };

    const auto addScalar = [&](const char *key, double uiMin, double uiMax,
                               double storedPerUi, double uiPerStored,
                               double Parameters::*member) {
        add(QString::fromLatin1(key), Field::Scalar, 0, 0, uiMin, uiMax, storedPerUi,
            uiPerStored, member);
    };

    // Basic controls.
    addScalar("exposure", -100.0, 100.0, 4.0 / 100.0, 25.0, &Parameters::exposure);
    addScalar("brightness", -100.0, 100.0, 0.01, 100.0, &Parameters::brightness);
    addScalar("contrast", -100.0, 100.0, 0.01, 100.0, &Parameters::contrast);
    addScalar("saturation", -100.0, 100.0, 0.01, 100.0, &Parameters::saturation);
    addScalar("highlights", -100.0, 100.0, 0.01, 100.0, &Parameters::highlights);
    addScalar("shadows", -100.0, 100.0, 0.01, 100.0, &Parameters::shadows);
    addScalar("whites", -100.0, 100.0, 0.01, 100.0, &Parameters::whites);
    addScalar("blacks", -100.0, 100.0, 0.01, 100.0, &Parameters::blacks);
    addScalar("temperature", -100.0, 100.0, 0.01, 100.0, &Parameters::temperature);
    addScalar("tint", -100.0, 100.0, 0.01, 100.0, &Parameters::tint);
    addScalar("vibrance", -100.0, 100.0, 0.01, 100.0, &Parameters::vibrance);
    addScalar("fade", 0.0, 100.0, 0.01, 100.0, &Parameters::fade);

    static const char *const hslNames[]{"red", "orange", "yellow", "green",
                                        "aqua", "blue", "purple", "magenta"};
    for (int channel = 0; channel < HslChannelCount; ++channel) {
        const QString name = QString::fromLatin1(hslNames[channel]);
        add(QStringLiteral("hsl.%1.hue").arg(name), Field::HslHue, channel, 0, -100.0, 100.0,
            0.01, 100.0, nullptr);
        add(QStringLiteral("hsl.%1.saturation").arg(name), Field::HslSaturation, channel, 0,
            -100.0, 100.0, 0.01, 100.0, nullptr);
        add(QStringLiteral("hsl.%1.luminance").arg(name), Field::HslLuminance, channel, 0,
            -100.0, 100.0, 0.01, 100.0, nullptr);
    }

    static const char *const curveNames[]{"RGB", "R", "G", "B"};
    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        for (int point = 0; point < CurvePointCount; ++point) {
            add(QStringLiteral("curve.%1.%2")
                    .arg(QString::fromLatin1(curveNames[channel]))
                    .arg(point),
                Field::CurvePoint, channel, point, 0.0, 100.0, 0.01, 100.0, nullptr);
        }
    }

    static const char *const gradeNames[]{"shadows", "midtones", "highlights"};
    for (int zone = 0; zone < GradeZoneCount; ++zone) {
        const QString name = QString::fromLatin1(gradeNames[zone]);
        add(QStringLiteral("grade.%1.hue").arg(name), Field::GradeHue, zone, 0, 0.0, 360.0,
            1.0, 1.0, nullptr);
        add(QStringLiteral("grade.%1.saturation").arg(name), Field::GradeSaturation, zone, 0,
            0.0, 100.0, 0.01, 100.0, nullptr);
        add(QStringLiteral("grade.%1.luminance").arg(name), Field::GradeLuminance, zone, 0,
            -100.0, 100.0, 0.01, 100.0, nullptr);
    }
    addScalar("grade.blending", 0.0, 100.0, 0.01, 100.0, &Parameters::gradeBlending);
    addScalar("grade.balance", -100.0, 100.0, 0.01, 100.0, &Parameters::gradeBalance);

    // Detail and effects.
    addScalar("texture", 0.0, 100.0, 0.01, 100.0, &Parameters::texture);
    addScalar("clarity", 0.0, 100.0, 0.01, 100.0, &Parameters::clarity);
    addScalar("dehaze", 0.0, 100.0, 0.01, 100.0, &Parameters::dehaze);
    addScalar("sharpen", 0.0, 100.0, 0.01, 100.0, &Parameters::sharpen);
    addScalar("noise", 0.0, 100.0, 0.01, 100.0, &Parameters::noise);
    addScalar("colorNoise", 0.0, 100.0, 0.01, 100.0, &Parameters::colorNoise);
    addScalar("vignette", -100.0, 100.0, 0.01, 100.0, &Parameters::vignette);
    addScalar("feather", 0.0, 100.0, 0.01, 100.0, &Parameters::feather);
    addScalar("grain", 0.0, 100.0, 0.01, 100.0, &Parameters::grain);

    return registry;
}

const Registry &registry()
{
    static const Registry instance = buildRegistry();
    return instance;
}

double storedValue(const Parameters &parameters, const KeyInfo &info)
{
    switch (info.field) {
    case Field::Scalar:
        return parameters.*(info.member);
    case Field::HslHue:
        return parameters.hsl[info.index].hue;
    case Field::HslSaturation:
        return parameters.hsl[info.index].saturation;
    case Field::HslLuminance:
        return parameters.hsl[info.index].luminance;
    case Field::CurvePoint:
        return parameters.curves[info.index].points[info.sub];
    case Field::GradeHue:
        return parameters.grade[info.index].hue;
    case Field::GradeSaturation:
        return parameters.grade[info.index].saturation;
    case Field::GradeLuminance:
        return parameters.grade[info.index].luminance;
    }
    return 0.0;
}

void assignStoredValue(Parameters &parameters, const KeyInfo &info, double value)
{
    switch (info.field) {
    case Field::Scalar:
        parameters.*(info.member) = value;
        return;
    case Field::HslHue:
        parameters.hsl[info.index].hue = value;
        return;
    case Field::HslSaturation:
        parameters.hsl[info.index].saturation = value;
        return;
    case Field::HslLuminance:
        parameters.hsl[info.index].luminance = value;
        return;
    case Field::CurvePoint:
        parameters.curves[info.index].points[info.sub] = value;
        return;
    case Field::GradeHue:
        parameters.grade[info.index].hue = value;
        return;
    case Field::GradeSaturation:
        parameters.grade[info.index].saturation = value;
        return;
    case Field::GradeLuminance:
        parameters.grade[info.index].luminance = value;
        return;
    }
}

// ---------------------------------------------------------------------------
// Numeric helpers
// ---------------------------------------------------------------------------

double bounded(double value, double limit)
{
    return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
}

double clamp01(double value)
{
    return std::clamp(value, 0.0, 1.0);
}

double luma(double red, double green, double blue)
{
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

double smoothstep(double edge0, double edge1, double value)
{
    if (edge0 == edge1)
        return value < edge0 ? 0.0 : 1.0;
    const double t = clamp01((value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

double normalizeHue(double hue)
{
    double result = std::fmod(hue, 360.0);
    if (result < 0.0)
        result += 360.0;
    return result;
}

double hueWeight(double hue, double center)
{
    // One shared half-width for all eight bands. The red/orange/yellow centres
    // are 30 degrees apart, so adjacent bands overlap smoothly; distant bands
    // do not contribute at all.
    constexpr double kHalfWidth = 45.0;
    double distance = std::abs(hue - center);
    distance = std::min(distance, 360.0 - distance);
    if (distance >= kHalfWidth)
        return 0.0;
    return 0.5 * (1.0 + std::cos(std::numbers::pi * distance / kHalfWidth));
}

double hueDegrees(double red, double green, double blue, double maximum, double minimum)
{
    const double chroma = maximum - minimum;
    if (chroma <= 1e-12)
        return 0.0;
    double hue;
    if (maximum == red)
        hue = 60.0 * std::fmod((green - blue) / chroma, 6.0);
    else if (maximum == green)
        hue = 60.0 * ((blue - red) / chroma + 2.0);
    else
        hue = 60.0 * ((red - green) / chroma + 4.0);
    if (hue < 0.0)
        hue += 360.0;
    return hue;
}

void rgbFromHsv(double hue, double saturation, double value, double &red, double &green,
                double &blue)
{
    hue = normalizeHue(hue);
    const double chroma = value * saturation;
    const double hp = hue / 60.0;
    const double second = chroma * (1.0 - std::abs(std::fmod(hp, 2.0) - 1.0));
    double r = 0.0;
    double g = 0.0;
    double b = 0.0;
    if (hp < 1.0) {
        r = chroma;
        g = second;
    } else if (hp < 2.0) {
        r = second;
        g = chroma;
    } else if (hp < 3.0) {
        g = chroma;
        b = second;
    } else if (hp < 4.0) {
        g = second;
        b = chroma;
    } else if (hp < 5.0) {
        r = second;
        b = chroma;
    } else {
        r = chroma;
        b = second;
    }
    const double base = value - chroma;
    red = r + base;
    green = g + base;
    blue = b + base;
}

quint16 toChannel(double value)
{
    const double scaled = clamp01(value) * 65535.0;
    const double base = std::floor(scaled);
    return static_cast<quint16>(base + (scaled - base >= 0.5 ? 1.0 : 0.0));
}

bool isLinearCurve(const ToneCurve &curve)
{
    for (int point = 0; point < CurvePointCount; ++point) {
        if (!std::isfinite(curve.points[point]))
            return false;
        if (std::abs(curve.points[point] - point * 0.25) > 1e-9)
            return false;
    }
    return true;
}

double evaluateCurve(const ToneCurve &curve, double value)
{
    const double x = clamp01(value);
    const double scaled = x * 4.0;
    int segment = static_cast<int>(scaled);
    if (segment > CurvePointCount - 2)
        segment = CurvePointCount - 2;
    const double fraction = scaled - segment;
    const double output =
        curve.points[segment] + (curve.points[segment + 1] - curve.points[segment]) * fraction;
    return clamp01(output);
}

// Box blur of the working image's luminance, edge-clamped. `output` receives
// the horizontal pass and then the final result; `scratch` is reused between
// calls. O(pixels), independent of the radius.
void boxBlurLuminance(const QImage &work, std::vector<float> &output,
                      std::vector<float> &scratch, int radius)
{
    const int width = work.width();
    const int height = work.height();
    const qsizetype stride = work.bytesPerLine();
    const auto *base = work.constBits();
    const int diameter = radius * 2 + 1;
    const auto size = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);

    output.resize(size);
    scratch.resize(size);

    const int workers = Detail::rowWorkerCount(width, height);
    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            const auto *pixels = reinterpret_cast<const QRgba64 *>(base + y * stride);
            const auto luminanceAt = [&](int x) {
                const QRgba64 pixel = pixels[std::clamp(x, 0, width - 1)];
                return luma(pixel.red() / 65535.0, pixel.green() / 65535.0,
                            pixel.blue() / 65535.0);
            };
            double sum = 0.0;
            for (int offset = -radius; offset <= radius; ++offset)
                sum += luminanceAt(offset);
            float *row = output.data() + static_cast<std::size_t>(y) * width;
            for (int x = 0; x < width; ++x) {
                row[x] = static_cast<float>(sum / diameter);
                sum += luminanceAt(x + radius + 1) - luminanceAt(x - radius);
            }
        }
    });

    // Vertical pass. Rows are independent of each other but each reads a
    // column of the horizontal result, so keep this pass serial to avoid
    // strided concurrent cache traffic; it remains O(pixels).
    for (int x = 0; x < width; ++x) {
        double sum = 0.0;
        for (int offset = -radius; offset <= radius; ++offset) {
            const int y = std::clamp(offset, 0, height - 1);
            sum += output[static_cast<std::size_t>(y) * width + x];
        }
        for (int y = 0; y < height; ++y) {
            scratch[static_cast<std::size_t>(y) * width + x] =
                static_cast<float>(sum / diameter);
            const int add = std::clamp(y + radius + 1, 0, height - 1);
            const int remove = std::clamp(y - radius, 0, height - 1);
            sum += output[static_cast<std::size_t>(add) * width + x]
                - output[static_cast<std::size_t>(remove) * width + x];
        }
    }

    output.swap(scratch);
}

// Filter presets: kept numerically identical to the legacy fast path.
enum class Preset {
    None,
    Fresh,
    Vivid,
    Warm,
    Cool,
    Film,
    Faded,
    Vintage,
    Sunset,
    Soft,
    Cream,
    Mono,
    Silver,
    Unknown,
};

Preset parsePreset(const QString &preset)
{
    if (preset.isEmpty() || preset == "none")
        return Preset::None;
    if (preset == "fresh")
        return Preset::Fresh;
    if (preset == "vivid")
        return Preset::Vivid;
    if (preset == "warm")
        return Preset::Warm;
    if (preset == "cool")
        return Preset::Cool;
    if (preset == "film")
        return Preset::Film;
    if (preset == "faded")
        return Preset::Faded;
    if (preset == "vintage")
        return Preset::Vintage;
    if (preset == "sunset")
        return Preset::Sunset;
    if (preset == "soft")
        return Preset::Soft;
    if (preset == "cream")
        return Preset::Cream;
    if (preset == "mono")
        return Preset::Mono;
    if (preset == "silver")
        return Preset::Silver;
    return Preset::Unknown;
}

bool isActivePreset(Preset preset)
{
    return preset != Preset::None && preset != Preset::Unknown;
}

struct Rgb {
    double red;
    double green;
    double blue;
};

Rgb clampedColor(Rgb color)
{
    return {clamp01(color.red), clamp01(color.green), clamp01(color.blue)};
}

Rgb brightnessColor(Rgb color, double amount)
{
    return {color.red * amount, color.green * amount, color.blue * amount};
}

Rgb contrastColor(Rgb color, double amount)
{
    return {(color.red - 0.5) * amount + 0.5, (color.green - 0.5) * amount + 0.5,
            (color.blue - 0.5) * amount + 0.5};
}

Rgb saturationColor(Rgb color, double amount)
{
    const double luminance = luma(color.red, color.green, color.blue);
    return {luminance + (color.red - luminance) * amount,
            luminance + (color.green - luminance) * amount,
            luminance + (color.blue - luminance) * amount};
}

// Partial sepia matrix matching the H5 prototype's `sepia(amount)`.
Rgb sepiaColor(Rgb color, double amount)
{
    const Rgb sepia{0.393 * color.red + 0.769 * color.green + 0.189 * color.blue,
                    0.349 * color.red + 0.686 * color.green + 0.168 * color.blue,
                    0.272 * color.red + 0.534 * color.green + 0.131 * color.blue};
    return {color.red + (sepia.red - color.red) * amount,
            color.green + (sepia.green - color.green) * amount,
            color.blue + (sepia.blue - color.blue) * amount};
}

// Keep this formula-for-formula identical to Adjustments::filterTarget in
// adjustments.cpp. Both pipelines must produce the same look at every
// intensity.
Rgb filterTarget(Rgb color, Preset preset)
{
    const auto [red, green, blue] = color;
    if (preset == Preset::None || preset == Preset::Unknown) {
        return color;
    } else if (preset == Preset::Mono) {
        const double luminance = luma(red, green, blue);
        return {luminance, luminance, luminance};
    } else if (preset == Preset::Silver) {
        const double luminance = luma(red, green, blue);
        const Rgb gray{luminance, luminance, luminance};
        return clampedColor(contrastColor(gray, 1.28));
    } else if (preset == Preset::Vivid) {
        const double luminance = luma(red, green, blue);
        color.red = std::clamp((red - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.green = std::clamp((green - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.blue = std::clamp((blue - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.red = luminance + (color.red - luminance) * 1.25;
        color.green = luminance + (color.green - luminance) * 1.25;
        color.blue = luminance + (color.blue - luminance) * 1.25;
    } else if (preset == Preset::Warm || preset == Preset::Vintage) {
        const double amount = preset == Preset::Warm ? 0.12 : 0.08;
        color.red = std::min(1.0, red + amount * (1.0 - red));
        color.blue = std::max(0.0, blue - amount * blue);
        if (preset == Preset::Vintage) {
            color.red = (color.red - 0.5) * 0.82 + 0.54;
            color.green = (green - 0.5) * 0.82 + 0.52;
            color.blue = (color.blue - 0.5) * 0.82 + 0.48;
        }
    } else if (preset == Preset::Cool) {
        color.red = std::max(0.0, red - 0.12 * red);
        color.blue = std::min(1.0, blue + 0.12 * (1.0 - blue));
    } else if (preset == Preset::Fresh) {
        // CSS: brightness(1.06) contrast(1.07) saturate(1.12)
        color = brightnessColor(color, 1.06);
        color = contrastColor(color, 1.07);
        color = saturationColor(color, 1.12);
        return clampedColor(color);
    } else if (preset == Preset::Film) {
        // CSS: sepia(.22) contrast(1.18) saturate(.85)
        color = sepiaColor(color, 0.22);
        color = contrastColor(color, 1.18);
        color = saturationColor(color, 0.85);
        return clampedColor(color);
    } else if (preset == Preset::Faded) {
        // CSS: brightness(1.1) contrast(.82) saturate(.76)
        color = brightnessColor(color, 1.10);
        color = contrastColor(color, 0.82);
        color = saturationColor(color, 0.76);
        return clampedColor(color);
    } else if (preset == Preset::Sunset) {
        // CSS: sepia(.4) saturate(1.3)
        color = sepiaColor(color, 0.40);
        color = saturationColor(color, 1.30);
        return clampedColor(color);
    } else if (preset == Preset::Soft) {
        // CSS: brightness(1.1) contrast(.86) saturate(.92)
        color = brightnessColor(color, 1.10);
        color = contrastColor(color, 0.86);
        color = saturationColor(color, 0.92);
        return clampedColor(color);
    } else if (preset == Preset::Cream) {
        // CSS: sepia(.2) brightness(1.08) contrast(.9)
        color = sepiaColor(color, 0.20);
        color = brightnessColor(color, 1.08);
        color = contrastColor(color, 0.90);
        return clampedColor(color);
    }
    return color;
}

quint32 grainHash(int x, int y)
{
    quint32 value = static_cast<quint32>(x) * 0x9e3779b1u
        ^ static_cast<quint32>(y) * 0x85ebca77u ^ 0x27d4eb2fu;
    value ^= value >> 15;
    value *= 0x2c1b3c6du;
    value ^= value >> 12;
    value *= 0x297a2d39u;
    value ^= value >> 15;
    return value;
}

bool isFloatingFormat(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

// Floating formats carry alpha as the fourth 16-bit half or 32-bit float
// element. Copy it back byte-for-byte so extended processing never quantizes
// or otherwise disturbs the alpha payload.
void restoreFloatingAlpha(QImage &result, const QImage &source)
{
    if (result.format() != source.format() || result.size() != source.size())
        return;
    const int elementBytes = source.depth() / 32; // 2 for half, 4 for float
    if (elementBytes <= 0)
        return;
    const qsizetype resultStride = result.bytesPerLine();
    const qsizetype sourceStride = source.bytesPerLine();
    uchar *resultBase = result.bits();
    const uchar *sourceBase = source.constBits();
    for (int y = 0; y < result.height(); ++y) {
        uchar *destination = resultBase + y * resultStride;
        const uchar *origin = sourceBase + y * sourceStride;
        for (int x = 0; x < result.width(); ++x) {
            std::memcpy(destination + (x * 4 + 3) * elementBytes,
                        origin + (x * 4 + 3) * elementBytes,
                        static_cast<std::size_t>(elementBytes));
        }
    }
}

Parameters sanitized(const Parameters &input)
{
    Parameters output = input;
    output.exposure = bounded(input.exposure, 4.0);
    output.brightness = bounded(input.brightness, 1.0);
    output.contrast = bounded(input.contrast, 1.0);
    output.saturation = bounded(input.saturation, 1.0);
    output.highlights = bounded(input.highlights, 1.0);
    output.shadows = bounded(input.shadows, 1.0);
    output.whites = bounded(input.whites, 1.0);
    output.blacks = bounded(input.blacks, 1.0);
    output.temperature = bounded(input.temperature, 1.0);
    output.tint = bounded(input.tint, 1.0);
    output.vibrance = bounded(input.vibrance, 1.0);
    output.fade = std::clamp(bounded(input.fade, 1.0), 0.0, 1.0);

    for (auto &channel : output.hsl) {
        channel.hue = bounded(channel.hue, 1.0);
        channel.saturation = bounded(channel.saturation, 1.0);
        channel.luminance = bounded(channel.luminance, 1.0);
    }
    for (auto &curve : output.curves) {
        for (int point = 0; point < CurvePointCount; ++point) {
            curve.points[point] = std::isfinite(curve.points[point])
                ? clamp01(curve.points[point])
                : point * 0.25;
        }
    }
    for (auto &zone : output.grade) {
        zone.hue = std::isfinite(zone.hue) ? normalizeHue(zone.hue) : 0.0;
        zone.saturation =
            std::isfinite(zone.saturation) ? std::clamp(zone.saturation, 0.0, 1.0) : 0.0;
        zone.luminance = bounded(zone.luminance, 1.0);
    }
    output.gradeBlending = std::isfinite(input.gradeBlending)
        ? std::clamp(input.gradeBlending, 0.0, 1.0)
        : 0.5;
    output.gradeBalance = bounded(input.gradeBalance, 1.0);

    output.texture = std::clamp(bounded(input.texture, 1.0), 0.0, 1.0);
    output.clarity = std::clamp(bounded(input.clarity, 1.0), 0.0, 1.0);
    output.dehaze = std::clamp(bounded(input.dehaze, 1.0), 0.0, 1.0);
    output.sharpen = std::clamp(bounded(input.sharpen, 1.0), 0.0, 1.0);
    output.noise = std::clamp(bounded(input.noise, 1.0), 0.0, 1.0);
    output.colorNoise = std::clamp(bounded(input.colorNoise, 1.0), 0.0, 1.0);
    output.vignette = bounded(input.vignette, 1.0);
    output.feather = std::clamp(bounded(input.feather, 1.0), 0.0, 1.0);
    output.grain = std::clamp(bounded(input.grain, 1.0), 0.0, 1.0);

    output.filterIntensity = std::isfinite(input.filterIntensity)
        ? std::clamp(input.filterIntensity, 0.0, 1.0)
        : 0.0;
    return output;
}

} // namespace

// ---------------------------------------------------------------------------
// Public key/value API
// ---------------------------------------------------------------------------

bool isParameterKey(const QString &key)
{
    return registry().lookup.contains(key);
}

QStringList parameterKeys()
{
    return registry().keys;
}

bool setParameter(Parameters &parameters, const QString &key, double uiValue)
{
    const Registry &table = registry();
    const auto iterator = table.lookup.constFind(key);
    if (iterator == table.lookup.constEnd())
        return false;
    const KeyInfo &info = table.infos[static_cast<std::size_t>(*iterator)];
    const double clampedUi =
        std::isfinite(uiValue) ? std::clamp(uiValue, info.uiMin, info.uiMax) : 0.0;
    assignStoredValue(parameters, info, clampedUi * info.storedPerUi);
    return true;
}

double parameterValue(const Parameters &parameters, const QString &key)
{
    const Registry &table = registry();
    const auto iterator = table.lookup.constFind(key);
    if (iterator == table.lookup.constEnd())
        return std::numeric_limits<double>::quiet_NaN();
    const KeyInfo &info = table.infos[static_cast<std::size_t>(*iterator)];
    return storedValue(parameters, info) * info.uiPerStored;
}

QVariantMap toUiValues(const Parameters &parameters)
{
    const Registry &table = registry();
    QVariantMap values;
    for (std::size_t i = 0; i < table.infos.size(); ++i) {
        values.insert(table.keys[static_cast<qsizetype>(i)],
                      storedValue(parameters, table.infos[i]) * table.infos[i].uiPerStored);
    }
    return values;
}

bool isGpuPreviewKey(const QString &key)
{
    return key == QStringLiteral("exposure") || key == QStringLiteral("brightness")
        || key == QStringLiteral("contrast") || key == QStringLiteral("saturation")
        || key == QStringLiteral("highlights") || key == QStringLiteral("shadows")
        || key == QStringLiteral("whites") || key == QStringLiteral("blacks")
        || key == QStringLiteral("temperature") || key == QStringLiteral("tint")
        || key == QStringLiteral("vibrance");
}

bool isGpuPreviewSupported(const Parameters &input)
{
    const Parameters p = sanitized(input);

    // Stages the shader does not implement. Neutral values are allowed so a
    // user can drag a supported key after a curve was reset to linear, etc.
    if (p.fade != 0.0)
        return false;
    for (const auto &channel : p.hsl) {
        if (channel.hue != 0.0 || channel.saturation != 0.0
            || channel.luminance != 0.0)
            return false;
    }
    for (const auto &curve : p.curves) {
        if (!isLinearCurve(curve))
            return false;
    }
    for (const auto &zone : p.grade) {
        // Hue alone cannot change pixels; blending/balance only shape an
        // already-active zone.
        if (zone.saturation != 0.0 || zone.luminance != 0.0)
            return false;
    }
    if (p.texture != 0.0 || p.clarity != 0.0 || p.dehaze != 0.0
        || p.sharpen != 0.0 || p.noise != 0.0 || p.colorNoise != 0.0
        || p.vignette != 0.0 || p.grain != 0.0)
        return false;

    if (p.filterIntensity > 0.0 && isActivePreset(parsePreset(p.filterPreset)))
        return false;
    return true;
}

// ---------------------------------------------------------------------------
// Dispatch helper
// ---------------------------------------------------------------------------

namespace Internal {

bool hasExtendedParameters(const Parameters &parameters)
{
    const auto active = [](double value) {
        return std::isfinite(value) && value != 0.0;
    };
    if (active(parameters.highlights) || active(parameters.shadows)
        || active(parameters.whites) || active(parameters.blacks)
        || active(parameters.temperature) || active(parameters.tint)
        || active(parameters.vibrance) || active(parameters.fade))
        return true;

    for (const auto &channel : parameters.hsl) {
        if (active(channel.hue) || active(channel.saturation) || active(channel.luminance))
            return true;
    }
    for (const auto &curve : parameters.curves) {
        if (!isLinearCurve(curve))
            return true;
    }
    for (const auto &zone : parameters.grade) {
        if (active(zone.saturation) || active(zone.luminance))
            return true;
    }
    if (active(parameters.texture) || active(parameters.clarity)
        || active(parameters.dehaze) || active(parameters.sharpen)
        || active(parameters.noise) || active(parameters.colorNoise)
        || active(parameters.vignette) || active(parameters.grain))
        return true;
    // Feather, grade blending/balance and grade hue alone cannot change
    // pixels, so they deliberately stay on the neutral fast path.
    return false;
}

QImage applyExtended(const QImage &source, const Parameters &parameters)
{
    const Parameters p = sanitized(parameters);
    const int width = source.width();
    const int height = source.height();
    if (width <= 0 || height <= 0)
        return {};

    QImage work = source.convertToFormat(QImage::Format_RGBA64);
    if (work.isNull())
        return {};

    const qsizetype stride = work.bytesPerLine();
    auto *base = work.bits();
    const int workers = Detail::rowWorkerCount(width, height);

    // --- Stages 1-6: one fused per-pixel pass ----------------------------
    const bool whiteBalanceActive = p.temperature != 0.0 || p.tint != 0.0;
    const double gainRed = 1.0 + 0.30 * p.temperature + 0.10 * p.tint;
    const double gainGreen = 1.0 - 0.20 * p.tint;
    const double gainBlue = 1.0 - 0.30 * p.temperature + 0.10 * p.tint;

    const bool toneActive = p.exposure != 0.0 || p.brightness != 0.0 || p.contrast != 0.0;
    const double exposureFactor = std::exp2(p.exposure);
    const double contrastFactor = 1.0 + p.contrast;

    const bool tonalAdjustActive =
        p.highlights != 0.0 || p.shadows != 0.0 || p.whites != 0.0 || p.blacks != 0.0;
    const bool saturationActive = p.saturation != 0.0;
    const bool vibranceActive = p.vibrance != 0.0;

    std::array<bool, HslChannelCount> hslActive{};
    bool anyHsl = false;
    for (int channel = 0; channel < HslChannelCount; ++channel) {
        hslActive[channel] = p.hsl[channel].hue != 0.0
            || p.hsl[channel].saturation != 0.0 || p.hsl[channel].luminance != 0.0;
        anyHsl = anyHsl || hslActive[channel];
    }
    static constexpr double kHueCenters[HslChannelCount]{0.0,  30.0, 60.0,  120.0,
                                                        180.0, 240.0, 280.0, 320.0};

    std::array<bool, CurveChannelCount> curveActive{};
    bool anyCurve = false;
    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        curveActive[channel] = !isLinearCurve(p.curves[channel]);
        anyCurve = anyCurve || curveActive[channel];
    }

    std::array<bool, GradeZoneCount> gradeZoneActive{};
    bool anyGrade = false;
    for (int zone = 0; zone < GradeZoneCount; ++zone) {
        gradeZoneActive[zone] =
            p.grade[zone].saturation != 0.0 || p.grade[zone].luminance != 0.0;
        anyGrade = anyGrade || gradeZoneActive[zone];
    }
    const double gradePivot = 0.5 - 0.25 * p.gradeBalance;
    const double gradeSigma = 0.20 + 0.20 * p.gradeBlending;
    const double gradeInv = 1.0 / (2.0 * gradeSigma * gradeSigma);

    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto *pixels = reinterpret_cast<QRgba64 *>(base + y * stride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel = pixels[x];
                double red = pixel.red() / 65535.0;
                double green = pixel.green() / 65535.0;
                double blue = pixel.blue() / 65535.0;

                // 1. White balance.
                if (whiteBalanceActive) {
                    red *= gainRed;
                    green *= gainGreen;
                    blue *= gainBlue;
                }

                // 2. Tonal.
                if (toneActive) {
                    const auto tone = [&](double value) {
                        return (value * exposureFactor - 0.5) * contrastFactor + 0.5
                            + p.brightness;
                    };
                    red = tone(red);
                    green = tone(green);
                    blue = tone(blue);
                }
                red = clamp01(red);
                green = clamp01(green);
                blue = clamp01(blue);
                if (tonalAdjustActive) {
                    const double level = luma(red, green, blue);
                    const double shadowMask = 1.0 - smoothstep(0.0, 0.55, level);
                    const double highlightMask = smoothstep(0.45, 1.0, level);
                    const double blackMask = 1.0 - smoothstep(0.0, 0.25, level);
                    const double whiteMask = smoothstep(0.75, 1.0, level);
                    const double delta = 0.5
                        * (p.shadows * shadowMask + p.highlights * highlightMask
                           + p.blacks * blackMask + p.whites * whiteMask);
                    red += delta;
                    green += delta;
                    blue += delta;
                    red = clamp01(red);
                    green = clamp01(green);
                    blue = clamp01(blue);
                }

                // 3. Saturation and vibrance.
                if (saturationActive) {
                    const double level = luma(red, green, blue);
                    const double factor = 1.0 + p.saturation;
                    red = level + (red - level) * factor;
                    green = level + (green - level) * factor;
                    blue = level + (blue - level) * factor;
                }
                if (vibranceActive) {
                    const double maximum = std::max({red, green, blue});
                    const double minimum = std::min({red, green, blue});
                    const double chroma = maximum - minimum;
                    const double currentSaturation = maximum > 1e-9 ? chroma / maximum : 0.0;
                    const double factor = 1.0 + p.vibrance * (1.0 - currentSaturation) * 0.8;
                    const double level = luma(red, green, blue);
                    red = level + (red - level) * factor;
                    green = level + (green - level) * factor;
                    blue = level + (blue - level) * factor;
                }
                red = clamp01(red);
                green = clamp01(green);
                blue = clamp01(blue);

                // 4. HSL targeted adjustments.
                if (anyHsl) {
                    const double maximum = std::max({red, green, blue});
                    const double minimum = std::min({red, green, blue});
                    if (maximum - minimum > 1e-6 && maximum > 1e-9) {
                        const double hue = hueDegrees(red, green, blue, maximum, minimum);
                        double hueShift = 0.0;
                        double saturationMultiplier = 1.0;
                        double luminanceShift = 0.0;
                        for (int channel = 0; channel < HslChannelCount; ++channel) {
                            if (!hslActive[channel])
                                continue;
                            const double weight = hueWeight(hue, kHueCenters[channel]);
                            if (weight <= 0.0)
                                continue;
                            hueShift += weight * p.hsl[channel].hue * 30.0;
                            saturationMultiplier *=
                                1.0 + weight * p.hsl[channel].saturation;
                            luminanceShift += weight * p.hsl[channel].luminance * 0.5;
                        }
                        const double saturation =
                            clamp01((maximum - minimum) / maximum * saturationMultiplier);
                        rgbFromHsv(hue + hueShift, saturation, maximum, red, green, blue);
                        if (luminanceShift != 0.0) {
                            red = clamp01(red + luminanceShift);
                            green = clamp01(green + luminanceShift);
                            blue = clamp01(blue + luminanceShift);
                        }
                    }
                }

                // 5. Tone curves: RGB first, then the per-channel curves.
                if (anyCurve) {
                    if (curveActive[0]) {
                        red = evaluateCurve(p.curves[0], red);
                        green = evaluateCurve(p.curves[0], green);
                        blue = evaluateCurve(p.curves[0], blue);
                    }
                    if (curveActive[1])
                        red = evaluateCurve(p.curves[1], red);
                    if (curveActive[2])
                        green = evaluateCurve(p.curves[2], green);
                    if (curveActive[3])
                        blue = evaluateCurve(p.curves[3], blue);
                }
                red = clamp01(red);
                green = clamp01(green);
                blue = clamp01(blue);

                // 6. Colour grading.
                if (anyGrade) {
                    const double level = luma(red, green, blue);
                    const double shadowWeight = std::exp(-(level * level) * gradeInv);
                    const double midWeight =
                        std::exp(-((level - gradePivot) * (level - gradePivot)) * gradeInv);
                    const double highWeight =
                        std::exp(-((level - 1.0) * (level - 1.0)) * gradeInv);
                    const double sum = shadowWeight + midWeight + highWeight;
                    if (sum > 0.0) {
                        const auto applyZone = [&](double weight,
                                                   const GradeZoneAdjustment &zone) {
                            if (zone.saturation != 0.0) {
                                double zoneRed;
                                double zoneGreen;
                                double zoneBlue;
                                rgbFromHsv(zone.hue, 1.0, 1.0, zoneRed, zoneGreen, zoneBlue);
                                const double zoneLevel = luma(zoneRed, zoneGreen, zoneBlue);
                                const double amount = zone.saturation * weight * 0.5;
                                red += (zoneRed - zoneLevel) * amount;
                                green += (zoneGreen - zoneLevel) * amount;
                                blue += (zoneBlue - zoneLevel) * amount;
                            }
                            if (zone.luminance != 0.0) {
                                const double amount = zone.luminance * weight * 0.5;
                                red += amount;
                                green += amount;
                                blue += amount;
                            }
                        };
                        if (gradeZoneActive[0])
                            applyZone(shadowWeight / sum, p.grade[0]);
                        if (gradeZoneActive[1])
                            applyZone(midWeight / sum, p.grade[1]);
                        if (gradeZoneActive[2])
                            applyZone(highWeight / sum, p.grade[2]);
                    }
                }
                red = clamp01(red);
                green = clamp01(green);
                blue = clamp01(blue);

                pixels[x] = QRgba64::fromRgba64(toChannel(red), toChannel(green),
                                                toChannel(blue), pixel.alpha());
            }
        }
    });

    // --- Stage 7: detail (neighbourhood) --------------------------------
    const bool textureActive = p.texture != 0.0;
    const bool clarityActive = p.clarity != 0.0;
    const bool dehazeActive = p.dehaze != 0.0;
    const bool sharpenActive = p.sharpen != 0.0;
    const bool luminanceNoiseActive = p.noise != 0.0;
    const bool colorNoiseActive = p.colorNoise != 0.0;
    const bool vignetteActive = p.vignette != 0.0;
    const bool grainActive = p.grain != 0.0;
    const bool fadeActive = p.fade != 0.0;
    const bool needSmallBlur = textureActive || sharpenActive || luminanceNoiseActive;
    const bool needLargeBlur = clarityActive;

    std::vector<float> blurSmall;
    std::vector<float> blurLarge;
    std::vector<float> blurScratch;
    const int minimumDimension = std::min(width, height);
    if (needSmallBlur) {
        const int radius = std::clamp(minimumDimension / 500, 1, 3);
        boxBlurLuminance(work, blurSmall, blurScratch, radius);
    }
    if (needLargeBlur) {
        const int radius = std::clamp(minimumDimension / 50, 4, 64);
        boxBlurLuminance(work, blurLarge, blurScratch, radius);
    }

    if (textureActive || clarityActive || dehazeActive || sharpenActive
        || luminanceNoiseActive) {
        Detail::parallelRows(height, workers, [&](int begin, int end) {
            for (int y = begin; y < end; ++y) {
                auto *pixels = reinterpret_cast<QRgba64 *>(base + y * stride);
                for (int x = 0; x < width; ++x) {
                    const QRgba64 pixel = pixels[x];
                    double red = pixel.red() / 65535.0;
                    double green = pixel.green() / 65535.0;
                    double blue = pixel.blue() / 65535.0;
                    const auto offset = static_cast<std::size_t>(y) * width + x;
                    const double originalLevel = luma(red, green, blue);

                    if (textureActive) {
                        const double detail = originalLevel - blurSmall[offset];
                        const double amount = p.texture * detail * 0.8;
                        red += amount;
                        green += amount;
                        blue += amount;
                    }
                    if (clarityActive) {
                        const double detail = originalLevel - blurLarge[offset];
                        const double amount = p.clarity * detail;
                        red += amount;
                        green += amount;
                        blue += amount;
                    }
                    if (dehazeActive) {
                        red = (red - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                        green = (green - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                        blue = (blue - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                        const double level = luma(red, green, blue);
                        const double factor = 1.0 + p.dehaze * 0.4;
                        red = level + (red - level) * factor;
                        green = level + (green - level) * factor;
                        blue = level + (blue - level) * factor;
                    }
                    if (sharpenActive) {
                        const double detail = originalLevel - blurSmall[offset];
                        const double amount = p.sharpen * detail * 1.5;
                        red += amount;
                        green += amount;
                        blue += amount;
                    }
                    if (luminanceNoiseActive) {
                        const double level = luma(red, green, blue);
                        const double target =
                            level + (blurSmall[offset] - level) * (p.noise * 0.8);
                        const double amount = target - level;
                        red += amount;
                        green += amount;
                        blue += amount;
                    }

                    pixels[x] = QRgba64::fromRgba64(toChannel(red), toChannel(green),
                                                    toChannel(blue), pixel.alpha());
                }
            }
        });
    }

    // Colour noise reduction runs on a private copy so the read-only source
    // neighbourhood and the written pixels never race across worker threads.
    if (colorNoiseActive) {
        const QImage before = work; // implicitly shared with `work`
        QImage reduced = work.copy();
        const qsizetype beforeStride = before.bytesPerLine();
        const auto *beforeBase = before.constBits();
        const qsizetype reducedStride = reduced.bytesPerLine();
        auto *reducedBase = reduced.bits();
        const double blend = p.colorNoise * 0.8;
        Detail::parallelRows(height, workers, [&](int begin, int end) {
            for (int y = begin; y < end; ++y) {
                auto *destination =
                    reinterpret_cast<QRgba64 *>(reducedBase + y * reducedStride);
                for (int x = 0; x < width; ++x) {
                    const QRgba64 pixel =
                        reinterpret_cast<const QRgba64 *>(beforeBase + y * beforeStride)[x];
                    const int x0 = std::max(0, x - 1);
                    const int x1 = std::min(width - 1, x + 1);
                    const int y0 = std::max(0, y - 1);
                    const int y1 = std::min(height - 1, y + 1);
                    double red = 0.0;
                    double green = 0.0;
                    double blue = 0.0;
                    int count = 0;
                    for (int yy = y0; yy <= y1; ++yy) {
                        const auto *row =
                            reinterpret_cast<const QRgba64 *>(beforeBase + yy * beforeStride);
                        for (int xx = x0; xx <= x1; ++xx) {
                            red += row[xx].red() / 65535.0;
                            green += row[xx].green() / 65535.0;
                            blue += row[xx].blue() / 65535.0;
                            ++count;
                        }
                    }
                    const double inverse = 1.0 / count;
                    const double sourceRed = pixel.red() / 65535.0;
                    const double sourceGreen = pixel.green() / 65535.0;
                    const double sourceBlue = pixel.blue() / 65535.0;
                    destination[x] = QRgba64::fromRgba64(
                        toChannel(sourceRed + (red * inverse - sourceRed) * blend),
                        toChannel(sourceGreen + (green * inverse - sourceGreen) * blend),
                        toChannel(sourceBlue + (blue * inverse - sourceBlue) * blend),
                        pixel.alpha());
                }
            }
        });
        work = reduced;
    }

    // --- Stages 8-9: effects, then the existing filter preset -----------
    const Preset preset = parsePreset(p.filterPreset);
    const bool filterActive = p.filterIntensity > 0.0 && isActivePreset(preset);
    const double halfWidth = width * 0.5;
    const double halfHeight = height * 0.5;
    const double vignetteInner = 0.15 + 0.55 * (1.0 - p.feather);

    if (vignetteActive || grainActive || fadeActive || filterActive) {
        // `base` may be stale if the colour-noise pass replaced `work`.
        base = work.bits();
        const qsizetype finalStride = work.bytesPerLine();
        Detail::parallelRows(height, workers, [&](int begin, int end) {
            for (int y = begin; y < end; ++y) {
                auto *pixels = reinterpret_cast<QRgba64 *>(base + y * finalStride);
                for (int x = 0; x < width; ++x) {
                    const QRgba64 pixel = pixels[x];
                    double red = pixel.red() / 65535.0;
                    double green = pixel.green() / 65535.0;
                    double blue = pixel.blue() / 65535.0;

                    if (vignetteActive) {
                        const double nx = (x + 0.5 - halfWidth) / halfWidth;
                        const double ny = (y + 0.5 - halfHeight) / halfHeight;
                        const double distance = std::sqrt((nx * nx + ny * ny) * 0.5);
                        const double mask = smoothstep(vignetteInner, 1.0, distance);
                        const double factor = 1.0 + p.vignette * mask;
                        red *= factor;
                        green *= factor;
                        blue *= factor;
                    }
                    if (grainActive) {
                        const quint32 hash = grainHash(x, y);
                        const double noise = double(hash) * (2.0 / 4294967295.0) - 1.0;
                        const double amount = noise * p.grain * 0.12;
                        red += amount;
                        green += amount;
                        blue += amount;
                    }
                    if (fadeActive) {
                        const double lift = p.fade * 0.15;
                        red = red * (1.0 - lift) + lift;
                        green = green * (1.0 - lift) + lift;
                        blue = blue * (1.0 - lift) + lift;
                    }
                    if (filterActive) {
                        const Rgb target = filterTarget({red, green, blue}, preset);
                        const auto blend = [&](double value, double filtered) {
                            if (value == filtered)
                                return value;
                            if (preset == Preset::Vivid)
                                return clamp01(value + (filtered - value) * p.filterIntensity);
                            return value + (clamp01(filtered) - value) * p.filterIntensity;
                        };
                        red = blend(red, target.red);
                        green = blend(green, target.green);
                        blue = blend(blue, target.blue);
                    }

                    pixels[x] = QRgba64::fromRgba64(toChannel(red), toChannel(green),
                                                    toChannel(blue), pixel.alpha());
                }
            }
        });
    }

    QImage result = work;
    if (isFloatingFormat(source.format())) {
        result = work.convertToFormat(source.format());
        if (result.isNull())
            return {};
        restoreFloatingAlpha(result, source);
    }
    if (result.colorSpace() != source.colorSpace())
        result.setColorSpace(source.colorSpace());
    result.setDotsPerMeterX(source.dotsPerMeterX());
    result.setDotsPerMeterY(source.dotsPerMeterY());
    return result;
}

} // namespace Internal

} // namespace NekoPic::Adjustments
