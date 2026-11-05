#include "adjustments.h"
#include "colorpipeline.h"
#include "core/filterpresets.h"

#include <QColorSpace>
#include <QSet>
#include <QtTest>
#include <qfloat16.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

using namespace NekoPic::Adjustments;

namespace {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

QImage makeImage(int width, int height, QImage::Format format, quint32 seed)
{
    QImage image(width, height, format);
    if (image.isNull())
        return image;
    quint32 state = seed;
    const auto next = [&state] {
        state = state * 1664525u + 1013904223u;
        return state;
    };
    const bool floating = format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
    const bool half = format == QImage::Format_RGBX16FPx4
        || format == QImage::Format_RGBA16FPx4
        || format == QImage::Format_RGBA16FPx4_Premultiplied;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const quint32 a = next();
            const quint32 b = next();
            const quint32 c = next();
            const quint32 d = next();
            if (floating) {
                float channels[4]{
                    float((a & 0xffff) / 65535.0),
                    float((b & 0xffff) / 65535.0),
                    float((c & 0xffff) / 65535.0),
                    float((d & 0xffff) / 65535.0),
                };
                if (half) {
                    auto *pixel = reinterpret_cast<qfloat16 *>(image.scanLine(y)) + x * 4;
                    for (int i = 0; i < 4; ++i)
                        pixel[i] = qfloat16(channels[i]);
                } else {
                    auto *pixel = reinterpret_cast<float *>(image.scanLine(y)) + x * 4;
                    for (int i = 0; i < 4; ++i)
                        pixel[i] = channels[i];
                }
            } else if (format == QImage::Format_RGBA8888) {
                auto *pixel = image.scanLine(y) + x * 4;
                pixel[0] = a & 0xff;
                pixel[1] = (b >> 8) & 0xff;
                pixel[2] = (c >> 16) & 0xff;
                pixel[3] = (d >> 8) & 0xff;
            } else {
                auto *pixel = reinterpret_cast<QRgba64 *>(image.scanLine(y)) + x;
                *pixel = QRgba64::fromRgba64(a & 0xffff, (b >> 3) & 0xffff,
                                             (c >> 7) & 0xffff, d & 0xffff);
            }
        }
    }
    return image;
}

bool sameBytes(const QImage &actual, const QImage &expected)
{
    if (actual.format() != expected.format() || actual.size() != expected.size())
        return false;
    if (actual.colorSpace() != expected.colorSpace())
        return false;
    if (actual.dotsPerMeterX() != expected.dotsPerMeterX()
        || actual.dotsPerMeterY() != expected.dotsPerMeterY())
        return false;
    const qsizetype rowBytes = qsizetype(actual.width()) * actual.depth() / 8;
    if (actual.bytesPerLine() < rowBytes)
        return false;
    for (int y = 0; y < actual.height(); ++y) {
        if (std::memcmp(actual.constScanLine(y), expected.constScanLine(y), rowBytes) != 0)
            return false;
    }
    return true;
}

QRgba64 rgba64At(const QImage &image, int x, int y = 0)
{
    const QImage converted = image.format() == QImage::Format_RGBA64
        ? image
        : image.convertToFormat(QImage::Format_RGBA64);
    return reinterpret_cast<const QRgba64 *>(converted.constScanLine(y))[x];
}

int channelAt(const QImage &image, int x, int channel, int y = 0)
{
    const QRgba64 pixel = rgba64At(image, x, y);
    switch (channel) {
    case 0:
        return pixel.red();
    case 1:
        return pixel.green();
    case 2:
        return pixel.blue();
    default:
        return pixel.alpha();
    }
}

int deltaAt(const QImage &before, const QImage &after, int x, int channel, int y = 0)
{
    return std::abs(channelAt(after, x, channel, y) - channelAt(before, x, channel, y));
}

int patchDelta(const QImage &before, const QImage &after, int x, int y = 0)
{
    return std::max({deltaAt(before, after, x, 0, y), deltaAt(before, after, x, 1, y),
                     deltaAt(before, after, x, 2, y)});
}

bool closeTo(double actual, double expected, double tolerance = 1e-9)
{
    return std::abs(actual - expected) <= tolerance;
}

int chromaAt(const QImage &image, int x, int y = 0)
{
    const QRgba64 pixel = rgba64At(image, x, y);
    const int maximum = std::max({pixel.red(), pixel.green(), pixel.blue()});
    const int minimum = std::min({pixel.red(), pixel.green(), pixel.blue()});
    return maximum - minimum;
}

int maximumDelta(const QImage &before, const QImage &after)
{
    const QImage a = before.convertToFormat(QImage::Format_RGBA64);
    const QImage b = after.convertToFormat(QImage::Format_RGBA64);
    int worst = 0;
    for (int y = 0; y < a.height(); ++y) {
        const auto *pa = reinterpret_cast<const QRgba64 *>(a.constScanLine(y));
        const auto *pb = reinterpret_cast<const QRgba64 *>(b.constScanLine(y));
        for (int x = 0; x < a.width(); ++x) {
            worst = std::max({worst, std::abs(int(pa[x].red()) - int(pb[x].red())),
                              std::abs(int(pa[x].green()) - int(pb[x].green())),
                              std::abs(int(pa[x].blue()) - int(pb[x].blue()))});
        }
    }
    return worst;
}

