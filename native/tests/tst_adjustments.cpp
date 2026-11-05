#include "adjustments.h"
#include "rowparallel.h"

#include <QColorSpace>
#include <QtTest>
#include <qfloat16.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

using namespace NekoPic::Adjustments;

namespace {

// ---------------------------------------------------------------------------
// Reference implementation: a verbatim copy of the pre-optimization algorithm.
// It is intentionally slow and simple; every optimized call must match it
// bit-for-bit.
// ---------------------------------------------------------------------------

quint16 legacyChannel(double value)
{
    return static_cast<quint16>(std::lround(std::clamp(value, 0.0, 1.0) * 65535.0));
}

struct LegacyRgb {
    double red;
    double green;
    double blue;
};

LegacyRgb legacyFilterTarget(LegacyRgb color, const QString &preset)
{
    const auto [red, green, blue] = color;
    const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    if (preset == "mono") {
        return {luminance, luminance, luminance};
    } else if (preset == "vivid") {
        color.red = std::clamp((red - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.green = std::clamp((green - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.blue = std::clamp((blue - 0.5) * 1.18 + 0.5, 0.0, 1.0);
        color.red = luminance + (color.red - luminance) * 1.25;
        color.green = luminance + (color.green - luminance) * 1.25;
        color.blue = luminance + (color.blue - luminance) * 1.25;
    } else if (preset == "warm" || preset == "vintage") {
        const double amount = preset == "warm" ? 0.12 : 0.08;
        color.red = std::min(1.0, red + amount * (1.0 - red));
        color.blue = std::max(0.0, blue - amount * blue);
        if (preset == "vintage") {
            color.red = (color.red - 0.5) * 0.82 + 0.54;
            color.green = (green - 0.5) * 0.82 + 0.52;
            color.blue = (color.blue - 0.5) * 0.82 + 0.48;
        }
    } else if (preset == "cool") {
        color.red = std::max(0.0, red - 0.12 * red);
        color.blue = std::min(1.0, blue + 0.12 * (1.0 - blue));
    }
    return color;
}

bool legacyIsFloating(QImage::Format format)
{
    return format >= QImage::Format_RGBX16FPx4
        && format <= QImage::Format_RGBA32FPx4_Premultiplied;
}

QImage legacyApplyFloating(const QImage &source, double exposure, double brightness,
                           double contrast, double saturation, const QString &preset,
                           double intensity)
{
    auto result = source.copy();
    if (result.isNull())
        return {};
    const bool half = source.depth() == 64;
    const bool premultiplied = source.format() == QImage::Format_RGBA16FPx4_Premultiplied
        || source.format() == QImage::Format_RGBA32FPx4_Premultiplied;
    const double exposureFactor = std::exp2(exposure);
    const bool toneChanged = exposure != 0 || brightness != 0 || contrast != 0;
    for (int y = 0; y < result.height(); ++y) {
        auto *floats = half ? nullptr : reinterpret_cast<float *>(result.scanLine(y));
        auto *halves = half ? reinterpret_cast<qfloat16 *>(result.scanLine(y)) : nullptr;
        for (int x = 0; x < result.width(); ++x) {
            const auto offset = x * 4;
            const double alpha = half ? float(halves[offset + 3]) : floats[offset + 3];
            if (premultiplied && alpha <= 0)
                continue;
            const double scale = premultiplied ? alpha : 1.0;
            LegacyRgb original{(half ? float(halves[offset]) : floats[offset]) / scale,
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
            if (intensity > 0) {
                const auto target = legacyFilterTarget(color, preset);
                const auto blend = [=](double value, double filtered) {
                    if (value == filtered)
                        return value;
                    if (preset == "vivid")
                        return std::clamp(value + (filtered - value) * intensity, 0.0, 1.0);
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
    return result;
}

QImage legacyApply(const QImage &source, const Parameters &parameters)
{
    if (source.isNull())
        return {};

    const auto legacyBounded = [](double value, double limit) {
        return std::isfinite(value) ? std::clamp(value, -limit, limit) : 0.0;
    };
    const double exposure = legacyBounded(parameters.exposure, 4.0);
    const double brightness = legacyBounded(parameters.brightness, 1.0);
    const double contrast = legacyBounded(parameters.contrast, 1.0);
    const double saturation = legacyBounded(parameters.saturation, 1.0);
    const double intensity = std::isfinite(parameters.filterIntensity)
        ? std::clamp(parameters.filterIntensity, 0.0, 1.0)
        : 0.0;
    const auto preset = parameters.filterPreset;
    if (exposure == 0.0 && brightness == 0.0 && contrast == 0.0 && saturation == 0.0
        && (preset.isEmpty() || preset == "none" || intensity == 0.0))
        return source;

    if (legacyIsFloating(source.format()))
        return legacyApplyFloating(source, exposure, brightness, contrast, saturation, preset,
                                   intensity);

    QImage result = source.convertToFormat(QImage::Format_RGBA64);
    if (result.isNull())
        return {};

    const double exposureFactor = std::exp2(exposure);
    const double contrastFactor = 1.0 + contrast;
    const double saturationFactor = 1.0 + saturation;
    for (int y = 0; y < result.height(); ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(result.scanLine(y));
        for (int x = 0; x < result.width(); ++x) {
            const QRgba64 pixel = pixels[x];
            auto tone = [=](quint16 value) {
                return (value / 65535.0 * exposureFactor - 0.5) * contrastFactor
                    + 0.5 + brightness;
            };
            const double red = tone(pixel.red());
            const double green = tone(pixel.green());
            const double blue = tone(pixel.blue());
            const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
            pixels[x] = QRgba64::fromRgba64(
                legacyChannel(luminance + (red - luminance) * saturationFactor),
                legacyChannel(luminance + (green - luminance) * saturationFactor),
                legacyChannel(luminance + (blue - luminance) * saturationFactor), pixel.alpha());
        }
    }
    if (!preset.isEmpty() && intensity > 0.0) {
        for (int y = 0; y < result.height(); ++y) {
            auto *pixels = reinterpret_cast<QRgba64 *>(result.scanLine(y));
            for (int x = 0; x < result.width(); ++x) {
                const QRgba64 pixel = pixels[x];
                double red = pixel.red() / 65535.0;
                double green = pixel.green() / 65535.0;
                double blue = pixel.blue() / 65535.0;
                const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
                double targetRed = red;
                double targetGreen = green;
                double targetBlue = blue;
                if (preset == "mono") {
                    targetRed = targetGreen = targetBlue = luminance;
                } else if (preset == "vivid") {
                    targetRed = std::clamp((red - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetGreen = std::clamp((green - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetBlue = std::clamp((blue - 0.5) * 1.18 + 0.5, 0.0, 1.0);
                    targetRed = luminance + (targetRed - luminance) * 1.25;
                    targetGreen = luminance + (targetGreen - luminance) * 1.25;
                    targetBlue = luminance + (targetBlue - luminance) * 1.25;
                } else if (preset == "warm" || preset == "vintage") {
                    const double amount = preset == "warm" ? 0.12 : 0.08;
                    targetRed = std::min(1.0, red + amount * (1.0 - red));
                    targetBlue = std::max(0.0, blue - amount * blue);
                    if (preset == "vintage") {
                        targetRed = (targetRed - 0.5) * 0.82 + 0.54;
                        targetGreen = (green - 0.5) * 0.82 + 0.52;
                        targetBlue = (targetBlue - 0.5) * 0.82 + 0.48;
                    }
                } else if (preset == "cool") {
                    targetRed = std::max(0.0, red - 0.12 * red);
                    targetBlue = std::min(1.0, blue + 0.12 * (1.0 - blue));
                }
                red += (targetRed - red) * intensity;
                green += (targetGreen - green) * intensity;
                blue += (targetBlue - blue) * intensity;
                pixels[x] =
                    QRgba64::fromRgba64(legacyChannel(red), legacyChannel(green),
                                        legacyChannel(blue), pixel.alpha());
            }
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

struct ParameterCase {
    QString name;
    Parameters parameters;
};

void addTone(ParameterCase &c, double exposure, double brightness, double contrast)
{
    c.parameters.exposure = exposure;
    c.parameters.brightness = brightness;
    c.parameters.contrast = contrast;
}

void addFilter(ParameterCase &c, const char *preset, double intensity)
{
    c.parameters.filterPreset = QString::fromLatin1(preset);
    c.parameters.filterIntensity = intensity;
}

std::vector<ParameterCase> allParameterCases()
{
    std::vector<ParameterCase> cases;
    cases.push_back({QStringLiteral("identity"), Parameters{}});
    {
        ParameterCase c{QStringLiteral("exposure +2"), {}};
        c.parameters.exposure = 2.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("exposure -2"), {}};
        c.parameters.exposure = -2.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("brightness +1"), {}};
        c.parameters.brightness = 1.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("brightness -1"), {}};
        c.parameters.brightness = -1.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("contrast +1"), {}};
        c.parameters.contrast = 1.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("contrast -1"), {}};
        c.parameters.contrast = -1.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("saturation +1"), {}};
        c.parameters.saturation = 1.0;
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("saturation -1"), {}};
        c.parameters.saturation = -1.0;
        cases.push_back(c);
    }
    for (const char *preset : {"mono", "vivid", "warm", "cool", "vintage"}) {
        for (double intensity : {0.0, 0.5, 1.0}) {
            ParameterCase c{QStringLiteral("%1 @ %2")
                                .arg(QString::fromLatin1(preset))
                                .arg(intensity),
                            {}};
            addFilter(c, preset, intensity);
            cases.push_back(c);
        }
    }
    {
        ParameterCase c{QStringLiteral("tone + saturation + vintage"), {}};
        addTone(c, 1.2, 0.0, 0.0);
        c.parameters.saturation = 0.3;
        addFilter(c, "vintage", 0.7);
        cases.push_back(c);
    }
    {
        ParameterCase c{QStringLiteral("tone + saturation + warm"), {}};
        addTone(c, -1.0, 0.5, -0.3);
        c.parameters.saturation = -0.5;
        addFilter(c, "warm", 0.4);
        cases.push_back(c);
    }
    return cases;
}

std::vector<ParameterCase> largeParameterCases()
{
    return {
        {QStringLiteral("exposure +2"), [] {
             Parameters p;
             p.exposure = 2.0;
             return p;
         }()},
        {QStringLiteral("saturation -1"), [] {
             Parameters p;
             p.saturation = -1.0;
             return p;
         }()},
        {QStringLiteral("combined vintage"), [] {
             Parameters p;
             p.exposure = 1.2;
             p.saturation = 0.3;
             p.filterPreset = QStringLiteral("vintage");
             p.filterIntensity = 0.7;
             return p;
         }()},
    };
}

QImage makeImage(int width, int height, QImage::Format format, quint32 seed)
{
    QImage image(width, height, format);
    if (image.isNull())
        return image;
    const quint16 alphaEdges[]{0, 1, 0x7fff, 0x8000, 0xfffe, 0xffff};
    quint32 state = seed;
    auto next = [&state] {
        state = state * 1664525u + 1013904223u;
        return state;
    };
    const bool floating = legacyIsFloating(format);
    const bool half = format == QImage::Format_RGBX16FPx4
        || format == QImage::Format_RGBA16FPx4
        || format == QImage::Format_RGBA16FPx4_Premultiplied;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const quint32 a = next();
            const quint32 b = next();
            const quint32 c = next();
            const quint32 d = next();
            const quint16 alpha = alphaEdges[d % 6];
            if (floating) {
                float channels[4]{
                    float((a & 0xffff) / 65535.0) * 1.6f,
                    float((b & 0xffff) / 65535.0),
                    float((c & 0xffff) / 65535.0) * 0.75f,
                    float(alpha / 65535.0),
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
                pixel[3] = alpha >> 8;
            } else {
                auto *pixel = reinterpret_cast<QRgba64 *>(image.scanLine(y)) + x;
                *pixel = QRgba64::fromRgba64(a & 0xffff, (b >> 3) & 0xffff,
                                             (c >> 7) & 0xffff, alpha);
            }
        }
    }
    return image;
}

bool sameImage(const QImage &actual, const QImage &expected)
{
    if (actual.format() != expected.format() || actual.size() != expected.size())
        return false;
    if (actual.colorSpace() != expected.colorSpace())
        return false;
    if (actual.dotsPerMeterX() != expected.dotsPerMeterX()
        || actual.dotsPerMeterY() != expected.dotsPerMeterY())
        return false;
    if (actual.sizeInBytes() != expected.sizeInBytes())
        return false;
    const qsizetype rowBytes = qsizetype(actual.width()) * actual.depth() / 8;
    for (int y = 0; y < actual.height(); ++y) {
        if (std::memcmp(actual.constScanLine(y), expected.constScanLine(y), rowBytes) != 0)
            return false;
    }
    return true;
}

void compareAgainstLegacy(const QImage &source, const QString &label)
{
    const QImage sourceBefore = source.copy();
    for (const auto &testCase : allParameterCases()) {
        const QImage expected = legacyApply(source, testCase.parameters);
        const QImage actual = apply(source, testCase.parameters);
        QVERIFY2(sameImage(actual, expected),
                 qPrintable(QStringLiteral("%1 / %2").arg(label, testCase.name)));
    }
    QVERIFY2(sameImage(source, sourceBefore), qPrintable(label + QStringLiteral(" source")));
}

} // namespace

class AdjustmentsTest : public QObject {
    Q_OBJECT
private slots:
    void identityPreservesImage();
    void exposureBrightensAndDarkens();
    void brightnessAndContrastChangeTonality();
    void saturationChangesColorWithoutChangingAlpha();
    void preservesHighDepthAndColorSpace();
    void handlesNullAndOutOfRangeParameters();
    void presetsRespectIntensityAndPreserveImageMetadata();
    void colorFilterPromotesGrayscaleWithoutDiscardingTint();
    void floatingFilterPreservesStorage_data();
    void floatingFilterPreservesStorage();
    void floatingExposurePreservesHdrPrecision();
    void rgba64FilterHasExactChannels();
    void floatingVividMatchesIntegerAtPartialIntensity();
    void matchesLegacyReferenceSmall_data();
    void matchesLegacyReferenceSmall();
    void matchesLegacyReferenceLarge_data();
    void matchesLegacyReferenceLarge();
    void matchesLegacyForEveryChannelValue();
    void parallelPathMatchesSerialReference();
    void alphaAndMetadataArePreservedExactly();
    void rowParallelThresholdSelectsSerialForSmallImages();
};

void AdjustmentsTest::identityPreservesImage()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    QCOMPARE(apply(image, {}), image);
}

void AdjustmentsTest::exposureBrightensAndDarkens()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.fill(QColor::fromRgbF(0.25, 0.25, 0.25));
    Parameters p;
    p.exposure = 1.0;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() > image.pixelColor(0, 0).redF());
    p.exposure = -1.0;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() < image.pixelColor(0, 0).redF());
}

void AdjustmentsTest::brightnessAndContrastChangeTonality()
{
    QImage image(2, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgbF(0.25, 0.25, 0.25));
    image.setPixelColor(1, 0, QColor::fromRgbF(0.75, 0.75, 0.75));
    Parameters p;
    p.brightness = 0.2;
    QVERIFY(apply(image, p).pixelColor(0, 0).redF() > image.pixelColor(0, 0).redF());
    p.brightness = 0.0;
    p.contrast = 0.5;
    const auto adjusted = apply(image, p);
    QVERIFY(adjusted.pixelColor(0, 0).redF() < image.pixelColor(0, 0).redF());
    QVERIFY(adjusted.pixelColor(1, 0).redF() > image.pixelColor(1, 0).redF());
}

void AdjustmentsTest::saturationChangesColorWithoutChangingAlpha()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(50000, 20000, 10000, 12345));
    Parameters p;
    p.saturation = -1.0;
    const auto pixel = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(pixel.red(), pixel.green());
    QCOMPARE(pixel.green(), pixel.blue());
    QCOMPARE(pixel.alpha(), quint16(12345));
}

void AdjustmentsTest::preservesHighDepthAndColorSpace()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(12345, 23456, 34567, 45678));
    image.setColorSpace(QColorSpace::DisplayP3);
    Parameters p;
    p.brightness = 0.01;
    const auto result = apply(image, p);
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QCOMPARE(result.pixelColor(0, 0).rgba64().alpha(), quint16(45678));
    QVERIFY(result.pixelColor(0, 0).rgba64().red() % 257 != 0);
}

