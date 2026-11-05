#include "colorpipeline_internal.h"

#include "rowparallel.h"

#include <QColorSpace>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>

namespace NekoPic::Adjustments::Internal {

namespace {

bool isFloatingFormat(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4 && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

// Floating formats carry alpha as the fourth 16-bit half or 32-bit float
// element. Copy it back byte-for-byte so extended processing never quantizes
// or otherwise disturbs the alpha payload.
void restoreFloatingAlpha(QImage& result, const QImage& source)
{
    if (result.format() != source.format() || result.size() != source.size())
        return;
    const int elementBytes = source.depth() / 32; // 2 for half, 4 for float
    if (elementBytes <= 0)
        return;
    const qsizetype resultStride = result.bytesPerLine();
    const qsizetype sourceStride = source.bytesPerLine();
    uchar* resultBase = result.bits();
    const uchar* sourceBase = source.constBits();
    for (int y = 0; y < result.height(); ++y) {
        uchar* destination = resultBase + y * resultStride;
        const uchar* origin = sourceBase + y * sourceStride;
        for (int x = 0; x < result.width(); ++x) {
            std::memcpy(destination + (x * 4 + 3) * elementBytes,
                        origin + (x * 4 + 3) * elementBytes,
                        static_cast<std::size_t>(elementBytes));
        }
    }
}

// Evaluates every activity flag once per image. The arithmetic that used to
// live inline in applyExtended() is unchanged; only its lifetime moved.
StageConfig makeStageConfig(const Parameters& input)
{
    StageConfig config;
    config.parameters = sanitized(input);
    const Parameters& p = config.parameters;

    config.whiteBalanceActive = p.temperature != 0.0 || p.tint != 0.0;
    config.gainRed = 1.0 + 0.30 * p.temperature + 0.10 * p.tint;
    config.gainGreen = 1.0 - 0.20 * p.tint;
    config.gainBlue = 1.0 - 0.30 * p.temperature + 0.10 * p.tint;

    config.toneActive = p.exposure != 0.0 || p.brightness != 0.0 || p.contrast != 0.0;
    config.exposureFactor = std::exp2(p.exposure);
    config.contrastFactor = 1.0 + p.contrast;

    config.tonalAdjustActive =
        p.highlights != 0.0 || p.shadows != 0.0 || p.whites != 0.0 || p.blacks != 0.0;
    config.saturationActive = p.saturation != 0.0;
    config.vibranceActive = p.vibrance != 0.0;

    for (int channel = 0; channel < HslChannelCount; ++channel) {
        config.hslActive[channel] = p.hsl[channel].hue != 0.0 || p.hsl[channel].saturation != 0.0 ||
                                    p.hsl[channel].luminance != 0.0;
        config.anyHsl = config.anyHsl || config.hslActive[channel];
    }

    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        config.curveActive[channel] = !isLinearCurve(p.curves[channel]);
        config.anyCurve = config.anyCurve || config.curveActive[channel];
    }

    for (int zone = 0; zone < GradeZoneCount; ++zone) {
        config.gradeZoneActive[zone] =
            p.grade[zone].saturation != 0.0 || p.grade[zone].luminance != 0.0;
        config.anyGrade = config.anyGrade || config.gradeZoneActive[zone];
    }
    config.gradePivot = 0.5 - 0.25 * p.gradeBalance;
    const double gradeSigma = 0.20 + 0.20 * p.gradeBlending;
    config.gradeInv = 1.0 / (2.0 * gradeSigma * gradeSigma);

    config.textureActive = p.texture != 0.0;
    config.clarityActive = p.clarity != 0.0;
    config.dehazeActive = p.dehaze != 0.0;
    config.sharpenActive = p.sharpen != 0.0;
    config.luminanceNoiseActive = p.noise != 0.0;
    config.colorNoiseActive = p.colorNoise != 0.0;
    config.needSmallBlur =
        config.textureActive || config.sharpenActive || config.luminanceNoiseActive;
    config.needLargeBlur = config.clarityActive;
    config.anyDetail = config.textureActive || config.clarityActive || config.dehazeActive ||
                       config.sharpenActive || config.luminanceNoiseActive;

    config.vignetteActive = p.vignette != 0.0;
    config.grainActive = p.grain != 0.0;
    config.fadeActive = p.fade != 0.0;
    config.preset = parsePreset(p.filterPreset);
    config.filterActive = p.filterIntensity > 0.0 && isActivePreset(config.preset);
    config.anyEffect =
        config.vignetteActive || config.grainActive || config.fadeActive || config.filterActive;
    config.vignetteInner = 0.15 + 0.55 * (1.0 - p.feather);

    config.anyTone = config.whiteBalanceActive || config.toneActive || config.tonalAdjustActive ||
                     config.saturationActive || config.vibranceActive || config.anyHsl;
    return config;
}

} // namespace

Parameters sanitized(const Parameters& input)
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