// Eight labelled patches:
//   0 near-black, 1 dark grey, 2 mid grey, 3 bright grey,
//   4 saturated red, 5 saturated blue, 6 low-saturation colour,
//   7 saturated green.
QImage makeBands()
{
    QImage image(8, 1, QImage::Format_RGBA64);
    const struct {
        double red;
        double green;
        double blue;
    } patches[]{{0.02, 0.02, 0.02}, {0.15, 0.15, 0.15}, {0.50, 0.50, 0.50},
                {0.90, 0.90, 0.90}, {0.90, 0.10, 0.10}, {0.10, 0.10, 0.90},
                {0.60, 0.55, 0.50}, {0.10, 0.80, 0.10}};
    auto *pixels = reinterpret_cast<QRgba64 *>(image.scanLine(0));
    for (int x = 0; x < 8; ++x) {
        pixels[x] = QRgba64::fromRgba64(
            static_cast<quint16>(std::lround(patches[x].red * 65535.0)),
            static_cast<quint16>(std::lround(patches[x].green * 65535.0)),
            static_cast<quint16>(std::lround(patches[x].blue * 65535.0)), 0xabcd);
    }
    return image;
}

QImage makeDetailImage(int width, int height)
{
    QImage image(width, height, QImage::Format_RGBA64);
    for (int y = 0; y < height; ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < width; ++x) {
            const double checker = ((x / 2 + y / 2) % 2) ? 0.75 : 0.25;
            const double gradient = double(x) / std::max(1, width - 1);
            pixels[x] = QRgba64::fromRgba64(
                static_cast<quint16>(std::lround(
                    std::clamp(0.5 * checker + 0.5 * gradient, 0.0, 1.0) * 65535.0)),
                static_cast<quint16>(std::lround(
                    std::clamp(0.6 * checker + 0.4 * (1.0 - gradient), 0.0, 1.0)
                    * 65535.0)),
                static_cast<quint16>(
                    std::lround(std::clamp(1.0 - checker, 0.0, 1.0) * 65535.0)),
                0xffff);
        }
    }
    return image;
}

QImage makeNoisyImage(int width, int height, quint32 seed)
{
    QImage image(width, height, QImage::Format_RGBA64);
    quint32 state = seed;
    for (int y = 0; y < height; ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < width; ++x) {
            state = state * 1664525u + 1013904223u;
            const quint16 red = static_cast<quint16>((state >> 16) & 0xffff);
            state = state * 1664525u + 1013904223u;
            const quint16 green = static_cast<quint16>((state >> 16) & 0xffff);
            state = state * 1664525u + 1013904223u;
            const quint16 blue = static_cast<quint16>((state >> 16) & 0xffff);
            pixels[x] = QRgba64::fromRgba64(red, green, blue, 0xffff);
        }
    }
    return image;
}

QImage makeFlat(int width, int height, double value)
{
    QImage image(width, height, QImage::Format_RGBA64);
    const quint16 level = static_cast<quint16>(std::lround(value * 65535.0));
    const QRgba64 pixel = QRgba64::fromRgba64(level, level, level, 0xffff);
    for (int y = 0; y < height; ++y) {
        auto *row = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < width; ++x)
            row[x] = pixel;
    }
    return image;
}

Parameters wideExtendedParameters()
{
    Parameters p;
    setParameter(p, "exposure", 30.0);
    setParameter(p, "temperature", 40.0);
    setParameter(p, "highlights", -20.0);
    setParameter(p, "saturation", 20.0);
    setParameter(p, "vibrance", 30.0);
    setParameter(p, "hsl.red.hue", 40.0);
    setParameter(p, "curve.RGB.1", 20.0);
    setParameter(p, "curve.RGB.3", 80.0);
    setParameter(p, "grade.shadows.saturation", 60.0);
    setParameter(p, "texture", 40.0);
    setParameter(p, "clarity", 30.0);
    setParameter(p, "dehaze", 20.0);
    setParameter(p, "sharpen", 30.0);
    setParameter(p, "noise", 20.0);
    setParameter(p, "colorNoise", 20.0);
    setParameter(p, "vignette", -40.0);
    setParameter(p, "feather", 30.0);
    setParameter(p, "grain", 20.0);
    setParameter(p, "fade", 10.0);
    return p;
}

} // namespace

class ColorPipelineTest : public QObject {
    Q_OBJECT
private slots:
    void keysRoundTrip();
    void unknownKeysRejected();
    void parameterClamping();
    void gpuPreviewKeys();
    void gpuPreviewSupport();
    void neutralExtendedParametersMatchBaseline_data();
    void neutralExtendedParametersMatchBaseline();
    void inactiveExtendedParametersStayNeutral();
    void whiteBalanceChangesColour();
    void tonalMasksTargetRanges();
    void vibranceTargetsLowSaturation();
    void hslChannelsAreTargeted();
    void curvesAreIdentityAndTargeted();
    void gradingTargetsTonalZones();
    void fadeLiftsBlacks();
    void detailEffectsChangePixels();
    void detailEffectsLeaveFlatImagesStable();
    void noiseAndGrainAreDeterministic();
    void parallelDeterminism();
    void vignetteAndFeatherTargetEdges();
    void preservesAlphaDepthColourSpaceAndDpi();
    void integerEightBitPromotesAlphaExactly();
    void floatingPreservesFormatAndAlpha_data();
    void floatingPreservesFormatAndAlpha();
    void extremeValuesDoNotCrash();
    void filterPresetsChangePixelsAndScaleWithIntensity();
    void filterPresetsMatchLegacyPipeline();
};

