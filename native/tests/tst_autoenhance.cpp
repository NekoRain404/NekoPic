#include "core/autoenhance.h"
#include "core/histogram.h"

#include <QtTest>

using NekoPic::AutoEnhance::suggest;
using NekoPic::Histogram::compute;

namespace {
QImage solid(int value)
{
    QImage image(32, 32, QImage::Format_RGBA8888);
    image.fill(QColor(value, value, value));
    return image;
}
}

class AutoEnhanceTest final : public QObject {
    Q_OBJECT
private slots:
    void emptyHistogramIsNoOp()
    {
        QVERIFY(suggest({}).isNoOp());
    }

    void darkImageLiftsExposure()
    {
        const auto suggestion = suggest(compute(solid(40)));
        QVERIFY(suggestion.exposure > 0);
    }

    void brightImageLowersExposure()
    {
        const auto suggestion = suggest(compute(solid(230)));
        QVERIFY(suggestion.exposure < 0);
    }

    void flatImageAddsContrastAndSaturation()
    {
        const auto suggestion = suggest(compute(solid(128)));
        QVERIFY(suggestion.contrast > 0);
        QVERIFY(suggestion.saturation > 0);
    }

    void valuesStayInUiRange()
    {
        for (int value : {0, 32, 64, 128, 192, 224, 255}) {
            const auto suggestion = suggest(compute(solid(value)));
            QVERIFY(std::abs(suggestion.exposure) <= 40.0);
            QVERIFY(std::abs(suggestion.contrast) <= 30.0);
            QVERIFY(std::abs(suggestion.saturation) <= 20.0);
            QVERIFY(std::abs(suggestion.blacks) <= 20.0);
            QVERIFY(std::abs(suggestion.whites) <= 20.0);
        }
    }
};

QTEST_MAIN(AutoEnhanceTest)
#include "tst_autoenhance.moc"
