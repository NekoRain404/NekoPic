#include "colorpipeline_internal.h"

#include "rowparallel.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace NekoPic::Adjustments::Internal {

// ---------------------------------------------------------------------------
// Filter presets: kept numerically identical to the legacy fast path.
// ---------------------------------------------------------------------------

Preset parsePreset(const QString& preset)
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

bool isActivePreset(Preset preset) { return preset != Preset::None && preset != Preset::Unknown; }

namespace {

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
    quint32 value =
        static_cast<quint32>(x) * 0x9e3779b1u ^ static_cast<quint32>(y) * 0x85ebca77u ^ 0x27d4eb2fu;
    value ^= value >> 15;
    value *= 0x2c1b3c6du;
    value ^= value >> 12;
    value *= 0x297a2d39u;
    value ^= value >> 15;
    return value;
}

// Box blur of the working image's luminance, edge-clamped. `output` receives
// the horizontal pass and then the final result; `scratch` is reused between
// calls. O(pixels), independent of the radius.
void boxBlurLuminance(const QImage& work, std::vector<float>& output, std::vector<float>& scratch,
                      int radius)
{
    const int width = work.width();
    const int height = work.height();
    const qsizetype stride = work.bytesPerLine();
    const auto* base = work.constBits();
    const int diameter = radius * 2 + 1;
    const auto size = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);

    output.resize(size);
    scratch.resize(size);

    const int workers = Detail::rowWorkerCount(width, height);
    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            const auto* pixels = reinterpret_cast<const QRgba64*>(base + y * stride);
            const auto luminanceAt = [&](int x) {
                const QRgba64 pixel = pixels[std::clamp(x, 0, width - 1)];
                return luma(pixel.red() / 65535.0, pixel.green() / 65535.0, pixel.blue() / 65535.0);
            };
            double sum = 0.0;
            for (int offset = -radius; offset <= radius; ++offset)
                sum += luminanceAt(offset);
            float* row = output.data() + static_cast<std::size_t>(y) * width;
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
            scratch[static_cast<std::size_t>(y) * width + x] = static_cast<float>(sum / diameter);
            const int add = std::clamp(y + radius + 1, 0, height - 1);
            const int remove = std::clamp(y - radius, 0, height - 1);
            sum += output[static_cast<std::size_t>(add) * width + x] -
                   output[static_cast<std::size_t>(remove) * width + x];
        }
    }

    output.swap(scratch);
}

} // namespace

// ---------------------------------------------------------------------------
// Stage 7: detail (neighbourhood)
// ---------------------------------------------------------------------------

void applyDetailStages(QImage& work, const StageConfig& config, int workers)
{
    const Parameters& p = config.parameters;
    const int width = work.width();
    const int height = work.height();
    const qsizetype stride = work.bytesPerLine();
    auto* base = work.bits();

    std::vector<float> blurSmall;
    std::vector<float> blurLarge;
    std::vector<float> blurScratch;
    const int minimumDimension = std::min(width, height);
    if (config.needSmallBlur) {
        const int radius = std::clamp(minimumDimension / 500, 1, 3);
        boxBlurLuminance(work, blurSmall, blurScratch, radius);
    }
    if (config.needLargeBlur) {
        const int radius = std::clamp(minimumDimension / 50, 4, 64);
        boxBlurLuminance(work, blurLarge, blurScratch, radius);
    }

    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto* pixels = reinterpret_cast<QRgba64*>(base + y * stride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel = pixels[x];
                double red = pixel.red() / 65535.0;
                double green = pixel.green() / 65535.0;
                double blue = pixel.blue() / 65535.0;
                const auto offset = static_cast<std::size_t>(y) * width + x;
                const double originalLevel = luma(red, green, blue);

                if (config.textureActive) {
                    const double detail = originalLevel - blurSmall[offset];
                    const double amount = p.texture * detail * 0.8;
                    red += amount;
                    green += amount;
                    blue += amount;
                }
                if (config.clarityActive) {
                    const double detail = originalLevel - blurLarge[offset];
                    const double amount = p.clarity * detail;
                    red += amount;
                    green += amount;
                    blue += amount;
                }
                if (config.dehazeActive) {
                    red = (red - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                    green = (green - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                    blue = (blue - 0.5) * (1.0 + p.dehaze * 0.8) + 0.5;
                    const double level = luma(red, green, blue);
                    const double factor = 1.0 + p.dehaze * 0.4;
                    red = level + (red - level) * factor;
                    green = level + (green - level) * factor;
                    blue = level + (blue - level) * factor;
                }
                if (config.sharpenActive) {
                    const double detail = originalLevel - blurSmall[offset];
                    const double amount = p.sharpen * detail * 1.5;
                    red += amount;
                    green += amount;
                    blue += amount;
                }
                if (config.luminanceNoiseActive) {
                    const double level = luma(red, green, blue);
                    const double target = level + (blurSmall[offset] - level) * (p.noise * 0.8);
                    const double amount = target - level;
                    red += amount;
                    green += amount;
                    blue += amount;
                }

                pixels[x] = QRgba64::fromRgba64(toChannel(red), toChannel(green), toChannel(blue),
                                                pixel.alpha());
            }
        }
    });
}

