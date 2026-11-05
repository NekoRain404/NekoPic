#include "render/previewmath.h"

#include "adjustments.h"

#include <QImage>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <iterator>

// Parity tests between the GPU preview shader mirror (render/previewmath.*)
// and the authoritative CPU implementation (core/adjustments.cpp). The mirror
// evaluates the shader formula; it is never used to produce export pixels.

using namespace NekoPic;
using namespace NekoPic::Render::PreviewMath;

namespace {

QImage makeGradientImage()
{
    QImage image(8, 6, QImage::Format_RGBA8888);
    for (int y = 0; y < image.height(); ++y) {
        uchar *line = image.scanLine(y);
        for (int x = 0; x < image.width(); ++x) {
            const int i = y * image.width() + x;
            uchar *pixel = line + x * 4;
            pixel[0] = static_cast<uchar>((i * 37 + 11) & 0xff);
            pixel[1] = static_cast<uchar>((i * 73 + 29) & 0xff);
            pixel[2] = static_cast<uchar>((i * 109 + 47) & 0xff);
            // Mix fully transparent, fully opaque and intermediate alpha.
            pixel[3] = i % 5 == 0 ? 0 : (i % 3 == 0 ? 255 : static_cast<uchar>((i * 41 + 7) & 0xff));
        }
    }
    return image;
}

QImage makeAlphaEdgeImage()
{
    constexpr int alphas[]{0, 1, 2, 64, 192, 255};
    QImage image(static_cast<int>(std::size(alphas)), 1, QImage::Format_RGBA8888);
    uchar *line = image.scanLine(0);
    for (int x = 0; x < image.width(); ++x) {
        uchar *pixel = line + x * 4;
        // Non-zero straight-alpha RGB under a fully transparent pixel is legal,
        // and the CPU path still adjusts those channels.
        pixel[0] = static_cast<uchar>(200 - x * 17);
        pixel[1] = static_cast<uchar>(30 + x * 29);
        pixel[2] = static_cast<uchar>(77 + x * 11);
        pixel[3] = static_cast<uchar>(alphas[x]);
    }
    return image;
}

QImage makeSinglePixel()
{
    QImage image(1, 1, QImage::Format_RGBA8888);
    uchar *pixel = image.scanLine(0);
    pixel[0] = 200;
    pixel[1] = 30;
    pixel[2] = 77;
    pixel[3] = 128;
    return image;
}

QImage makeRgba64Image()
{
    QImage image(6, 4, QImage::Format_RGBA64);
    for (int y = 0; y < image.height(); ++y) {
        auto *line = reinterpret_cast<QRgba64 *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const int i = y * image.width() + x;
            line[x] = QRgba64::fromRgba64(
                static_cast<quint16>((i * 9001 + 3) & 0xffff),
                static_cast<quint16>((i * 17011 + 17) & 0xffff),
                static_cast<quint16>((i * 33013 + 29) & 0xffff),
                static_cast<quint16>((i * 41011 + 41) & 0xffff));
        }
    }
    return image;
}

// Returns the largest per-channel absolute difference (including alpha) after
// bringing both images to straight-alpha RGBA8888.
int maxChannelDiff(const QImage &lhs, const QImage &rhs)
{
    const QImage a = lhs.convertToFormat(QImage::Format_RGBA8888);
    const QImage b = rhs.convertToFormat(QImage::Format_RGBA8888);
    if (a.size() != b.size())
        return 256;
    int worst = 0;
    for (int y = 0; y < a.height(); ++y) {
        const uchar *pa = a.constScanLine(y);
        const uchar *pb = b.constScanLine(y);
        for (int x = 0; x < a.width() * 4; ++x)
            worst = std::max(worst, std::abs(int(pa[x]) - int(pb[x])));
    }
    return worst;
}

int maxChannelDiff16(const QImage &lhs, const QImage &rhs)
{
    if (lhs.size() != rhs.size())
        return 65536;
    int worst = 0;
    for (int y = 0; y < lhs.height(); ++y) {
        const auto *pa = reinterpret_cast<const QRgba64 *>(lhs.constScanLine(y));
        const auto *pb = reinterpret_cast<const QRgba64 *>(rhs.constScanLine(y));
        for (int x = 0; x < lhs.width(); ++x) {
            for (int c = 0; c < 4; ++c) {
                const int va = c == 0 ? pa[x].red() : c == 1 ? pa[x].green()
                    : c == 2 ? pa[x].blue() : pa[x].alpha();
                const int vb = c == 0 ? pb[x].red() : c == 1 ? pb[x].green()
                    : c == 2 ? pb[x].blue() : pb[x].alpha();
                worst = std::max(worst, std::abs(va - vb));
            }
        }
    }
    return worst;
}

} // namespace