void AdjustmentsTest::handlesNullAndOutOfRangeParameters()
{
    QVERIFY(apply(QImage(), {}).isNull());
    QImage image(1, 1, QImage::Format_RGBA64);
    image.fill(Qt::red);
    Parameters p;
    p.brightness = 100.0;
    const auto result = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(result.red(), quint16(65535));
    QCOMPARE(result.green(), quint16(65535));
}

void AdjustmentsTest::presetsRespectIntensityAndPreserveImageMetadata()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(50000, 20000, 10000, 12345));
    image.setColorSpace(QColorSpace::DisplayP3);
    Parameters p;
    p.filterPreset = "mono";
    p.filterIntensity = 0.0;
    QCOMPARE(apply(image, p), image);
    p.filterIntensity = 1.0;
    const auto filtered = apply(image, p);
    QCOMPARE(filtered.format(), image.format());
    QCOMPARE(filtered.colorSpace(), image.colorSpace());
    QCOMPARE(filtered.pixelColor(0, 0).rgba64().alpha(), quint16(12345));
    const auto pixel = filtered.pixelColor(0, 0).rgba64();
    QCOMPARE(pixel.red(), pixel.green());
    QCOMPARE(pixel.green(), pixel.blue());
    p.filterPreset = "unknown";
    QCOMPARE(apply(image, p), image);
}