void ColorPipelineTest::keysRoundTrip()
{
    const QStringList keys = parameterKeys();
    QCOMPARE(keys.size(), 76);
    QSet<QString> unique;
    for (const auto &key : keys)
        unique.insert(key);
    QCOMPARE(unique.size(), keys.size());

    Parameters parameters;
    for (const auto &key : keys) {
        QVERIFY2(isParameterKey(key), qPrintable(key));
        double value = 37.0;
        if (key.startsWith(QStringLiteral("grade."))
            && key.endsWith(QStringLiteral(".hue")))
            value = 123.0;
        if (key == QStringLiteral("exposure"))
            value = -37.0;
        QVERIFY2(setParameter(parameters, key, value), qPrintable(key));
        QVERIFY2(std::abs(parameterValue(parameters, key) - value) < 1e-9,
                 qPrintable(QStringLiteral("%1 -> %2")
                                .arg(key)
                                .arg(parameterValue(parameters, key))));
    }

    const QVariantMap ui = toUiValues(parameters);
    QCOMPARE(ui.size(), keys.size());
    for (const auto &key : keys) {
        QVERIFY2(ui.contains(key), qPrintable(key));
        QVERIFY2(std::abs(ui.value(key).toDouble() - parameterValue(parameters, key)) < 1e-9,
                 qPrintable(key));
    }

    // Stored-unit sanity for a few representative conversions.
    QVERIFY(closeTo(parameterValue(parameters, QStringLiteral("exposure")), -37.0));
    Parameters fresh;
    QVERIFY(setParameter(fresh, QStringLiteral("exposure"), 50.0));
    QVERIFY(closeTo(fresh.exposure, 2.0, 1e-12));
    QVERIFY(setParameter(fresh, QStringLiteral("curve.RGB.2"), 75.0));
    QVERIFY(closeTo(fresh.curves[0].points[2], 0.75, 1e-12));
    QVERIFY(setParameter(fresh, QStringLiteral("hsl.green.saturation"), -25.0));
    QVERIFY(closeTo(fresh.hsl[3].saturation, -0.25, 1e-12));
    QVERIFY(setParameter(fresh, QStringLiteral("grade.shadows.hue"), 220.0));
    QVERIFY(closeTo(fresh.grade[0].hue, 220.0, 1e-12));
}

void ColorPipelineTest::unknownKeysRejected()
{
    Parameters parameters;
    QVERIFY(!isParameterKey(QStringLiteral("nope")));
    QVERIFY(!isParameterKey(QStringLiteral("hsl.red.sharpness")));
    QVERIFY(!isParameterKey(QStringLiteral("curve.C.0")));
    QVERIFY(!setParameter(parameters, QStringLiteral("nope"), 10.0));
    QVERIFY(std::isnan(parameterValue(parameters, QStringLiteral("nope"))));
}

void ColorPipelineTest::parameterClamping()
{
    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("exposure"), 1000.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("exposure")), 100.0));
    QVERIFY(closeTo(p.exposure, 4.0, 1e-12));
    QVERIFY(setParameter(p, QStringLiteral("exposure"), -1000.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("exposure")), -100.0));
    QVERIFY(closeTo(p.exposure, -4.0, 1e-12));

    QVERIFY(setParameter(p, QStringLiteral("temperature"), 500.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("temperature")), 100.0));
    QVERIFY(closeTo(p.temperature, 1.0, 1e-12));

    QVERIFY(setParameter(p, QStringLiteral("fade"), -50.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("fade")), 0.0));
    QVERIFY(setParameter(p, QStringLiteral("fade"), 500.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("fade")), 100.0));
    QVERIFY(closeTo(p.fade, 1.0, 1e-12));

    QVERIFY(setParameter(p, QStringLiteral("curve.RGB.0"), -20.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("curve.RGB.0")), 0.0));
    QVERIFY(closeTo(p.curves[0].points[0], 0.0, 1e-12));

    QVERIFY(setParameter(p, QStringLiteral("grade.shadows.hue"), 400.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("grade.shadows.hue")), 360.0));
    QVERIFY(closeTo(p.grade[0].hue, 360.0, 1e-12));

    QVERIFY(setParameter(p, QStringLiteral("vignette"), -500.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("vignette")), -100.0));
    QVERIFY(setParameter(p, QStringLiteral("feather"), 500.0));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("feather")), 100.0));

    QVERIFY(setParameter(p, QStringLiteral("exposure"),
                         std::numeric_limits<double>::quiet_NaN()));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("exposure")), 0.0));
    QVERIFY(setParameter(p, QStringLiteral("grain"),
                         std::numeric_limits<double>::infinity()));
    QVERIFY(closeTo(parameterValue(p, QStringLiteral("grain")), 0.0));
}

void ColorPipelineTest::gpuPreviewKeys()
{
    for (const char *key : {"exposure", "brightness", "contrast", "saturation",
                            "highlights", "shadows", "whites", "blacks",
                            "temperature", "tint", "vibrance"}) {
        QVERIFY2(isGpuPreviewKey(QString::fromLatin1(key)), key);
    }
    for (const char *key : {"fade", "hsl.red.hue", "curve.RGB.0",
                            "grade.shadows.hue", "grade.shadows.saturation",
                            "grade.shadows.luminance", "texture", "clarity",
                            "dehaze", "sharpen", "noise", "colorNoise",
                            "vignette", "feather", "grain", "filter",
                            "filter-intensity", "not-a-key"}) {
        QVERIFY2(!isGpuPreviewKey(QString::fromLatin1(key)), key);
    }
}