class PreviewMathTest : public QObject {
    Q_OBJECT
private slots:
    void parity_data();
    void parity();
    void rgba64Parity();
    void extendedRgba64Parity();
    void alphaPreserved();
    void nullImage();
};

void PreviewMathTest::parity_data()
{
    QTest::addColumn<QImage>("image");
    QTest::addColumn<double>("exposure");
    QTest::addColumn<double>("brightness");
    QTest::addColumn<double>("contrast");
    QTest::addColumn<double>("saturation");
    QTest::addColumn<double>("highlights");
    QTest::addColumn<double>("shadows");
    QTest::addColumn<double>("whites");
    QTest::addColumn<double>("blacks");
    QTest::addColumn<double>("temperature");
    QTest::addColumn<double>("tint");
    QTest::addColumn<double>("vibrance");

    struct Case {
        const char *name;
        double exposure;
        double brightness;
        double contrast;
        double saturation;
        double highlights;
        double shadows;
        double whites;
        double blacks;
        double temperature;
        double tint;
        double vibrance;
    };
    const Case cases[]{
        {"identity", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"exposure+2", 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"exposure-2", -2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"brightness+0.5", 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"brightness-0.75", 0.0, -0.75, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"contrast+1", 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"contrast-1", 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"saturation-1", 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"saturation+1", 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"combined", 1.25, 0.1, 0.4, -0.6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        // Extended-basic stages.
        {"highlights+1", 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"highlights-1", 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"shadows+1", 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"shadows-1", 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        {"whites+1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0},
        {"whites-1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0},
        {"blacks+1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0},
        {"blacks-1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0},
        {"temperature+1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0},
        {"temperature-1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0},
        {"tint+1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0},
        {"tint-1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0},
        {"vibrance+1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0},
        {"vibrance-1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0},
        {"wb+tonal", 0.5, 0.0, 0.2, 0.0, 0.6, -0.4, 0.3, -0.5, 0.8, -0.7, 0.0},
        {"extended-combined", 1.25, 0.1, 0.4, -0.6, 0.5, -0.4, 0.2, -0.3, 0.6,
         -0.5, 0.7},
        {"extended-extreme", 4.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
         1.0},
        {"extended-negative", -4.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0,
         -1.0, -1.0, -1.0},
    };

    const auto addImage = [&](const QImage &image, const char *label) {
        for (const Case &item : cases) {
            const QString name = QStringLiteral("%1/%2").arg(QString::fromLatin1(label),
                                                             QString::fromLatin1(item.name));
            QTest::newRow(qPrintable(name)) << image << item.exposure << item.brightness
                                            << item.contrast << item.saturation
                                            << item.highlights << item.shadows
                                            << item.whites << item.blacks
                                            << item.temperature << item.tint
                                            << item.vibrance;
        }
    };

    addImage(makeGradientImage(), "gradient");
    addImage(makeAlphaEdgeImage(), "alpha-edges");
    addImage(makeSinglePixel(), "1x1");
}

void PreviewMathTest::parity()
{
    QFETCH(QImage, image);
    QFETCH(double, exposure);
    QFETCH(double, brightness);
    QFETCH(double, contrast);
    QFETCH(double, saturation);
    QFETCH(double, highlights);
    QFETCH(double, shadows);
    QFETCH(double, whites);
    QFETCH(double, blacks);
    QFETCH(double, temperature);
    QFETCH(double, tint);
    QFETCH(double, vibrance);

    Adjustments::Parameters parameters;
    parameters.exposure = exposure;
    parameters.brightness = brightness;
    parameters.contrast = contrast;
    parameters.saturation = saturation;
    parameters.highlights = highlights;
    parameters.shadows = shadows;
    parameters.whites = whites;
    parameters.blacks = blacks;
    parameters.temperature = temperature;
    parameters.tint = tint;
    parameters.vibrance = vibrance;

    const QImage expected = Adjustments::apply(image, parameters);
    const QImage actual = applyRgba8(image, parameters);

    QCOMPARE(actual.format(), QImage::Format_RGBA8888);
    // The CPU path rounds through 16 bits and converts back; one LSB of
    // divergence is expected. Extended stages add another intermediate clamp
    // but no extra quantization, so 2/255 still leaves margin for rounding
    // order without hiding a real formula mismatch. GPU float precision is
    // covered by the QML shader test, which uses a wider 4/255 tolerance.
    const int worst = maxChannelDiff(expected, actual);
    QVERIFY2(worst <= 2, qPrintable(QStringLiteral("max channel diff %1/255").arg(worst)));
}

void PreviewMathTest::rgba64Parity()
{
    const QImage image = makeRgba64Image();
    const double exposures[]{0.0, 2.0, -2.0};
    const double brightnesses[]{0.0, 0.5, -0.75};
    const double contrasts[]{0.0, 1.0, -1.0};
    const double saturations[]{0.0, -1.0, 1.0};
    for (double exposure : exposures) {
        for (double brightness : brightnesses) {
            for (double contrast : contrasts) {
                for (double saturation : saturations) {
                    Adjustments::Parameters parameters;
                    parameters.exposure = exposure;
                    parameters.brightness = brightness;
                    parameters.contrast = contrast;
                    parameters.saturation = saturation;
                    const QImage expected = Adjustments::apply(image, parameters);
                    const QImage actual = applyRgba64(image, parameters);
                    QCOMPARE(actual.format(), QImage::Format_RGBA64);
                    // Both paths use double math and the same channel rounding;
                    // allow two 16-bit units for identity-path early returns.
                    const int worst = maxChannelDiff16(expected, actual);
                    QVERIFY2(worst <= 2, qPrintable(
                        QStringLiteral("max 16-bit channel diff %1 (e=%2 b=%3 c=%4 s=%5)")
                            .arg(worst).arg(exposure).arg(brightness)
                            .arg(contrast).arg(saturation)));
                }
            }
        }
    }
}

void PreviewMathTest::extendedRgba64Parity()
{
    const QImage image = makeRgba64Image();
    struct Case {
        const char *name;
        Adjustments::Parameters parameters;
    };
    Adjustments::Parameters combined;
    combined.exposure = 1.25;
    combined.brightness = 0.1;
    combined.contrast = 0.4;
    combined.saturation = -0.6;
    combined.highlights = 0.5;
    combined.shadows = -0.4;
    combined.whites = 0.2;
    combined.blacks = -0.3;
    combined.temperature = 0.6;
    combined.tint = -0.5;
    combined.vibrance = 0.7;

    Adjustments::Parameters extreme;
    extreme.exposure = 4.0;
    extreme.brightness = 1.0;
    extreme.contrast = 1.0;
    extreme.saturation = 1.0;
    extreme.highlights = 1.0;
    extreme.shadows = 1.0;
    extreme.whites = 1.0;
    extreme.blacks = 1.0;
    extreme.temperature = 1.0;
    extreme.tint = 1.0;
    extreme.vibrance = 1.0;

    Adjustments::Parameters tonal;
    tonal.highlights = -0.8;
    tonal.shadows = 0.9;
    tonal.whites = -0.6;
    tonal.blacks = 0.7;

    Adjustments::Parameters whiteBalance;
    whiteBalance.temperature = -0.9;
    whiteBalance.tint = 0.85;
    whiteBalance.vibrance = -0.75;

    const Case cases[]{
        {"combined", combined},
        {"extreme", extreme},
        {"tonal-masks", tonal},
        {"white-balance-vibrance", whiteBalance},
    };
    for (const Case &item : cases) {
        const QImage expected = Adjustments::apply(image, item.parameters);
        const QImage actual = applyRgba64(image, item.parameters);
        QCOMPARE(actual.format(), QImage::Format_RGBA64);
        // Both sides use double math and the same final channel rounding. Two
        // 16-bit units leave room for the CPU's RGBA64 conversion and the
        // mirror's straight-alpha evaluation order; a formula mismatch would
        // be far larger.
        const int worst = maxChannelDiff16(expected, actual);
        QVERIFY2(worst <= 2, qPrintable(
            QStringLiteral("%1: max 16-bit channel diff %2")
                .arg(QString::fromLatin1(item.name)).arg(worst)));
    }
}

void PreviewMathTest::alphaPreserved()
{
    const QImage image = makeAlphaEdgeImage();
    Adjustments::Parameters parameters;
    parameters.exposure = 1.5;
    parameters.brightness = 0.3;
    parameters.contrast = -0.4;
    parameters.saturation = 0.8;

    const QImage mirrored = applyRgba8(image, parameters);
    const QImage cpu = Adjustments::apply(image, parameters).convertToFormat(QImage::Format_RGBA8888);
    const QImage source = image.convertToFormat(QImage::Format_RGBA8888);

    for (int y = 0; y < source.height(); ++y) {
        const uchar *from = source.constScanLine(y);
        const uchar *mirror = mirrored.constScanLine(y);
        const uchar *authoritative = cpu.constScanLine(y);
        for (int x = 0; x < source.width(); ++x) {
            QCOMPARE(mirror[x * 4 + 3], from[x * 4 + 3]);
            QCOMPARE(authoritative[x * 4 + 3], from[x * 4 + 3]);
        }
    }
}

void PreviewMathTest::nullImage()
{
    QVERIFY(applyRgba8(QImage(), {}).isNull());
    QVERIFY(applyRgba64(QImage(), {}).isNull());
    QVERIFY(Adjustments::apply(QImage(), {}).isNull());
}

QTEST_GUILESS_MAIN(PreviewMathTest)
#include "tst_previewmath.moc"