void AdjustmentsTest::colorFilterPromotesGrayscaleWithoutDiscardingTint()
{
    QImage image(1, 1, QImage::Format_Grayscale8);
    image.fill(QColor(100, 100, 100));
    image.setColorSpace(QColorSpace::SRgb);
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p);
    QCOMPARE(result.format(), QImage::Format_RGBA64);
    QCOMPARE(result.colorSpace(), image.colorSpace());
    QVERIFY(result.pixelColor(0, 0).red() > result.pixelColor(0, 0).blue());
}

void AdjustmentsTest::floatingFilterPreservesStorage_data()
{
    QTest::addColumn<QImage::Format>("format");
    QTest::newRow("rgba-float") << QImage::Format_RGBA32FPx4;
    QTest::newRow("rgba-half") << QImage::Format_RGBA16FPx4;
    QTest::newRow("rgba-float-premultiplied") << QImage::Format_RGBA32FPx4_Premultiplied;
    QTest::newRow("rgba-half-premultiplied") << QImage::Format_RGBA16FPx4_Premultiplied;
    QTest::newRow("rgbx-float") << QImage::Format_RGBX32FPx4;
    QTest::newRow("rgbx-half") << QImage::Format_RGBX16FPx4;
}

void AdjustmentsTest::floatingFilterPreservesStorage()
{
    QFETCH(QImage::Format, format);
    QImage seed(1, 1, QImage::Format_RGBA32FPx4);
    auto *seedChannels = reinterpret_cast<float *>(seed.bits());
    seedChannels[0] = 0.123456789f;
    seedChannels[1] = 1.23456789f; // Warm does not edit green, even above SDR white.
    seedChannels[2] = 0.234567891f;
    seedChannels[3] = 0.3456780016f;
    const auto image = seed.convertToFormat(format);
    const auto original = image.copy();
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p);
    QCOMPARE(result.format(), format);
    const qsizetype channelBytes = image.depth() / 32;
    QCOMPARE(std::memcmp(result.constBits() + 3 * channelBytes,
                         image.constBits() + 3 * channelBytes, channelBytes),
             0);
    QCOMPARE(std::memcmp(result.constBits() + channelBytes,
                         image.constBits() + channelBytes, channelBytes),
             0);
    QVERIFY(std::memcmp(result.constBits(), image.constBits(), channelBytes) != 0);
    QCOMPARE(image, original);
    p.filterIntensity = 0;
    QCOMPARE(apply(image, p), original);
}