void ColorPipelineTest::gpuPreviewSupport()
{
    Parameters parameters;
    QVERIFY(isGpuPreviewSupported(parameters));

    // Every key the shader implements is accepted simultaneously.
    parameters.exposure = 1.0;
    parameters.brightness = 0.2;
    parameters.contrast = -0.3;
    parameters.saturation = 0.4;
    parameters.highlights = 0.5;
    parameters.shadows = -0.6;
    parameters.whites = 0.3;
    parameters.blacks = -0.2;
    parameters.temperature = 0.7;
    parameters.tint = -0.4;
    parameters.vibrance = 0.8;
    QVERIFY(isGpuPreviewSupported(parameters));

    // Each unsupported stage forces the CPU path.
    parameters = {};
    parameters.fade = 0.5;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.hsl[0].hue = 0.1;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.curves[1].points[2] = 0.6;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.grade[0].saturation = 0.2;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.grade[2].luminance = 0.2;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.texture = 0.1;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.vignette = 0.2;
    QVERIFY(!isGpuPreviewSupported(parameters));
    parameters = {};
    parameters.filterPreset = QStringLiteral("mono");
    parameters.filterIntensity = 1.0;
    QVERIFY(!isGpuPreviewSupported(parameters));

    // Neutral values that cannot change pixels are allowed: linear curves,
    // grade hue/blending/balance without saturation/luminance, and feather.
    parameters = {};
    parameters.grade[0].hue = 200.0;
    parameters.gradeBlending = 0.9;
    parameters.gradeBalance = 0.5;
    parameters.feather = 0.2;
    QVERIFY(isGpuPreviewSupported(parameters));
    // "none" plus any intensity is neutral.
    parameters = {};
    parameters.filterPreset = QStringLiteral("none");
    parameters.filterIntensity = 1.0;
    QVERIFY(isGpuPreviewSupported(parameters));
}

void ColorPipelineTest::neutralExtendedParametersMatchBaseline_data()
{
    QTest::addColumn<int>("format");
    QTest::newRow("rgba8888") << int(QImage::Format_RGBA8888);
    QTest::newRow("rgba64") << int(QImage::Format_RGBA64);
    QTest::newRow("rgba32f") << int(QImage::Format_RGBA32FPx4);
    QTest::newRow("rgba16f-premultiplied")
        << int(QImage::Format_RGBA16FPx4_Premultiplied);
}

void ColorPipelineTest::neutralExtendedParametersMatchBaseline()
{
    QFETCH(int, format);
    QImage source = makeImage(37, 23, QImage::Format(format), 0x51ed270bu);
    source.setColorSpace(QColorSpace::DisplayP3);
    source.setDotsPerMeterX(2835);
    source.setDotsPerMeterY(2836);

    std::vector<Parameters> basics;
    basics.push_back(Parameters{});
    {
        Parameters p;
        p.exposure = 1.2;
        p.contrast = 0.35;
        basics.push_back(p);
    }
    {
        Parameters p;
        p.saturation = -0.6;
        basics.push_back(p);
    }
    {
        Parameters p;
        p.filterPreset = QStringLiteral("warm");
        p.filterIntensity = 0.7;
        basics.push_back(p);
    }
    {
        Parameters p;
        p.exposure = -0.75;
        p.brightness = 0.2;
        p.filterPreset = QStringLiteral("vintage");
        p.filterIntensity = 0.4;
        basics.push_back(p);
    }

    for (const auto &basic : basics) {
        const QImage baseline = apply(source, basic);
        Parameters neutral = basic;
        // Non-default values that are nevertheless pixel-neutral.
        neutral.feather = 0.73;
        neutral.gradeBlending = 0.91;
        neutral.gradeBalance = -0.67;
        neutral.grade[0].hue = 123.0;
        neutral.grade[2].hue = 300.0;
        const QImage actual = apply(source, neutral);
        QVERIFY2(sameBytes(actual, baseline), "neutral extended fields changed output");
    }
}

void ColorPipelineTest::inactiveExtendedParametersStayNeutral()
{
    const QImage source = makeBands();
    const QImage baseline = apply(source, Parameters{});

    Parameters p;
    // Linear curves set through the public API.
    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        static const char *const names[]{"RGB", "R", "G", "B"};
        for (int point = 0; point < CurvePointCount; ++point) {
            QVERIFY(setParameter(p, QStringLiteral("curve.%1.%2")
                                        .arg(QString::fromLatin1(names[channel]))
                                        .arg(point),
                                 point * 25.0));
        }
    }
    // Feather without a vignette, grade hue with zero saturation and grading
    // blend/balance without an active zone are all inactive.
    QVERIFY(setParameter(p, QStringLiteral("feather"), 80.0));
    QVERIFY(setParameter(p, QStringLiteral("grade.shadows.hue"), 12.0));
    QVERIFY(setParameter(p, QStringLiteral("grade.midtones.hue"), 355.0));
    QVERIFY(setParameter(p, QStringLiteral("grade.blending"), 90.0));
    QVERIFY(setParameter(p, QStringLiteral("grade.balance"), -80.0));
    QVERIFY(sameBytes(apply(source, p), baseline));
}

