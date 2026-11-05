#include "app/documentcontroller.h"
#include "app/filterpreviews.h"
#include "core/filterpresets.h"
#include <QQuickImageProvider>
#include <QTemporaryDir>
#include <QTest>
#include <QThreadPool>

class FilterPreviewsTest final : public QObject {
    Q_OBJECT
private slots:
    void thumbnailsUseCurrentBaseAndAdjustments();
    void sourceReplacementAndShutdown();
    void parallelBatchIsIdenticalToSerialReference();
};

namespace {
QImage thumbnail(QQuickImageProvider &provider, const QString &preset, quint64 revision)
{
    QSize size;
    return provider.requestImage(preset + '/' + QString::number(revision), &size, {});
}

// The historical serial batch: downsample once, then apply every preset to
// the same small source. Used as the byte-exact reference for the parallel
// implementation.
QHash<QString, QImage> serialReference(const QImage &source,
    NekoPic::Adjustments::Parameters parameters)
{
    const auto small = (source.width() > 192 || source.height() > 144)
        ? source.scaled(192, 144, Qt::KeepAspectRatio, Qt::SmoothTransformation) : source;
    QHash<QString, QImage> images;
    for (const auto &preset : NekoPic::Filters::presetIds()) {
        auto tileParameters = parameters;
        tileParameters.filterPreset = preset;
        images.insert(preset, NekoPic::Adjustments::apply(small, tileParameters)
                                 .convertToFormat(QImage::Format_RGBA8888));
    }
    return images;
}

QImage patternedSource(QImage::Format format)
{
    QImage source(640, 400, format);
    for (int y = 0; y < source.height(); ++y) {
        for (int x = 0; x < source.width(); ++x) {
            source.setPixelColor(x, y,
                QColor((x * 3 + y) % 256, (x + y * 5) % 256, (x * 7 + y * 2) % 256,
                    (x * 11 + y * 13) % 256));
        }
    }
    return source;
}

void compareBatches(const QHash<QString, QImage> &actual,
                    const QHash<QString, QImage> &expected, const char *label)
{
    QCOMPARE(actual.size(), expected.size());
    for (auto it = expected.cbegin(); it != expected.cend(); ++it) {
        QVERIFY2(actual.contains(it.key()), qPrintable(QStringLiteral("%1 missing %2")
            .arg(label, it.key())));
        const auto &image = actual.value(it.key());
        QCOMPARE(image.size(), it.value().size());
        QCOMPARE(image.format(), QImage::Format_RGBA8888);
        QVERIFY2(image == it.value(), qPrintable(QStringLiteral("%1: %2 differs")
            .arg(label, it.key())));
    }
}
}

void FilterPreviewsTest::thumbnailsUseCurrentBaseAndAdjustments()
{
    QTemporaryDir directory;
    QImage source(800, 400, QImage::Format_ARGB32);
    source.fill(QColor(80, 120, 160, 192));
    QVERIFY(source.save(directory.filePath("source.png")));
    DocumentController document;
    FilterPreviews previews(document);
    auto provider = previews.createImageProvider();
    QVERIFY(!previews.ready());
    document.openImage(QUrl::fromLocalFile(directory.filePath("source.png")));
    QTRY_VERIFY(!document.busy());
    QTRY_VERIFY(previews.ready());
    auto revision = previews.revision();
    const auto original = thumbnail(*provider, "none", revision);
    QCOMPARE(original.size(), QSize(192, 96));
    // Smooth scaling may round premultiplied alpha by one 8-bit channel value.
    const auto color = original.pixelColor(0, 0);
    QVERIFY(qAbs(color.red() - 80) <= 1);
    QVERIFY(qAbs(color.green() - 120) <= 1);
    QVERIFY(qAbs(color.blue() - 160) <= 1);
    QCOMPARE(color.alpha(), 192);
    const auto presets = NekoPic::Filters::presetIds();
    QCOMPARE(presets.size(), 13);
    for (const auto &preset : presets) {
        const auto image = thumbnail(*provider, preset, revision);
        QCOMPARE(image.size(), original.size());
        if (preset != QStringLiteral("none"))
            QVERIFY(image != original);
        QCOMPARE(image.pixelColor(0, 0).alpha(), 192);
    }
    const auto mono = thumbnail(*provider, "mono", revision).pixelColor(0, 0);
    QCOMPARE(mono.red(), mono.green());
    QCOMPARE(mono.green(), mono.blue());
    QVERIFY(thumbnail(*provider, "unknown", revision).isNull());

    document.selectFilter("warm");
    QTRY_VERIFY(!document.busy());
    // Filter choice and strength never compound into the preview source.
    document.beginFilterIntensity();
    document.finishFilterIntensity(20);
    QTRY_VERIFY(!document.busy());
    QCOMPARE(previews.revision(), revision);
    QCOMPARE(thumbnail(*provider, "none", revision), original);
    document.beginAdjustment("brightness");
    document.finishAdjustment("brightness", 20);
    QTRY_VERIFY(!document.busy());
    QTRY_VERIFY(previews.ready() && previews.revision() > revision);
    revision = previews.revision();
    const auto brighter = thumbnail(*provider, "none", revision).pixelColor(0, 0);
    QVERIFY(brighter.red() > 120 && brighter.blue() > 200);
    // Crop changes the source and the preview's aspect ratio.
    document.cropImage(QRectF(0, 0, 200, 400));
    QTRY_VERIFY(!document.busy());
    QTRY_VERIFY(previews.ready() && previews.revision() > revision);
    QCOMPARE(thumbnail(*provider, "none", previews.revision()).size(), QSize(72, 144));
    QVERIFY(thumbnail(*provider, "none", revision).isNull());
}