void AdjustmentsTest::floatingExposurePreservesHdrPrecision()
{
    QImage image(1, 1, QImage::Format_RGBA32FPx4);
    image.setColorSpace(QColorSpace::DisplayP3);
    auto *pixel = reinterpret_cast<float *>(image.bits());
    pixel[0] = 2.1234567f;
    pixel[1] = 0.123456789f;
    pixel[2] = -0.125f;
    pixel[3] = 0.3456780016f;
    Parameters p;
    p.exposure = 1;
    const auto result = apply(image, p);
    QCOMPARE(result.format(), image.format());
    QCOMPARE(result.colorSpace(), image.colorSpace());
    const auto *adjusted = reinterpret_cast<const float *>(result.constBits());
    QCOMPARE(adjusted[0], pixel[0] * 2);
    QCOMPARE(adjusted[1], pixel[1] * 2);
    QCOMPARE(adjusted[2], -0.25f);
    QCOMPARE(std::memcmp(adjusted + 3, pixel + 3, sizeof(float)), 0);
    p.exposure = 0;
    p.filterPreset = "warm";
    p.filterIntensity = 0.5;
    const auto warm = apply(image, p);
    const auto *filtered = reinterpret_cast<const float *>(warm.constBits());
    QCOMPARE(filtered[1], pixel[1]);
    QCOMPARE(filtered[2], -0.0625f); // Blend an explicitly SDR-clamped warm-blue target.
}