void ColorPipelineTest::whiteBalanceChangesColour()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});

    Parameters warm;
    QVERIFY(setParameter(warm, QStringLiteral("temperature"), 100.0));
    const QImage warmed = apply(bands, warm);
    // Mid grey becomes warmer: red rises, blue falls.
    QVERIFY(channelAt(warmed, 2, 0) > channelAt(baseline, 2, 0) + 1000);
    QVERIFY(channelAt(warmed, 2, 2) < channelAt(baseline, 2, 2) - 1000);

    Parameters cool;
    QVERIFY(setParameter(cool, QStringLiteral("temperature"), -100.0));
    const QImage cooled = apply(bands, cool);
    QVERIFY(channelAt(cooled, 2, 0) < channelAt(baseline, 2, 0));
    QVERIFY(channelAt(cooled, 2, 2) > channelAt(baseline, 2, 2));

    Parameters magenta;
    QVERIFY(setParameter(magenta, QStringLiteral("tint"), 100.0));
    const QImage tinted = apply(bands, magenta);
    QVERIFY(channelAt(tinted, 2, 1) < channelAt(baseline, 2, 1));

    Parameters greenTint;
    QVERIFY(setParameter(greenTint, QStringLiteral("tint"), -100.0));
    const QImage green = apply(bands, greenTint);
    QVERIFY(channelAt(green, 2, 1) > channelAt(baseline, 2, 1));
}

void ColorPipelineTest::tonalMasksTargetRanges()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});

    Parameters highlights;
    QVERIFY(setParameter(highlights, QStringLiteral("highlights"), -100.0));
    const QImage highlightResult = apply(bands, highlights);
    QVERIFY(deltaAt(baseline, highlightResult, 3, 0)
            > 3 * deltaAt(baseline, highlightResult, 1, 0));
    QVERIFY(channelAt(highlightResult, 3, 0) < channelAt(baseline, 3, 0));

    Parameters shadows;
    QVERIFY(setParameter(shadows, QStringLiteral("shadows"), 100.0));
    const QImage shadowResult = apply(bands, shadows);
    QVERIFY(deltaAt(baseline, shadowResult, 1, 0)
            > 3 * deltaAt(baseline, shadowResult, 3, 0));
    QVERIFY(channelAt(shadowResult, 1, 0) > channelAt(baseline, 1, 0));

    Parameters whites;
    QVERIFY(setParameter(whites, QStringLiteral("whites"), -100.0));
    const QImage whitesResult = apply(bands, whites);
    QVERIFY(deltaAt(baseline, whitesResult, 3, 0)
            > 3 * deltaAt(baseline, whitesResult, 2, 0));
    QVERIFY(channelAt(whitesResult, 3, 0) < channelAt(baseline, 3, 0));

    Parameters blacks;
    QVERIFY(setParameter(blacks, QStringLiteral("blacks"), -100.0));
    const QImage blacksResult = apply(bands, blacks);
    QVERIFY(deltaAt(baseline, blacksResult, 1, 0)
            > 3 * deltaAt(baseline, blacksResult, 2, 0));
    QVERIFY(channelAt(blacksResult, 1, 0) < channelAt(baseline, 1, 0));
}

void ColorPipelineTest::vibranceTargetsLowSaturation()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});
    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("vibrance"), 100.0));
    const QImage actual = apply(bands, p);

    const double lowRatio = double(chromaAt(actual, 6)) / std::max(1, chromaAt(baseline, 6));
    const double highRatio = double(chromaAt(actual, 4)) / std::max(1, chromaAt(baseline, 4));
    QVERIFY(lowRatio > highRatio);
    QVERIFY(channelAt(actual, 6, 0) != channelAt(baseline, 6, 0));

    // A neutral pixel has no saturation to boost.
    QVERIFY(deltaAt(baseline, actual, 2, 0) <= 1);
    QVERIFY(deltaAt(baseline, actual, 2, 1) <= 1);
    QVERIFY(deltaAt(baseline, actual, 2, 2) <= 1);
}

void ColorPipelineTest::hslChannelsAreTargeted()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});

    Parameters redHue;
    QVERIFY(setParameter(redHue, QStringLiteral("hsl.red.hue"), 100.0));
    const QImage hueResult = apply(bands, redHue);
    // A +30 degree shift turns the pure-red patch orange, raising green.
    QVERIFY(deltaAt(baseline, hueResult, 4, 1) > 3000);
    QVERIFY(deltaAt(baseline, hueResult, 5, 0) <= 2);
    QVERIFY(deltaAt(baseline, hueResult, 5, 1) <= 2);
    QVERIFY(deltaAt(baseline, hueResult, 5, 2) <= 2);

    Parameters redSaturation;
    QVERIFY(setParameter(redSaturation, QStringLiteral("hsl.red.saturation"), -100.0));
    const QImage saturationResult = apply(bands, redSaturation);
    QVERIFY(chromaAt(saturationResult, 4) < chromaAt(baseline, 4) / 2);
    QVERIFY(deltaAt(baseline, saturationResult, 5, 0) <= 2);

    Parameters blueLuminance;
    QVERIFY(setParameter(blueLuminance, QStringLiteral("hsl.blue.luminance"), 100.0));
    const QImage luminanceResult = apply(bands, blueLuminance);
    QVERIFY(channelAt(luminanceResult, 5, 2) > channelAt(baseline, 5, 2));
    QVERIFY(deltaAt(baseline, luminanceResult, 4, 0) <= 2);
}

