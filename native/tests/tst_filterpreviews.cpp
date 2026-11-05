#include "app/documentcontroller.h"
#include "app/filterpreviews.h"
#include <QQuickImageProvider>
#include <QTemporaryDir>
#include <QTest>
#include <QThreadPool>

class FilterPreviewsTest final : public QObject {
    Q_OBJECT
private slots:
    void thumbnailsUseCurrentBaseAndAdjustments();
    void sourceReplacementAndShutdown();
};

namespace {
QImage thumbnail(QQuickImageProvider &provider, const QString &preset, quint64 revision)
{
    QSize size;
    return provider.requestImage(preset + '/' + QString::number(revision), &size, {});
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
    for (const auto &preset : {"vivid", "warm", "cool", "mono", "vintage"}) {
        const auto image = thumbnail(*provider, preset, revision);
        QCOMPARE(image.size(), original.size());
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

QTEST_MAIN(FilterPreviewsTest)
#include "tst_filterpreviews.moc"