void AdjustmentsTest::rgba64FilterHasExactChannels()
{
    QImage image(1, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(10000, 20000, 30000, 12345));
    Parameters p;
    p.filterPreset = "warm";
    const auto result = apply(image, p).pixelColor(0, 0).rgba64();
    QCOMPARE(result.red(), quint16(16664));
    QCOMPARE(result.green(), quint16(20000));
    QCOMPARE(result.blue(), quint16(26400));
    QCOMPARE(result.alpha(), quint16(12345));
}

void AdjustmentsTest::floatingVividMatchesIntegerAtPartialIntensity()
{
    QImage image(3, 1, QImage::Format_RGBA64);
    image.setPixelColor(0, 0, QColor::fromRgba64(60000, 10000, 30000, 12345));
    image.setPixelColor(1, 0, QColor::fromRgba64(5000, 60000, 10000, 23456));
    image.setPixelColor(2, 0, QColor::fromRgba64(10000, 20000, 65000, 34567));
    Parameters p;
    p.filterPreset = "vivid";
    p.filterIntensity = 0.5;
    const auto integerResult = apply(image, p);
    const auto floatingResult = apply(image.convertToFormat(QImage::Format_RGBA32FPx4), p);
    for (int x = 0; x < image.width(); ++x) {
        const auto expected = integerResult.pixelColor(x, 0);
        const auto actual = floatingResult.pixelColor(x, 0);
        // One 16-bit rounding unit, allowing for float conversion on input.
        QVERIFY(std::abs(actual.redF() - expected.redF()) < 2.0 / 65535);
        QVERIFY(std::abs(actual.greenF() - expected.greenF()) < 2.0 / 65535);
        QVERIFY(std::abs(actual.blueF() - expected.blueF()) < 2.0 / 65535);
    }
}