void ColorPipelineTest::curvesAreIdentityAndTargeted()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});

    Parameters linear;
    static const char *const names[]{"RGB", "R", "G", "B"};
    for (int channel = 0; channel < CurveChannelCount; ++channel) {
        for (int point = 0; point < CurvePointCount; ++point) {
            QVERIFY(setParameter(linear, QStringLiteral("curve.%1.%2")
                                           .arg(QString::fromLatin1(names[channel]))
                                           .arg(point),
                                 point * 25.0));
        }
    }
    QVERIFY(sameBytes(apply(bands, linear), baseline));

    Parameters sCurve;
    QVERIFY(setParameter(sCurve, QStringLiteral("curve.RGB.1"), 17.0));
    QVERIFY(setParameter(sCurve, QStringLiteral("curve.RGB.3"), 83.0));
    const QImage contrastResult = apply(bands, sCurve);
    QVERIFY(channelAt(contrastResult, 1, 0) < channelAt(baseline, 1, 0));
    QVERIFY(channelAt(contrastResult, 3, 0) > channelAt(baseline, 3, 0));

    Parameters redCurve;
    QVERIFY(setParameter(redCurve, QStringLiteral("curve.R.2"), 25.0));
    const QImage redResult = apply(bands, redCurve);
    QVERIFY(channelAt(redResult, 2, 0) < channelAt(baseline, 2, 0) - 10000);
    QVERIFY(deltaAt(baseline, redResult, 2, 1) <= 1);
    QVERIFY(deltaAt(baseline, redResult, 2, 2) <= 1);
}

void ColorPipelineTest::gradingTargetsTonalZones()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});

    Parameters shadows;
    QVERIFY(setParameter(shadows, QStringLiteral("grade.shadows.hue"), 0.0));
    QVERIFY(setParameter(shadows, QStringLiteral("grade.shadows.saturation"), 100.0));
    const QImage shadowResult = apply(bands, shadows);
    const int darkDelta = patchDelta(baseline, shadowResult, 1);
    const int brightDelta = patchDelta(baseline, shadowResult, 3);
    QVERIFY(darkDelta > 1000);
    QVERIFY(darkDelta > 5 * brightDelta);
    // A red shadow tint raises red relative to blue on the dark patch.
    QVERIFY(channelAt(shadowResult, 1, 0) > channelAt(baseline, 1, 0));
    QVERIFY(channelAt(shadowResult, 1, 2) < channelAt(baseline, 1, 2));

    Parameters highlights;
    QVERIFY(setParameter(highlights, QStringLiteral("grade.highlights.hue"), 240.0));
    QVERIFY(setParameter(highlights, QStringLiteral("grade.highlights.saturation"), 100.0));
    const QImage highlightResult = apply(bands, highlights);
    const int darkHighlightDelta = patchDelta(baseline, highlightResult, 1);
    const int brightHighlightDelta = patchDelta(baseline, highlightResult, 3);
    QVERIFY(brightHighlightDelta > 1000);
    QVERIFY(brightHighlightDelta > 5 * darkHighlightDelta);
    QVERIFY(channelAt(highlightResult, 3, 2) > channelAt(baseline, 3, 2));

    Parameters midtones;
    QVERIFY(setParameter(midtones, QStringLiteral("grade.midtones.hue"), 60.0));
    QVERIFY(setParameter(midtones, QStringLiteral("grade.midtones.saturation"), 100.0));
    const QImage midtoneResult = apply(bands, midtones);
    QVERIFY(patchDelta(baseline, midtoneResult, 2) > 1000);
}

void ColorPipelineTest::fadeLiftsBlacks()
{
    const QImage bands = makeBands();
    const QImage baseline = apply(bands, Parameters{});
    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("fade"), 100.0));
    const QImage actual = apply(bands, p);
    QVERIFY(channelAt(actual, 0, 0) > channelAt(baseline, 0, 0) + 5000);
    QVERIFY(deltaAt(baseline, actual, 0, 0) > deltaAt(baseline, actual, 3, 0));
}

void ColorPipelineTest::detailEffectsChangePixels()
{
    const QImage detail = makeDetailImage(32, 24);
    const QImage noisy = makeNoisyImage(24, 16, 0x12345678u);
    const QImage baselineDetail = apply(detail, Parameters{});
    const QImage baselineNoisy = apply(noisy, Parameters{});

    struct Case {
        const char *key;
    };
    const Case cases[]{{"texture"}, {"clarity"}, {"dehaze"}, {"sharpen"}};
    for (const auto &item : cases) {
        Parameters p;
        QVERIFY(setParameter(p, QString::fromLatin1(item.key), 100.0));
        const QImage actual = apply(detail, p);
        QVERIFY2(!sameBytes(actual, baselineDetail), item.key);
        QVERIFY2(maximumDelta(baselineDetail, actual) > 100, item.key);
    }

    for (const char *key : {"noise", "colorNoise"}) {
        Parameters p;
        QVERIFY(setParameter(p, QString::fromLatin1(key), 100.0));
        const QImage actual = apply(noisy, p);
        QVERIFY2(!sameBytes(actual, baselineNoisy), key);
        QVERIFY2(maximumDelta(baselineNoisy, actual) > 100, key);
    }
}

void ColorPipelineTest::detailEffectsLeaveFlatImagesStable()
{
    const QImage flat = makeFlat(16, 16, 0.5);
    const QImage baseline = apply(flat, Parameters{});
    for (const char *key : {"texture", "clarity", "sharpen", "dehaze", "noise",
                            "colorNoise"}) {
        Parameters p;
        QVERIFY(setParameter(p, QString::fromLatin1(key), 100.0));
        const QImage actual = apply(flat, p);
        QVERIFY2(maximumDelta(baseline, actual) <= 1, key);
    }
}