    for (auto& channel : output.hsl) {
        channel.hue = bounded(channel.hue, 1.0);
        channel.saturation = bounded(channel.saturation, 1.0);
        channel.luminance = bounded(channel.luminance, 1.0);
    }
    for (auto& curve : output.curves) {
        for (int point = 0; point < CurvePointCount; ++point) {
            curve.points[point] =
                std::isfinite(curve.points[point]) ? clamp01(curve.points[point]) : point * 0.25;
        }
    }
    for (auto& zone : output.grade) {
        zone.hue = std::isfinite(zone.hue) ? normalizeHue(zone.hue) : 0.0;
        zone.saturation =
            std::isfinite(zone.saturation) ? std::clamp(zone.saturation, 0.0, 1.0) : 0.0;
        zone.luminance = bounded(zone.luminance, 1.0);
    }
    output.gradeBlending =
        std::isfinite(input.gradeBlending) ? std::clamp(input.gradeBlending, 0.0, 1.0) : 0.5;
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

    output.filterIntensity =
        std::isfinite(input.filterIntensity) ? std::clamp(input.filterIntensity, 0.0, 1.0) : 0.0;
    return output;
}

// ---------------------------------------------------------------------------
// Dispatch helper
// ---------------------------------------------------------------------------

bool hasExtendedParameters(const Parameters& parameters)
{
    const auto active = [](double value) { return std::isfinite(value) && value != 0.0; };
    if (active(parameters.highlights) || active(parameters.shadows) || active(parameters.whites) ||
        active(parameters.blacks) || active(parameters.temperature) || active(parameters.tint) ||
        active(parameters.vibrance) || active(parameters.fade))
        return true;

    for (const auto& channel : parameters.hsl) {
        if (active(channel.hue) || active(channel.saturation) || active(channel.luminance))
            return true;
    }
    for (const auto& curve : parameters.curves) {
        if (!isLinearCurve(curve))
            return true;
    }
    for (const auto& zone : parameters.grade) {
        if (active(zone.saturation) || active(zone.luminance))
            return true;
    }
    if (active(parameters.texture) || active(parameters.clarity) || active(parameters.dehaze) ||
        active(parameters.sharpen) || active(parameters.noise) || active(parameters.colorNoise) ||
        active(parameters.vignette) || active(parameters.grain))
        return true;
    // Feather, grade blending/balance and grade hue alone cannot change
    // pixels, so they deliberately stay on the neutral fast path.
    return false;
}

QImage applyExtended(const QImage& source, const Parameters& parameters)
{
    const StageConfig config = makeStageConfig(parameters);
    const int width = source.width();
    const int height = source.height();
    if (width <= 0 || height <= 0)
        return {};

    QImage work = source.convertToFormat(QImage::Format_RGBA64);
    if (work.isNull())
        return {};

    const qsizetype stride = work.bytesPerLine();
    auto* base = work.bits();
    const int workers = Detail::rowWorkerCount(width, height);

    // --- Stages 1-6: one fused per-pixel pass ----------------------------
    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto* pixels = reinterpret_cast<QRgba64*>(base + y * stride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel = pixels[x];
                Rgb color{pixel.red() / 65535.0, pixel.green() / 65535.0, pixel.blue() / 65535.0};

                if (config.anyTone)
                    applyToneStages(color, config);
                if (config.anyCurve)
                    applyCurveStages(color, config);
                else
                    clampColor(color); // original unconditional post-curve clamp
                if (config.anyGrade)
                    applyGradeStage(color, config);
                else
                    clampColor(color); // original unconditional post-grade clamp

                pixels[x] = QRgba64::fromRgba64(toChannel(color.red), toChannel(color.green),
                                                toChannel(color.blue), pixel.alpha());
            }
        }
    });

    // --- Stage 7: detail (neighbourhood) --------------------------------
    if (config.anyDetail)
        applyDetailStages(work, config, workers);
    if (config.colorNoiseActive)
        applyColorNoiseStage(work, config, workers);

    // --- Stages 8-9: effects, then the existing filter preset -----------
    if (config.anyEffect)
        applyEffectStages(work, config, workers);

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

} // namespace NekoPic::Adjustments::Internal