void AdjustmentsTest::matchesLegacyReferenceSmall_data()
{
    QTest::addColumn<int>("width");
    QTest::addColumn<int>("height");
    QTest::addColumn<int>("format");

    const struct {
        int width;
        int height;
    } sizes[]{{1, 1}, {1, 257}, {257, 1}, {64, 64}};
    const struct {
        const char *name;
        QImage::Format format;
    } formats[]{{"rgba8888", QImage::Format_RGBA8888},
                {"rgba64", QImage::Format_RGBA64},
                {"rgba32f", QImage::Format_RGBA32FPx4},
                {"rgba16f-premultiplied", QImage::Format_RGBA16FPx4_Premultiplied}};

    for (const auto &size : sizes) {
        for (const auto &format : formats) {
            QTest::newRow(qPrintable(QStringLiteral("%1x%2-%3")
                                         .arg(size.width)
                                         .arg(size.height)
                                         .arg(QString::fromLatin1(format.name))))
                << size.width << size.height << int(format.format);
        }
    }
}

void AdjustmentsTest::matchesLegacyReferenceSmall()
{
    QFETCH(int, width);
    QFETCH(int, height);
    QFETCH(int, format);
    const QImage source =
        makeImage(width, height, QImage::Format(format), 0x9e3779b9u + quint32(width * 31 + height));
    compareAgainstLegacy(source,
                         QStringLiteral("%1x%2/%3").arg(width).arg(height).arg(format));
}