void ColorPipelineTest::noiseAndGrainAreDeterministic()
{
    const QImage noisy = makeNoisyImage(24, 16, 0xabcdef01u);
    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("noise"), 80.0));
    QVERIFY(setParameter(p, QStringLiteral("colorNoise"), 80.0));
    QVERIFY(setParameter(p, QStringLiteral("grain"), 90.0));
    QVERIFY(setParameter(p, QStringLiteral("texture"), 40.0));
    const QImage first = apply(noisy, p);
    const QImage second = apply(noisy, p);
    QVERIFY(sameBytes(first, second));
    QVERIFY(maximumDelta(apply(noisy, Parameters{}), first) > 100);
}

void ColorPipelineTest::parallelDeterminism()
{
    // Above the row-parallel threshold, so this exercises chunk boundaries.
    const QImage source = makeNoisyImage(1024, 1024, 0x2545f491u);
    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("texture"), 60.0));
    QVERIFY(setParameter(p, QStringLiteral("grain"), 60.0));
    QVERIFY(setParameter(p, QStringLiteral("vignette"), -50.0));
    const QImage first = apply(source, p);
    const QImage second = apply(source, p);
    QVERIFY(sameBytes(first, second));
}

void ColorPipelineTest::vignetteAndFeatherTargetEdges()
{
    const QImage flat = makeFlat(16, 16, 0.5);
    const QImage baseline = apply(flat, Parameters{});

    Parameters p;
    QVERIFY(setParameter(p, QStringLiteral("vignette"), -100.0));
    QVERIFY(setParameter(p, QStringLiteral("feather"), 50.0));
    const QImage vignetted = apply(flat, p);
    QVERIFY(channelAt(vignetted, 0, 0) < channelAt(baseline, 0, 0) - 10000);
    QVERIFY(deltaAt(baseline, vignetted, 0, 0, 0)
            > deltaAt(baseline, vignetted, 8, 0, 8));
    // Corners are darkened more than edge midpoints, and the centre is untouched.
    QVERIFY(channelAt(vignetted, 8, 0, 8) == channelAt(baseline, 8, 0, 8));

    Parameters hard = p;
    QVERIFY(setParameter(hard, QStringLiteral("feather"), 0.0));
    Parameters soft = p;
    QVERIFY(setParameter(soft, QStringLiteral("feather"), 100.0));
    const QImage hardResult = apply(flat, hard);
    const QImage softResult = apply(flat, soft);
    QVERIFY(channelAt(hardResult, 0, 0, 8) != channelAt(softResult, 0, 0, 8));

    Parameters bright;
    QVERIFY(setParameter(bright, QStringLiteral("vignette"), 100.0));
    const QImage brightResult = apply(flat, bright);
    QVERIFY(channelAt(brightResult, 0, 0, 0) > channelAt(baseline, 0, 0, 0));
}

void ColorPipelineTest::preservesAlphaDepthColourSpaceAndDpi()
{
    QImage image(8, 4, QImage::Format_RGBA64);
    const quint16 alphas[]{0, 1, 0x7fff, 0x8000, 0xfffe, 0xffff};
    for (int y = 0; y < image.height(); ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            pixels[x] = QRgba64::fromRgba64(quint16(x * 7000), quint16(y * 15000),
                                            quint16(x * y * 997), alphas[(x + y) % 6]);
        }
    }
    image.setColorSpace(QColorSpace::DisplayP3);
    image.setDotsPerMeterX(2835);
    image.setDotsPerMeterY(2836);

    const Parameters p = wideExtendedParameters();
    const QImage result = apply(image, p);
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.dotsPerMeterX(), 2835);
    QCOMPARE(result.dotsPerMeterY(), 2836);
    for (int y = 0; y < result.height(); ++y) {
        const auto *pixels = reinterpret_cast<const QRgba64 *>(result.constScanLine(y));
        for (int x = 0; x < result.width(); ++x)
            QCOMPARE(pixels[x].alpha(), alphas[(x + y) % 6]);
    }
}

void ColorPipelineTest::integerEightBitPromotesAlphaExactly()
{
    QImage image(8, 4, QImage::Format_RGBA8888);
    const uchar alphas[]{0, 1, 64, 127, 128, 254, 255, 200};
    for (int y = 0; y < image.height(); ++y) {
        auto *row = image.scanLine(y);
        for (int x = 0; x < image.width(); ++x) {
            auto *pixel = row + x * 4;
            pixel[0] = uchar(x * 30);
            pixel[1] = uchar(y * 60);
            pixel[2] = uchar(x * y * 7);
            pixel[3] = alphas[(x + y) % 8];
        }
    }
    const QImage result = apply(image, wideExtendedParameters());
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    for (int y = 0; y < result.height(); ++y) {
        const auto *pixels = reinterpret_cast<const QRgba64 *>(result.constScanLine(y));
        for (int x = 0; x < result.width(); ++x)
            QCOMPARE(pixels[x].alpha(), quint16(alphas[(x + y) % 8]) * 257);
    }
}

void ColorPipelineTest::floatingPreservesFormatAndAlpha_data()
{
    QTest::addColumn<int>("format");
    QTest::newRow("rgba-float") << int(QImage::Format_RGBA32FPx4);
    QTest::newRow("rgba-half") << int(QImage::Format_RGBA16FPx4);
    QTest::newRow("rgba-float-premultiplied")
        << int(QImage::Format_RGBA32FPx4_Premultiplied);
    QTest::newRow("rgba-half-premultiplied")
        << int(QImage::Format_RGBA16FPx4_Premultiplied);
}