// Colour noise reduction runs on a private copy so the read-only source
// neighbourhood and the written pixels never race across worker threads.
void applyColorNoiseStage(QImage& work, const StageConfig& config, int workers)
{
    const Parameters& p = config.parameters;
    const int width = work.width();
    const int height = work.height();
    const QImage before = work; // implicitly shared with `work`
    QImage reduced = work.copy();
    const qsizetype beforeStride = before.bytesPerLine();
    const auto* beforeBase = before.constBits();
    const qsizetype reducedStride = reduced.bytesPerLine();
    auto* reducedBase = reduced.bits();
    const double blend = p.colorNoise * 0.8;
    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto* destination = reinterpret_cast<QRgba64*>(reducedBase + y * reducedStride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel =
                    reinterpret_cast<const QRgba64*>(beforeBase + y * beforeStride)[x];
                const int x0 = std::max(0, x - 1);
                const int x1 = std::min(width - 1, x + 1);
                const int y0 = std::max(0, y - 1);
                const int y1 = std::min(height - 1, y + 1);
                double red = 0.0;
                double green = 0.0;
                double blue = 0.0;
                int count = 0;
                for (int yy = y0; yy <= y1; ++yy) {
                    const auto* row =
                        reinterpret_cast<const QRgba64*>(beforeBase + yy * beforeStride);
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
                    toChannel(sourceBlue + (blue * inverse - sourceBlue) * blend), pixel.alpha());
            }
        }
    });
    work = reduced;
}

// ---------------------------------------------------------------------------
// Stages 8-9: effects, then the existing filter preset
// ---------------------------------------------------------------------------

void applyEffectStages(QImage& work, const StageConfig& config, int workers)
{
    const Parameters& p = config.parameters;
    const int width = work.width();
    const int height = work.height();
    auto* base = work.bits();
    const qsizetype stride = work.bytesPerLine();
    const double halfWidth = width * 0.5;
    const double halfHeight = height * 0.5;
    const double vignetteInner = config.vignetteInner;
    const Preset preset = config.preset;
    const bool filterActive = config.filterActive;

    Detail::parallelRows(height, workers, [&](int begin, int end) {
        for (int y = begin; y < end; ++y) {
            auto* pixels = reinterpret_cast<QRgba64*>(base + y * stride);
            for (int x = 0; x < width; ++x) {
                const QRgba64 pixel = pixels[x];
                double red = pixel.red() / 65535.0;
                double green = pixel.green() / 65535.0;
                double blue = pixel.blue() / 65535.0;

                if (config.vignetteActive) {
                    const double nx = (x + 0.5 - halfWidth) / halfWidth;
                    const double ny = (y + 0.5 - halfHeight) / halfHeight;
                    const double distance = std::sqrt((nx * nx + ny * ny) * 0.5);
                    const double mask = smoothstep(vignetteInner, 1.0, distance);
                    const double factor = 1.0 + p.vignette * mask;
                    red *= factor;
                    green *= factor;
                    blue *= factor;
                }
                if (config.grainActive) {
                    const quint32 hash = grainHash(x, y);
                    const double noise = double(hash) * (2.0 / 4294967295.0) - 1.0;
                    const double amount = noise * p.grain * 0.12;
                    red += amount;
                    green += amount;
                    blue += amount;
                }
                if (config.fadeActive) {
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

                pixels[x] = QRgba64::fromRgba64(toChannel(red), toChannel(green), toChannel(blue),
                                                pixel.alpha());
            }
        }
    });
}

} // namespace NekoPic::Adjustments::Internal