void AdjustmentsTest::matchesLegacyReferenceLarge_data()
{
    QTest::addColumn<int>("width");
    QTest::addColumn<int>("height");
    QTest::addColumn<int>("format");

    const struct {
        int width;
        int height;
    } sizes[]{{1024, 768}, {2048, 1536}};
    const struct {
        const char *name;
        QImage::Format format;
    } formats[]{{"rgba8888", QImage::Format_RGBA8888},
                {"rgba64", QImage::Format_RGBA64},
                {"rgba32f", QImage::Format_RGBA32FPx4}};

    for (const auto &size : sizes) {
        for (const auto &format : formats) {
            QTest::newRow(qPrintable(QStringLiteral("%1x%2-%3")
                                         .arg(size.width)
                                         .arg(size.height)
                                         .arg(QString::fromLatin1(format.name))))
                << size.width << size.height << int(format.format);
        }
    }
}

void AdjustmentsTest::matchesLegacyReferenceLarge()
{
    QFETCH(int, width);
    QFETCH(int, height);
    QFETCH(int, format);
    const QImage source =
        makeImage(width, height, QImage::Format(format), 0x51ed270bu + quint32(width + height));
    for (const auto &testCase : largeParameterCases()) {
        const QImage expected = legacyApply(source, testCase.parameters);
        const QImage actual = apply(source, testCase.parameters);
        QVERIFY2(sameImage(actual, expected),
                 qPrintable(QStringLiteral("%1x%2/%3 / %4")
                                .arg(width)
                                .arg(height)
                                .arg(format)
                                .arg(testCase.name)));
    }
}

void AdjustmentsTest::matchesLegacyForEveryChannelValue()
{
    // 256x256 images whose red channel covers every 16-bit value, paired with
    // three deterministic permutations for green and blue. This exercises the
    // tone-only shortcut at every possible 16-bit input.
    const std::vector<ParameterCase> cases{
        {QStringLiteral("exposure +2"), [] {
             Parameters p;
             p.exposure = 2.0;
             return p;
         }()},
        {QStringLiteral("exposure -2"), [] {
             Parameters p;
             p.exposure = -2.0;
             return p;
         }()},
        {QStringLiteral("contrast -1"), [] {
             Parameters p;
             p.contrast = -1.0;
             return p;
         }()},
        {QStringLiteral("brightness -1"), [] {
             Parameters p;
             p.brightness = -1.0;
             return p;
         }()},
        {QStringLiteral("mixed tone"), [] {
             Parameters p;
             p.exposure = 0.3;
             p.brightness = 0.2;
             p.contrast = -0.4;
             return p;
         }()},
        {QStringLiteral("mono filter"), [] {
             Parameters p;
             p.exposure = 0.7;
             p.filterPreset = QStringLiteral("mono");
             p.filterIntensity = 0.75;
             return p;
         }()},
    };

    for (int variant = 0; variant < 3; ++variant) {
        QImage image(256, 256, QImage::Format_RGBA64);
        for (int i = 0; i < 65536; ++i) {
            const int x = i % 256;
            const int y = i / 256;
            const quint16 red = quint16(i);
            const quint16 green = quint16((i * 257 + variant * 7919) & 0xffff);
            const quint16 blue = quint16((i * 8191 + variant * 104729) & 0xffff);
            auto *pixel = reinterpret_cast<QRgba64 *>(image.scanLine(y)) + x;
            *pixel = QRgba64::fromRgba64(red, green, blue, 0xffff);
        }
        for (const auto &testCase : cases) {
            const QImage expected = legacyApply(image, testCase.parameters);
            const QImage actual = apply(image, testCase.parameters);
            QVERIFY2(sameImage(actual, expected),
                     qPrintable(QStringLiteral("variant %1 / %2")
                                    .arg(variant)
                                    .arg(testCase.name)));
        }
    }
}

void AdjustmentsTest::parallelPathMatchesSerialReference()
{
    // 1024x1024 is above the row-parallel threshold; the legacy reference is
    // serial, so this checks the threaded path across chunk boundaries.
    const struct {
        int width;
        int height;
    } sizes[]{{1024, 1024}, {1600, 800}};
    for (const auto &size : sizes) {
        for (QImage::Format format :
             {QImage::Format_RGBA64, QImage::Format_RGBA8888, QImage::Format_RGBA32FPx4}) {
            const QImage source =
                makeImage(size.width, size.height, format, 0x2545f491u + quint32(size.width));
            for (const auto &testCase : largeParameterCases()) {
                const QImage expected = legacyApply(source, testCase.parameters);
                const QImage actual = apply(source, testCase.parameters);
                QVERIFY2(sameImage(actual, expected),
                         qPrintable(QStringLiteral("%1x%2 format %3 / %4")
                                        .arg(size.width)
                                        .arg(size.height)
                                        .arg(int(format))
                                        .arg(testCase.name)));
            }
        }
    }
}