void ColorPipelineTest::floatingPreservesFormatAndAlpha()
{
    QFETCH(int, format);
    const QImage::Format imageFormat = QImage::Format(format);
    QImage image = makeImage(9, 5, imageFormat, 0x9e3779b9u);
    image.setColorSpace(QColorSpace::DisplayP3);
    image.setDotsPerMeterX(4000);
    image.setDotsPerMeterY(5000);

    const QImage result = apply(image, wideExtendedParameters());
    QCOMPARE(result.format(), imageFormat);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.dotsPerMeterX(), 4000);
    QCOMPARE(result.dotsPerMeterY(), 5000);

    const int elementBytes = image.depth() / 32;
    for (int y = 0; y < image.height(); ++y) {
        const uchar *before = image.constScanLine(y);
        const uchar *after = result.constScanLine(y);
        for (int x = 0; x < image.width(); ++x) {
            QCOMPARE(std::memcmp(before + (x * 4 + 3) * elementBytes,
                                 after + (x * 4 + 3) * elementBytes,
                                 static_cast<std::size_t>(elementBytes)),
                     0);
        }
    }

    // The normalized working buffer must not emit NaN or infinity.
    const bool half = image.depth() == 64;
    for (int y = 0; y < result.height(); ++y) {
        const uchar *row = result.constScanLine(y);
        for (int x = 0; x < result.width() * 3; ++x) {
            double value;
            if (half) {
                value = double(
                    float(reinterpret_cast<const qfloat16 *>(row)[x]));
            } else {
                value = double(reinterpret_cast<const float *>(row)[x]);
            }
            QVERIFY(std::isfinite(value));
        }
    }
}

void ColorPipelineTest::extremeValuesDoNotCrash()
{
    const QImage integer = makeBands();
    const QImage floating = makeImage(8, 8, QImage::Format_RGBA32FPx4, 0x12345678u);

    Parameters high;
    Parameters low;
    for (const auto &key : parameterKeys()) {
        QVERIFY(setParameter(high, key, 1e9));
        QVERIFY(setParameter(low, key, -1e9));
    }
    for (const QImage &source : {integer, floating}) {
        const QImage highResult = apply(source, high);
        const QImage lowResult = apply(source, low);
        QVERIFY(!highResult.isNull());
        QVERIFY(!lowResult.isNull());
        QCOMPARE(highResult.size(), source.size());
    }

    Parameters hostile;
    hostile.exposure = std::numeric_limits<double>::infinity();
    hostile.temperature = std::numeric_limits<double>::quiet_NaN();
    hostile.curves[0].points[0] = std::numeric_limits<double>::quiet_NaN();
    hostile.curves[1].points[4] = std::numeric_limits<double>::infinity();
    hostile.grade[0].hue = std::numeric_limits<double>::quiet_NaN();
    hostile.grade[1].saturation = 1e308;
    hostile.texture = std::numeric_limits<double>::infinity();
    hostile.filterIntensity = std::numeric_limits<double>::quiet_NaN();
    for (const QImage &source : {integer, floating}) {
        const QImage result = apply(source, hostile);
        QVERIFY(!result.isNull());
        const QImage::Format expectedFormat = source.format() == QImage::Format_RGBA64
            ? QImage::Format_RGBA64
            : source.format();
        QCOMPARE(result.format(), expectedFormat);
    }
}


void ColorPipelineTest::filterPresetsChangePixelsAndScaleWithIntensity()
{
    const QImage source = makeBands();
    const auto presets = NekoPic::Filters::presetIds();
    QCOMPARE(presets.size(), 13);

    Parameters identity;
    identity.filterPreset = QStringLiteral("none");
    identity.filterIntensity = 1.0;
    QVERIFY2(sameBytes(apply(source, identity), source), "none must be an identity");

    for (const auto &preset : presets) {
        if (preset == QStringLiteral("none"))
            continue;
        Parameters off;
        off.filterPreset = preset;
        off.filterIntensity = 0.0;
        QVERIFY2(sameBytes(apply(source, off), source),
                 qPrintable(preset + QStringLiteral(" at intensity 0 must be a no-op")));

        Parameters half;
        half.filterPreset = preset;
        half.filterIntensity = 0.5;
        const QImage halfImage = apply(source, half);
        QVERIFY2(halfImage != source,
                 qPrintable(preset + QStringLiteral(" must change pixels")));

        Parameters full;
        full.filterPreset = preset;
        full.filterIntensity = 1.0;
        const QImage fullImage = apply(source, full);
        QVERIFY2(fullImage != source,
                 qPrintable(preset + QStringLiteral(" must change pixels at full strength")));
        QVERIFY2(fullImage != halfImage,
                 qPrintable(preset + QStringLiteral(" must scale with intensity")));
    }
}

void ColorPipelineTest::filterPresetsMatchLegacyPipeline()
{
    const QImage source = makeBands();
    const auto presets = NekoPic::Filters::presetIds();
    const double intensities[]{0.0, 0.25, 0.5, 0.75, 1.0};
    for (const auto &preset : presets) {
        for (const double intensity : intensities) {
            Parameters p;
            p.filterPreset = preset;
            p.filterIntensity = intensity;
            const QImage legacy = apply(source, p);
            const QImage extended = Internal::applyExtended(source, p);
            QVERIFY2(sameBytes(legacy, extended),
                     qPrintable(QStringLiteral("legacy/extended mismatch for %1 at %2")
                                    .arg(preset)
                                    .arg(intensity)));
        }
    }
}

QTEST_MAIN(ColorPipelineTest)
#include "tst_colorpipeline.moc"