void FilterPreviewsTest::sourceReplacementAndShutdown()
{
    QTemporaryDir directory;
    QImage first(600, 600, QImage::Format_RGB32);
    first.fill(Qt::red);
    QImage second(60, 80, QImage::Format_RGB32);
    second.fill(Qt::blue);
    QVERIFY(first.save(directory.filePath("first.png")));
    QVERIFY(second.save(directory.filePath("second.png")));
    auto document = std::make_unique<DocumentController>();
    auto previews = std::make_unique<FilterPreviews>(*document);
    auto provider = previews->createImageProvider();
    document->openImage(QUrl::fromLocalFile(directory.filePath("first.png")));
    QTRY_VERIFY(!document->busy());
    // Replace a pending source before a thumbnail generation is delivered.
    document->openImage(QUrl::fromLocalFile(directory.filePath("second.png")));
    QTRY_VERIFY(!document->busy());
    QTRY_VERIFY(previews->ready());
    QCOMPARE(thumbnail(*provider, "none", previews->revision()).pixelColor(0, 0), QColor(Qt::blue));
    document.reset();
    QVERIFY(!previews->ready());
    QVERIFY(thumbnail(*provider, "none", previews->revision()).isNull());
    previews.reset();
    // The provider may outlive the coordinator; workers never capture either QObject.
    QVERIFY(QThreadPool::globalInstance()->waitForDone(5000));
}

void FilterPreviewsTest::parallelBatchIsIdenticalToSerialReference()
{
    const auto source = patternedSource(QImage::Format_RGBA8888);
    NekoPic::Adjustments::Parameters basic;
    basic.exposure = 0.6;
    basic.brightness = 0.12;
    basic.contrast = 0.18;
    basic.saturation = 0.25;
    basic.filterIntensity = 0.7;

    const auto reference = serialReference(source, basic);
    QCOMPARE(reference.size(), 13);
    for (int workers : {1, 4, 6}) {
        const auto batch = FilterPreviews::generateBatch(source, basic, workers);
        QCOMPARE(batch.size(), NekoPic::Filters::presetIds().size());
        for (const auto &preset : NekoPic::Filters::presetIds())
            QVERIFY2(batch.contains(preset), qPrintable(preset));
        compareBatches(batch, reference,
            qPrintable(QStringLiteral("basic workers %1").arg(workers)));
    }

    // Repeated fan-out must be deterministic regardless of thread interleaving.
    const auto first = FilterPreviews::generateBatch(source, basic, 6);
    const auto second = FilterPreviews::generateBatch(source, basic, 6);
    QVERIFY(first == second);

    // Extended controls take the per-preset fallback; the float source also
    // skips the shared-base split. Both must still match the serial batches.
    auto extended = basic;
    extended.highlights = 0.3;
    extended.shadows = -0.2;
    extended.vibrance = 0.35;
    extended.hsl[0].saturation = 0.4;
    extended.curves[0].points[2] = 0.63;
    extended.grade[1].saturation = 0.2;
    extended.texture = 0.2;
    compareBatches(FilterPreviews::generateBatch(source, extended, 6),
                   serialReference(source, extended), "extended");

    const auto floatSource = source.convertToFormat(QImage::Format_RGBA32FPx4);
    const auto scaledA = floatSource.scaled(192, 144, Qt::KeepAspectRatio,
                                            Qt::SmoothTransformation);
    const auto scaledB = floatSource.scaled(192, 144, Qt::KeepAspectRatio,
                                            Qt::SmoothTransformation);
    QVERIFY(scaledA == scaledB);
    {
        auto fresh = basic;
        fresh.filterPreset = QStringLiteral("fresh");
        const auto snapshot = scaledA.copy();
        // The historical serial expression chains convertToFormat() onto the
        // apply() temporary. Reproduce it verbatim so the comparison also
        // covers Qt's rvalue conversion path.
        const auto direct = NekoPic::Adjustments::apply(scaledA, fresh)
                                .convertToFormat(QImage::Format_RGBA8888);
        const auto generated = FilterPreviews::generateBatch(scaledA, basic, 1);
        QVERIFY(generated.value(QStringLiteral("fresh")) == direct);
        QVERIFY(scaledA == snapshot); // workers never mutate the preview source.
    }
    compareBatches(FilterPreviews::generateBatch(scaledA, basic, 1),
                   serialReference(scaledB, basic), "float no-scale");
    compareBatches(serialReference(floatSource, basic), serialReference(floatSource, basic),
                   "float reference determinism");
    compareBatches(FilterPreviews::generateBatch(floatSource, basic, 1),
                   FilterPreviews::generateBatch(floatSource, basic, 1),
                   "float generator determinism");
    compareBatches(FilterPreviews::generateBatch(floatSource, basic, 1),
                   serialReference(floatSource, basic), "float workers 1");
    compareBatches(FilterPreviews::generateBatch(floatSource, basic, 6),
                   serialReference(floatSource, basic), "float workers 6");
}

QTEST_MAIN(FilterPreviewsTest)
#include "tst_filterpreviews.moc"
