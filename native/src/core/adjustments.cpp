#include "adjustments.h"

#include "colorpipeline.h"
#include "rowparallel.h"

#include <qfloat16.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace NekoPic::Adjustments {
namespace {

constexpr int kChannelValues = 65536;
constexpr double kChannelMax = 65535.0;

// The historical saturation pass is mathematically a no-op at saturation 0,
// but `luminance + (red - luminance)` can still round by an ulp. When a channel
// sits this close to a 16-bit rounding boundary, recompute that expression
// exactly so the shortcut stays bit-identical. Over the clamped parameter range
// the worst-case difference is below 4e-9 units, so this margin is safe.
constexpr double kRoundingGuard = 1e-7;

double bounded(double value, double limit)
{
    return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
}

// std::lround without a libm call. The argument is clamped to [0, 1], so the
// scaled value is non-negative and "half away from zero" is "half up". floor()
// and the subtraction are exact for these values, so the result matches
// lround exactly.
quint16 channel(double value)
{
    const double scaled = std::clamp(value, 0.0, 1.0) * kChannelMax;
    const double base = std::floor(scaled);
    return static_cast<quint16>(base + (scaled - base >= 0.5 ? 1.0 : 0.0));
}

bool nearRoundingBoundary(double value)
{
    const double scaled = value * kChannelMax;
    const double fraction = scaled - std::floor(scaled);
    return std::abs(fraction - 0.5) < kRoundingGuard;
}

struct Rgb {
    double red;
    double green;
    double blue;
};

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

double presetLuma(Rgb color)
{
    return 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue;
}

Rgb clampedColor(Rgb color)
{
    return {std::clamp(color.red, 0.0, 1.0), std::clamp(color.green, 0.0, 1.0),
            std::clamp(color.blue, 0.0, 1.0)};
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
    const double luminance = presetLuma(color);
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

// The single source of truth for look formulas. Both the floating-point path
// and the integer path below call this, so their results stay in lockstep.
Rgb filterTarget(Rgb color, Preset preset)
{
    const auto [red, green, blue] = color;
    if (preset == Preset::None || preset == Preset::Unknown) {
        return color;
    } else if (preset == Preset::Mono) {
        const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
        return {luminance, luminance, luminance};
    } else if (preset == Preset::Silver) {
        const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
        const Rgb gray{luminance, luminance, luminance};
        return clampedColor(contrastColor(gray, 1.28));
    } else if (preset == Preset::Vivid) {
        const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
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

// Target used by the floating-point path.
Rgb floatingFilterTarget(Rgb color, Preset preset)
{
    return filterTarget(color, preset);
}

// Target used by the integer path's second pass, which works on the already
// quantized channels. Kept numerically identical to the historical code.
void integerFilterTarget(Preset preset, double red, double green, double blue,
                         double &targetRed, double &targetGreen, double &targetBlue)
{
    const Rgb target = filterTarget({red, green, blue}, preset);
    targetRed = target.red;
    targetGreen = target.green;
    targetBlue = target.blue;
}

bool isFloating(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

// v / 65535 for every 16-bit channel value, computed with the same division
// the historical code used. Shared by the tone table and the filter pass.
const std::vector<double> &unitTable()
{
    static const std::vector<double> table = [] {
        std::vector<double> values(kChannelValues);
        for (int i = 0; i < kChannelValues; ++i)
            values[i] = i / kChannelMax;
        return values;
    }();
    return table;
}

// Tone transfer for one apply() call. `rounded` is channel(values[i]) and
// `nearBoundary` marks the entries that need the exact legacy saturation
// expression even when saturation is zero.
struct ToneTable {
    std::vector<double> values;
    std::vector<quint16> rounded;
    std::vector<std::uint8_t> nearBoundary;
};

ToneTable buildToneTable(double exposureFactor, double contrastFactor, double brightness)
{
    const auto &unit = unitTable();
    ToneTable table;
    table.values.resize(kChannelValues);
    table.rounded.resize(kChannelValues);
    table.nearBoundary.resize(kChannelValues);
    for (int i = 0; i < kChannelValues; ++i) {
        // Keep this expression identical to the historical per-pixel maths:
        // (value / 65535 * exposureFactor - 0.5) * contrastFactor + 0.5 + brightness
        const double value = (unit[i] * exposureFactor - 0.5) * contrastFactor + 0.5 + brightness;
        table.values[i] = value;
        table.rounded[i] = channel(value);
        table.nearBoundary[i] = nearRoundingBoundary(value) ? 1 : 0;
    }
    return table;
}

using FilterMap = std::vector<quint16>;

// Warm, vintage and cool transform each channel independently once the first
// pass has been quantized, so their second pass collapses to a 16-bit lookup.
FilterMap buildFilterMap(Preset preset, int channelIndex, double intensity)
{
    const auto &unit = unitTable();
    FilterMap map(kChannelValues);
    for (int i = 0; i < kChannelValues; ++i) {
        const double value = unit[i];
        double targetRed = value;
        double targetGreen = value;
        double targetBlue = value;
        integerFilterTarget(preset, value, value, value, targetRed, targetGreen, targetBlue);
        const double target = channelIndex == 0 ? targetRed
            : channelIndex == 1                ? targetGreen
                                               : targetBlue;
        map[i] = channel(value + (target - value) * intensity);
    }
    return map;
}

QImage applyFloating(const QImage &source, double exposure, double brightness,
                     double contrast, double saturation, Preset preset, double intensity)
{
    auto result = source.copy();
    if (result.isNull())
        return {};
    const bool half = source.depth() == 64;
    const bool premultiplied = source.format() == QImage::Format_RGBA16FPx4_Premultiplied
        || source.format() == QImage::Format_RGBA32FPx4_Premultiplied;
    const double exposureFactor = std::exp2(exposure);
    const bool toneChanged = exposure != 0 || brightness != 0 || contrast != 0;
    const bool filterActive = intensity > 0.0 && isActivePreset(preset);

    const int width = result.width();
    const int height = result.height();
    const qsizetype stride = result.bytesPerLine();
    auto *base = result.bits();

    auto processRange = [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto *floats = half ? nullptr : reinterpret_cast<float *>(base + y * stride);
            auto *halves = half ? reinterpret_cast<qfloat16 *>(base + y * stride) : nullptr;
            for (int x = 0; x < width; ++x) {
                const auto offset = x * 4;
                const double alpha = half ? float(halves[offset + 3]) : floats[offset + 3];
                if (premultiplied && alpha <= 0)
                    continue;
                const double scale = premultiplied ? alpha : 1.0;
                Rgb original{(half ? float(halves[offset]) : floats[offset]) / scale,
                             (half ? float(halves[offset + 1]) : floats[offset + 1]) / scale,
                             (half ? float(halves[offset + 2]) : floats[offset + 2]) / scale};
                auto color = original;
                if (toneChanged) {
                    const auto tone = [=](double value) {
                        return (value * exposureFactor - 0.5) * (1.0 + contrast) + 0.5 + brightness;
                    };
                    color = {tone(color.red), tone(color.green), tone(color.blue)};
                }
                if (saturation != 0) {
                    const double luminance =
                        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue;
                    color = {luminance + (color.red - luminance) * (1.0 + saturation),
                             luminance + (color.green - luminance) * (1.0 + saturation),
                             luminance + (color.blue - luminance) * (1.0 + saturation)};
                }
                if (filterActive) {
                    const auto target = floatingFilterTarget(color, preset);
                    const auto blend = [=](double value, double filtered) {
                        if (value == filtered)
                            return value;
                        // Vivid can overshoot during saturation. Match the integer
                        // path by blending first, then clipping its SDR output.
                        if (preset == Preset::Vivid)
                            return std::clamp(value + (filtered - value) * intensity, 0.0, 1.0);
                        // Other presets have SDR targets; untouched channels retain HDR values.
                        return value + (std::clamp(filtered, 0.0, 1.0) - value) * intensity;
                    };
                    color = {blend(color.red, target.red), blend(color.green, target.green),
                             blend(color.blue, target.blue)};
                }
                const double before[]{original.red, original.green, original.blue};
                const double after[]{color.red, color.green, color.blue};
                for (int c = 0; c < 3; ++c) {
                    if (after[c] == before[c])
                        continue;
                    if (half)
                        halves[offset + c] = qfloat16(float(after[c] * scale));
                    else
                        floats[offset + c] = float(after[c] * scale);
                }
                // Alpha is never rewritten, including half/float payload bits.
            }
        }
    };

    Detail::parallelRows(height, Detail::rowWorkerCount(width, height), processRange);
    return result;
}

QImage applyInteger(const QImage &source, double exposureFactor, double contrastFactor,
                    double brightness, double saturationFactor, bool hasSaturation,
                    Preset preset, double intensity)
{
    QImage result = source.convertToFormat(QImage::Format_RGBA64);
    if (result.isNull())
        return {};

    const bool filterActive = intensity > 0.0 && isActivePreset(preset);
    const bool filterSeparable = filterActive
        && (preset == Preset::Warm || preset == Preset::Vintage || preset == Preset::Cool);
    const auto tone = buildToneTable(exposureFactor, contrastFactor, brightness);

    const auto &unit = unitTable();
    FilterMap filterRed;
    FilterMap filterGreen;
    FilterMap filterBlue;
    if (filterSeparable) {
        filterRed = buildFilterMap(preset, 0, intensity);
        filterGreen = buildFilterMap(preset, 1, intensity);
        filterBlue = buildFilterMap(preset, 2, intensity);
    }

    const int width = result.width();
    const int height = result.height();
    const qsizetype stride = result.bytesPerLine();
    auto *base = result.bits();

    auto processRange = [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto *pixels = reinterpret_cast<QRgba64 *>(base + y * stride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel = pixels[x];
                const quint16 redValue = pixel.red();
                const quint16 greenValue = pixel.green();
                const quint16 blueValue = pixel.blue();

                quint16 outRed;
                quint16 outGreen;
                quint16 outBlue;
                if (hasSaturation) {
                    double red = tone.values[redValue];
                    double green = tone.values[greenValue];
                    double blue = tone.values[blueValue];
                    const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
                    red = luminance + (red - luminance) * saturationFactor;
                    green = luminance + (green - luminance) * saturationFactor;
                    blue = luminance + (blue - luminance) * saturationFactor;
                    outRed = channel(red);
                    outGreen = channel(green);
                    outBlue = channel(blue);
                } else if (tone.nearBoundary[redValue] || tone.nearBoundary[greenValue]
                           || tone.nearBoundary[blueValue]) {
                    const double red = tone.values[redValue];
                    const double green = tone.values[greenValue];
                    const double blue = tone.values[blueValue];
                    const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
                    outRed = channel(luminance + (red - luminance) * saturationFactor);
                    outGreen = channel(luminance + (green - luminance) * saturationFactor);
                    outBlue = channel(luminance + (blue - luminance) * saturationFactor);
                } else {
                    outRed = tone.rounded[redValue];
                    outGreen = tone.rounded[greenValue];
                    outBlue = tone.rounded[blueValue];
                }

                if (filterActive) {
                    if (filterSeparable) {
                        outRed = filterRed[outRed];
                        outGreen = filterGreen[outGreen];
                        outBlue = filterBlue[outBlue];
                    } else {
                        const double red = unit[outRed];
                        const double green = unit[outGreen];
                        const double blue = unit[outBlue];
                        double targetRed;
                        double targetGreen;
                        double targetBlue;
                        integerFilterTarget(preset, red, green, blue, targetRed, targetGreen,
                                            targetBlue);
                        outRed = channel(red + (targetRed - red) * intensity);
                        outGreen = channel(green + (targetGreen - green) * intensity);
                        outBlue = channel(blue + (targetBlue - blue) * intensity);
                    }
                }

                pixels[x] = QRgba64::fromRgba64(outRed, outGreen, outBlue, pixel.alpha());
            }
        }
    };

    Detail::parallelRows(height, Detail::rowWorkerCount(width, height), processRange);
    return result;
}

} // namespace

QImage apply(const QImage &source, const Parameters &parameters)
{
    if (source.isNull())
        return {};

    // Extended controls run through the new pipeline; the neutral case stays
    // on the optimised path below so its pixels remain byte-identical.
    if (Internal::hasExtendedParameters(parameters))
        return Internal::applyExtended(source, parameters);

    const double exposure = bounded(parameters.exposure, 4.0);
    const double brightness = bounded(parameters.brightness, 1.0);
    const double contrast = bounded(parameters.contrast, 1.0);
    const double saturation = bounded(parameters.saturation, 1.0);
    const double intensity = std::isfinite(parameters.filterIntensity)
        ? std::clamp(parameters.filterIntensity, 0.0, 1.0)
        : 0.0;
    const auto &presetName = parameters.filterPreset;
    if (exposure == 0.0 && brightness == 0.0 && contrast == 0.0 && saturation == 0.0
        && (presetName.isEmpty() || presetName == "none" || intensity == 0.0))
        return source;

    const Preset preset = parsePreset(presetName);
    if (isFloating(source.format()))
        return applyFloating(source, exposure, brightness, contrast, saturation, preset, intensity);

    const double exposureFactor = std::exp2(exposure);
    const double contrastFactor = 1.0 + contrast;
    const double saturationFactor = 1.0 + saturation;
    return applyInteger(source, exposureFactor, contrastFactor, brightness, saturationFactor,
                        saturation != 0.0, preset, intensity);
}

} // namespace NekoPic::Adjustments