void AdjustmentsTest::alphaAndMetadataArePreservedExactly()
{
    QImage image(16, 4, QImage::Format_RGBA64);
    const quint16 alphaEdges[]{0, 1, 0x7fff, 0x8000, 0xfffe, 0xffff};
    for (int y = 0; y < image.height(); ++y) {
        auto *pixels = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            pixels[x] = QRgba64::fromRgba64(quint16(x * 4096), quint16(y * 16000),
                                            quint16(x * y * 997), alphaEdges[(x + y) % 6]);
        }
    }
    image.setColorSpace(QColorSpace::DisplayP3);
    image.setDotsPerMeterX(2835);
    image.setDotsPerMeterY(2836);
    const QImage sourceBefore = image.copy();

    for (const auto &testCase : allParameterCases()) {
        const QImage actual = apply(image, testCase.parameters);
        const QImage expected = legacyApply(image, testCase.parameters);
        QVERIFY2(sameImage(actual, expected), qPrintable(testCase.name));
        QCOMPARE(actual.format(), expected.format());
        QCOMPARE(actual.colorSpace(), image.colorSpace());
        QCOMPARE(actual.dotsPerMeterX(), 2835);
        QCOMPARE(actual.dotsPerMeterY(), 2836);
        for (int y = 0; y < actual.height(); ++y) {
            const auto *pixels = reinterpret_cast<const QRgba64 *>(actual.constScanLine(y));
            for (int x = 0; x < actual.width(); ++x)
                QCOMPARE(pixels[x].alpha(), alphaEdges[(x + y) % 6]);
        }
    }
    QVERIFY(sameImage(image, sourceBefore));

    // Alpha edges on premultiplied floating storage, where alpha == 0 pixels
    // are skipped and nonzero pixels are scaled.
    for (QImage::Format format :
         {QImage::Format_RGBA16FPx4_Premultiplied, QImage::Format_RGBA32FPx4_Premultiplied}) {
        const QImage floating = makeImage(8, 4, format, 0xabcdef01u);
        for (const auto &testCase : largeParameterCases()) {
            const QImage actual = apply(floating, testCase.parameters);
            const QImage expected = legacyApply(floating, testCase.parameters);
            QVERIFY2(sameImage(actual, expected),
                     qPrintable(QStringLiteral("float format %1 / %2")
                                    .arg(int(format))
                                    .arg(testCase.name)));
        }
    }
}

void AdjustmentsTest::rowParallelThresholdSelectsSerialForSmallImages()
{
    using NekoPic::Detail::rowWorkerCount;
    const int hardwareLimit = NekoPic::Detail::hardwareWorkerLimit();

    QCOMPARE(static_cast<int>(rowWorkerCount(1, 1)), 1);
    QCOMPARE(static_cast<int>(rowWorkerCount(0, 2000)), 1);
    QCOMPARE(static_cast<int>(rowWorkerCount(1024, 1023)), 1); // just below 1 MP
    QCOMPARE(static_cast<int>(rowWorkerCount(4096, 1)), 1);    // single scanline
    QCOMPARE(static_cast<int>(rowWorkerCount(32, 100000)), 1); // too narrow to split
    QCOMPARE(static_cast<int>(rowWorkerCount(1024, 1024)), hardwareLimit);
    QCOMPARE(static_cast<int>(rowWorkerCount(4000, 3000)), hardwareLimit);

    // A sub-threshold image must still match the reference exactly.
    const QImage small = makeImage(1024, 1023, QImage::Format_RGBA64, 0xfeedfaceu);
    Parameters p;
    p.saturation = -1.0;
    p.filterPreset = QStringLiteral("vivid");
    p.filterIntensity = 0.5;
    QVERIFY(sameImage(apply(small, p), legacyApply(small, p)));
}

QTEST_GUILESS_MAIN(AdjustmentsTest)
#include "tst_adjustments.moc"
