#include "app/documentcontroller.h"
#include "core/adjustments.h"
#include "core/filterpresets.h"
#include "document/objectlayer.h"
#include "document/shapeobject.h"

#include <QImage>
#include <QImageReader>
#include <QColorSpace>
#include <QLinearGradient>
#include <QPainter>
#include <QRectF>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QtTest>
#include <limits>
#include <memory>

namespace {
QImage gradientImage(int width, int height)
{
    QImage image(width, height, QImage::Format_RGB32);
    QPainter painter(&image);
    QLinearGradient gradient(0, 0, width, height);
    gradient.setColorAt(0.0, QColor(30, 60, 90));
    gradient.setColorAt(0.5, QColor(140, 110, 80));
    gradient.setColorAt(1.0, QColor(220, 200, 170));
    painter.fillRect(image.rect(), gradient);
    return image;
}

// Independent full-resolution reference: adjustments followed by the same
// rectangle the controller created through addShape().
QImage composeWithRectangle(const QImage &base,
                            const NekoPic::Adjustments::Parameters &parameters,
                            const QRectF &rect,
                            const QPointF &translation = QPointF())
{
    QImage expected = NekoPic::Adjustments::apply(base, parameters);
    NekoPic::Document::ObjectLayer layer;
    auto shape = std::make_unique<NekoPic::Document::ShapeObject>(
        NekoPic::Document::ShapeKind::Rectangle);
    shape->setRect(rect.normalized());
    shape->setCornerRadius(0.0);
    shape->setFillColor(QColor(Qt::red));
    shape->setStrokeColor(QColor(Qt::black));
    shape->setStrokeWidth(2.0);
    shape->setTranslation(translation);
    layer.add(std::move(shape));
    layer.renderOnto(expected);
    return expected;
}

QImage mosaicPattern()
{
    QImage image(24, 16, QImage::Format_RGBA64);
    image.setColorSpace(QColorSpace::DisplayP3);
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            image.setPixelColor(x, y, QColor::fromRgba64(
                1000 + x * 1500, 2000 + y * 1800, 4000 + (x + y) * 700, 40000));
    return image;
}
}

class DocumentControllerTest final : public QObject {
    Q_OBJECT
private slots:
    void opensImageAsynchronously();
    void failedOpenPreservesDocument();
    void savesAsPng();
    void saveAsSelectedFormat_data();
    void saveAsSelectedFormat();
    void appendedExtensionDoesNotOverwrite();
    void openFilterIncludesInstalledFormats();
    void transformsAndHistory();
    void transformsAreAsynchronous();
    void destructionDuringTransformIsSafe();
    void savePointAndHistoryBranch();
    void protectsUnsavedChanges();
    void failedSavePreservesDirtyState();
    void historyRespectsMemoryLimit();
    void adjustmentPreviewCommitsOneHistoryStep();
    void zeroAdjustmentRestoresSource();
    void completedPreviewDoesNotChangeHistory();
    void adjustmentInteractiveEndsOnRelease();
    void adjustmentsPersistAcrossEditsAndHistory();
    void resetAdjustmentsIsOneUndoableEdit();
    void filterPresetCommitsAndPersistsAcrossTransformHistory();
    void filterIntensityPreviewCommitsOnce();
    void selectsEveryRegistryFilterAndRejectsUnknown();
    void resetAdjustmentsRetainsFilter();
    void mosaicEditsAreUndoable_data();
    void mosaicEditsAreUndoable();
    void mosaicPreservesParametersThroughTransforms();
    void invalidMosaicInputsDoNotEdit();
    void interactiveProxyPreviewCommitsFullResolution();
    void objectEditAfterAdjustmentMatchesFullCompose();
    void undoRedoKeepsAdjustedBaseCacheConsistent();
};

void DocumentControllerTest::interactiveProxyPreviewCommitsFullResolution()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    // Just above the 2.5 MP proxy threshold, so interactive previews take the
    // downscaled path while the commit must stay full resolution.
    const QImage source = gradientImage(1600, 1600);
    QVERIFY(source.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 10000);
    const QImage original = controller.image();

    const QRectF rect(100, 120, 220, 180);
    controller.addShape(QStringLiteral("rectangle"), rect, Qt::red, Qt::black, 2.0, 0.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 10000);
    const QImage before = controller.image();

    controller.beginAdjustment(QStringLiteral("clarity"));
    controller.previewAdjustment(QStringLiteral("clarity"), 40.0);
    QTRY_VERIFY_WITH_TIMEOUT(controller.image() != before, 10000);
    // The proxy canvas is scaled back up: image_ stays at full source size and
    // no history is written for transient previews.
    QCOMPARE(controller.image().size(), source.size());
    QVERIFY(controller.busy());

    const QImage firstPreview = controller.image();
    controller.previewAdjustment(QStringLiteral("clarity"), 55.0);
    QTRY_VERIFY_WITH_TIMEOUT(controller.image() != firstPreview, 10000);
    QCOMPARE(controller.image().size(), source.size());

    controller.finishAdjustment(QStringLiteral("clarity"), 40.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 10000);

    // Finishing must recompute at full resolution and be bit-identical to a
    // direct Adjustments::apply() plus object compositing.
    NekoPic::Adjustments::Parameters parameters;
    parameters.clarity = 0.4;
    const QImage expected = composeWithRectangle(controller.baseImage(), parameters, rect);
    QCOMPARE(controller.image(), expected);
    QCOMPARE(controller.image().size(), source.size());
    QVERIFY(controller.canUndo());
    // Exactly one history entry for the commit; the previews added none.
    controller.undo();
    QCOMPARE(controller.image(), before);
    controller.undo();
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.canUndo());
}

void DocumentControllerTest::objectEditAfterAdjustmentMatchesFullCompose()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = gradientImage(96, 64);
    QVERIFY(source.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);

    const QRectF rect(12, 10, 30, 22);
    controller.addShape(QStringLiteral("rectangle"), rect, Qt::red, Qt::black, 2.0, 0.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto ids = controller.objectIds();
    QCOMPARE(ids.size(), 1);
    const quint64 shape = ids.first().toULongLong();

    controller.beginAdjustment(QStringLiteral("brightness"));
    controller.finishAdjustment(QStringLiteral("brightness"), 40.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);

    const QImage base = controller.baseImage();
    NekoPic::Adjustments::Parameters parameters;
    parameters.brightness = 0.4;
    // Sanity: the committed adjustment matches a full compose.
    QCOMPARE(controller.image(), composeWithRectangle(base, parameters, rect));

    // First edit after the adjustment fills the adapted-base cache.
    controller.moveObject(shape, 4.0, 6.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(),
             composeWithRectangle(base, parameters, rect, QPointF(4.0, 6.0)));

    // Subsequent edit reuses the cache; pixels must still match a full compose.
    controller.moveObject(shape, -2.0, 3.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(),
             composeWithRectangle(base, parameters, rect, QPointF(2.0, 9.0)));

    // Hiding the only object exposes the cached adjusted base exactly.
    QVERIFY(controller.setObjectVisible(shape, false));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(base, parameters));

    // A parameter change invalidates the cache; the next object edit must use
    // the new adjustment values.
    controller.beginAdjustment(QStringLiteral("contrast"));
    controller.finishAdjustment(QStringLiteral("contrast"), 25.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    parameters.contrast = 0.25;
    QVERIFY(controller.setObjectVisible(shape, true));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(),
             composeWithRectangle(base, parameters, rect, QPointF(2.0, 9.0)));
}

void DocumentControllerTest::undoRedoKeepsAdjustedBaseCacheConsistent()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QImage source = gradientImage(96, 64);
    QVERIFY(source.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);

    const QRectF rect(12, 10, 30, 22);
    controller.addShape(QStringLiteral("rectangle"), rect, Qt::red, Qt::black, 2.0, 0.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const quint64 shape = controller.objectIds().first().toULongLong();
    const QImage unadjusted = controller.image();

    controller.beginAdjustment(QStringLiteral("brightness"));
    controller.finishAdjustment(QStringLiteral("brightness"), 40.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const QImage adjusted = controller.image();

    controller.moveObject(shape, 3.0, 2.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const QImage movedOnce = controller.image();

    controller.moveObject(shape, 1.0, 1.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const QImage movedTwice = controller.image();

    // Walk the cached object edits backwards and forwards.
    controller.undo();
    QCOMPARE(controller.image(), movedOnce);
    controller.undo();
    QCOMPARE(controller.image(), adjusted);
    controller.redo();
    QCOMPARE(controller.image(), movedOnce);
    controller.redo();
    QCOMPARE(controller.image(), movedTwice);
    controller.undo();
    QCOMPARE(controller.image(), movedOnce);
    controller.undo();
    QCOMPARE(controller.image(), adjusted);

    // Undo the adjustment itself: the restored base/parameters must not reuse
    // the adjusted pixels.
    controller.undo();
    QCOMPARE(controller.image(), unadjusted);
    QCOMPARE(controller.adjustmentValues().value(QStringLiteral("brightness")).toDouble(), 0.0);

    controller.moveObject(shape, 0.0, 5.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const NekoPic::Adjustments::Parameters defaults;
    const QImage expected =
        composeWithRectangle(controller.baseImage(), defaults, rect, QPointF(0.0, 5.0));
    QCOMPARE(controller.image(), expected);

    controller.undo();
    QCOMPARE(controller.image(), unadjusted);
    controller.redo();
    QCOMPARE(controller.image(), expected);
}

void DocumentControllerTest::mosaicEditsAreUndoable_data()
{
    QTest::addColumn<bool>("stroke");
    QTest::newRow("rectangle") << false;
    QTest::newRow("stroke") << true;
}

void DocumentControllerTest::mosaicEditsAreUndoable()
{
    QFETCH(bool, stroke);
    QTemporaryDir dir;
    QVERIFY(mosaicPattern().save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto original = controller.image();
    if (stroke) {
        const QVariantList points{QPointF(6, 6), QPointF(12, 6)};
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicStroke",
            Q_ARG(QVariantList, points), Q_ARG(double, 6.0), Q_ARG(int, 4)));
    } else {
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicRectangle",
            Q_ARG(QRectF, QRectF(4, 4, 12, 8)), Q_ARG(int, 4)));
    }
    QVERIFY(controller.busy());
    controller.mosaicRectangle(QRectF(0, 0, 24, 16), 8);
    controller.flipHorizontal(); // Busy edits must be ignored.
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto edited = controller.image();
    QVERIFY(edited != original);
    QVERIFY(edited.pixelColor(6, 6) != original.pixelColor(6, 6));
    QCOMPARE(edited.pixelColor(0, 0), original.pixelColor(0, 0));
    QCOMPARE(edited.pixelColor(23, 15), original.pixelColor(23, 15));
    QCOMPARE(edited.format(), QImage::Format_RGBA64);
    QCOMPARE(edited.colorSpace(), original.colorSpace());
    QCOMPARE(edited.pixelColor(6, 6).rgba64().alpha(), original.pixelColor(6, 6).rgba64().alpha());
    QVERIFY(controller.dirty());
    controller.undo();
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
    controller.redo();
    QCOMPARE(controller.image(), edited);
}

void DocumentControllerTest::mosaicPreservesParametersThroughTransforms()
{
    QTemporaryDir dir;
    QVERIFY(mosaicPattern().save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.selectFilter("warm");
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginFilterIntensity();
    controller.finishFilterIntensity(35);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 20);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto adjustedBeforeMosaic = controller.image();
    QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicRectangle",
        Q_ARG(QRectF, QRectF(4, 4, 12, 8)), Q_ARG(int, 4)));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto adjustedMosaic = controller.image();
    const auto mosaicBase = controller.baseImage();
    const auto parameters = controller.adjustmentParameters();
    QCOMPARE(parameters.brightness, 0.2);
    QCOMPARE(parameters.filterPreset, QStringLiteral("warm"));
    QCOMPARE(controller.filterIntensity(), 35.0);
    QCOMPARE(adjustedMosaic.pixelColor(0, 0), adjustedBeforeMosaic.pixelColor(0, 0));
    QCOMPARE(adjustedMosaic, NekoPic::Adjustments::apply(mosaicBase, parameters));
    controller.resetAdjustments();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.filterPreset(), QStringLiteral("warm"));
    QVERIFY(controller.image() != adjustedMosaic);
    controller.undo();
    QCOMPARE(controller.image(), adjustedMosaic);
    QCOMPARE(controller.adjustmentValues().value("brightness").toDouble(), 20.0);
    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto rotated = controller.image();
    QCOMPARE(rotated, adjustedMosaic.transformed(QTransform().rotate(90)));
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(controller.image() != rotated);
    QCOMPARE(controller.filterPreset(), QStringLiteral("warm"));
    auto resetParameters = parameters;
    resetParameters.brightness = 0;
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(
        mosaicBase.transformed(QTransform().rotate(90)), resetParameters));
    controller.undo();
    QCOMPARE(controller.image(), rotated);
}

void DocumentControllerTest::invalidMosaicInputsDoNotEdit()
{
    QTemporaryDir dir;
    QVERIFY(mosaicPattern().save(dir.filePath("source.png")));
    DocumentController controller;
    controller.mosaicRectangle(QRectF(0, 0, 8, 8), 4);
    controller.mosaicStroke({QPointF(4, 4)}, 6, 4);
    QVERIFY(!controller.busy());
    QVERIFY(!controller.hasImage());
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto original = controller.image();
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const QList<QRectF> rectangles{QRectF(), QRectF(100, 100, 4, 4),
        QRectF(nan, 0, 3, 3), QRectF(0, 0, 1e100, 1e100)};
    for (const auto &area : rectangles) {
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicRectangle",
            Q_ARG(QRectF, area), Q_ARG(int, 4)));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    }
    const QList<QVariantList> strokes{{}, {QStringLiteral("invalid")},
        {QPointF(4, 4), QStringLiteral("invalid")}, {QPointF(1e100, 0)},
        {QPointF(nan, 0)}, {QPointF(100, 100)}, QVariantList(4097, QPointF(4, 4))};
    for (const auto &points : strokes) {
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicStroke",
            Q_ARG(QVariantList, points), Q_ARG(double, 6.0), Q_ARG(int, 4)));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    }
    for (const int block : {0, 1, -1, std::numeric_limits<int>::max()}) {
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicRectangle",
            Q_ARG(QRectF, QRectF(0, 0, 8, 8)), Q_ARG(int, block)));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    }
    for (const double diameter : {0.0, -1.0, nan, 1e100}) {
        const QVariantList points{QPointF(4, 4)};
        QVERIFY(QMetaObject::invokeMethod(&controller, "mosaicStroke",
            Q_ARG(QVariantList, points), Q_ARG(double, diameter), Q_ARG(int, 4)));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    }
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
}

void DocumentControllerTest::resetAdjustmentsIsOneUndoableEdit()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(QColor(70, 100, 130));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 40);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("contrast");
    controller.finishAdjustment("contrast", 25);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto adjusted = controller.image();
    QVERIFY(QMetaObject::invokeMethod(&controller, "resetAdjustments"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.property("adjustmentValues").toMap().value("brightness").toDouble(), 0.0);
    controller.undo();
    QCOMPARE(controller.image(), adjusted);
    QCOMPARE(controller.property("adjustmentValues").toMap().value("contrast").toDouble(), 25.0);
    controller.redo();
    QCOMPARE(controller.image(), original);
}

void DocumentControllerTest::filterPresetCommitsAndPersistsAcrossTransformHistory()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGBA64);
    original.fill(QColor::fromRgba64(50000, 20000, 10000, 30000));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.selectFilter("mono");
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.property("filterPreset").toString(), QStringLiteral("mono"));
    QVERIFY(controller.canUndo());
    const auto filtered = controller.image();
    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.property("filterPreset").toString(), QStringLiteral("mono"));
    controller.undo();
    QCOMPARE(controller.image(), filtered);
    controller.undo();
    QCOMPARE(controller.image(), original);
    QCOMPARE(controller.property("filterPreset").toString(), QStringLiteral("none"));
    controller.redo();
    QCOMPARE(controller.property("filterPreset").toString(), QStringLiteral("mono"));
}

void DocumentControllerTest::filterIntensityPreviewCommitsOnce()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGBA64);
    original.fill(QColor::fromRgba64(50000, 20000, 10000, 30000));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.selectFilter("vivid");
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto full = controller.image();
    controller.beginFilterIntensity();
    QVERIFY(controller.filterIntensityInteractive());
    QVERIFY(!controller.adjustmentInteractive());
    controller.previewFilterIntensity(50.0);
    QTRY_VERIFY_WITH_TIMEOUT(controller.image() != full, 5000);
    QVERIFY(controller.canUndo());
    controller.finishFilterIntensity(0.0);
    QVERIFY(!controller.filterIntensityInteractive());
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.property("filterIntensity").toDouble(), 0.0);
    QVERIFY(controller.canUndo());
    controller.undo();
    QCOMPARE(controller.property("filterIntensity").toDouble(), 100.0);
    QCOMPARE(controller.image(), full);
    controller.undo();
    QVERIFY(!controller.canUndo());
    QCOMPARE(controller.image(), original);
}

void DocumentControllerTest::resetAdjustmentsRetainsFilter()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGBA64);
    original.fill(QColor::fromRgba64(50000, 20000, 10000, 30000));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.selectFilter("warm");
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto filtered = controller.image();
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 20.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto adjusted = controller.image();
    QVERIFY(adjusted != filtered);
    controller.resetAdjustments();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.filterPreset(), QStringLiteral("warm"));
    QCOMPARE(controller.image(), filtered);
    QCOMPARE(controller.adjustmentValues().value("brightness").toDouble(), 0.0);
    controller.undo();
    QCOMPARE(controller.image(), adjusted);
    QCOMPARE(controller.filterPreset(), QStringLiteral("warm"));
}

void DocumentControllerTest::adjustmentsPersistAcrossEditsAndHistory()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(QColor(70, 100, 130));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 40);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("contrast");
    controller.finishAdjustment("contrast", 25);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    NekoPic::Adjustments::Parameters p;
    p.brightness = 0.4;
    p.contrast = 0.25;
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(original, p));
    QCOMPARE(controller.property("adjustmentValues").toMap().value("brightness").toDouble(), 40.0);
    controller.undo();
    QCOMPARE(controller.property("adjustmentValues").toMap().value("contrast").toDouble(), 0.0);
    controller.redo();
    QCOMPARE(controller.property("adjustmentValues").toMap().value("contrast").toDouble(), 25.0);
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    p.brightness = 0;
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(original, p));
    controller.undo();
    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("brightness");
    controller.finishAdjustment("brightness", 0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(original.transformed(QTransform().rotate(90)), p));
}

void DocumentControllerTest::adjustmentInteractiveEndsOnRelease()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(Qt::red);
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    const auto propertyIndex = controller.metaObject()->indexOfProperty("adjustmentInteractive");
    QVERIFY(propertyIndex >= 0);
    QSignalSpy spy(&controller, SIGNAL(adjustmentInteractiveChanged()));
    QVERIFY(spy.isValid());
    controller.beginAdjustment("brightness");
    QVERIFY(controller.property("adjustmentInteractive").toBool());
    QCOMPARE(spy.size(), 1);
    controller.previewAdjustment("brightness", 50.0);
    controller.finishAdjustment("brightness", 50.0);
    QVERIFY(!controller.property("adjustmentInteractive").toBool());
    QVERIFY(controller.busy());
    QCOMPARE(spy.size(), 2);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(spy.size(), 2);
}

void DocumentControllerTest::completedPreviewDoesNotChangeHistory()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(QColor(70, 100, 130));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.beginAdjustment("exposure");
    controller.previewAdjustment("exposure", 50.0);
    QTRY_VERIFY_WITH_TIMEOUT(controller.image() != original, 5000);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
    controller.finishAdjustment("exposure", 0.0);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
}

void DocumentControllerTest::adjustmentPreviewCommitsOneHistoryStep()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(QColor(70, 100, 130));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(QMetaObject::invokeMethod(&controller, "beginAdjustment", Q_ARG(QString, "brightness")));
    QVERIFY(controller.property("adjusting").toBool());
    QVERIFY(controller.busy());
    QVERIFY(QMetaObject::invokeMethod(&controller, "previewAdjustment", Q_ARG(QString, "brightness"), Q_ARG(double, 30.0)));
    QVERIFY(QMetaObject::invokeMethod(&controller, "previewAdjustment", Q_ARG(QString, "brightness"), Q_ARG(double, 60.0)));
    controller.saveAs(QUrl::fromLocalFile(dir.filePath("preview.png")), "png");
    controller.openImageDiscardingChanges(QUrl::fromLocalFile(dir.filePath("source.png")));
    QVERIFY(!QFileInfo::exists(dir.filePath("preview.png")));
    QVERIFY(QMetaObject::invokeMethod(&controller, "finishAdjustment", Q_ARG(QString, "brightness"), Q_ARG(double, 60.0)));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(!controller.property("adjusting").toBool());
    NekoPic::Adjustments::Parameters p;
    p.brightness = 0.6;
    QCOMPARE(controller.image(), NekoPic::Adjustments::apply(original, p));
    QVERIFY(controller.dirty());
    QVERIFY(controller.canUndo());
    controller.undo();
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.canUndo());
    QVERIFY(!controller.dirty());
}

void DocumentControllerTest::zeroAdjustmentRestoresSource()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(QColor(70, 100, 130));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(QMetaObject::invokeMethod(&controller, "beginAdjustment", Q_ARG(QString, "brightness")));
    QVERIFY(QMetaObject::invokeMethod(&controller, "previewAdjustment", Q_ARG(QString, "brightness"), Q_ARG(double, 70.0)));
    QVERIFY(QMetaObject::invokeMethod(&controller, "finishAdjustment", Q_ARG(QString, "brightness"), Q_ARG(double, 0.0)));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.canUndo());
    QVERIFY(!controller.dirty());
}

void DocumentControllerTest::destructionDuringTransformIsSafe()
{
    QTemporaryDir dir;
    QImage source(2048, 2048, QImage::Format_RGB32);
    source.fill(Qt::red);
    QVERIFY(source.save(dir.filePath("source.png")));
    {
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(controller.hasImage());
        controller.rotateClockwise();
        QVERIFY(controller.busy());
    }
    QVERIFY(QThreadPool::globalInstance()->waitForDone(5000));
    QCoreApplication::processEvents();
}

void DocumentControllerTest::transformsAreAsynchronous()
{
    QTemporaryDir dir;
    QImage original(32, 24, QImage::Format_RGB32);
    original.fill(Qt::red);
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QSignalSpy busySpy(&controller, &DocumentController::busyChanged);
    controller.rotateClockwise();
    QVERIFY(controller.busy());
    QCOMPARE(controller.image().size(), original.size());
    controller.flipHorizontal();
    controller.undo();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(busySpy.size(), 2);
    QCOMPARE(controller.image().size(), QSize(24, 32));
    QVERIFY(controller.canUndo());
    controller.undo();
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.canUndo());
}

void DocumentControllerTest::historyRespectsMemoryLimit()
{
    QTemporaryDir dir;
    QImage source(8192, 4096, QImage::Format_RGB32);
    source.fill(Qt::red);
    QVERIFY(source.save(dir.filePath("large.png")));
    source = {};
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("large.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 30000);
    QVERIFY2(controller.hasImage(), qPrintable(controller.errorMessage()));
    controller.flipHorizontal();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 30000);
    controller.flipVertical();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 30000);
    controller.flipHorizontal();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 30000);
    QVERIFY(controller.canUndo());
    controller.undo();
    QVERIFY(controller.canUndo());
    controller.undo();
    QVERIFY(!controller.canUndo());
    QVERIFY(controller.dirty());
}

void DocumentControllerTest::failedSavePreservesDirtyState()
{
    QTemporaryDir dir;
    QImage source(2, 3, QImage::Format_RGB32);
    source.fill(Qt::red);
    QVERIFY(source.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.saveAs(QUrl::fromLocalFile(dir.filePath("missing/result.png")), QStringLiteral("png"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(!controller.errorMessage().isEmpty());
    QVERIFY(controller.dirty());
    QCOMPARE(controller.fileName(), QStringLiteral("source.png"));
    QVERIFY(controller.canUndo());
}

void DocumentControllerTest::protectsUnsavedChanges()
{
    QTemporaryDir dir;
    QImage first(2, 3, QImage::Format_RGB32);
    first.fill(Qt::red);
    QVERIFY(first.save(dir.filePath("first.png")));
    QImage second(4, 5, QImage::Format_RGB32);
    second.fill(Qt::blue);
    QVERIFY(second.save(dir.filePath("second.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("first.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.openImage(QUrl::fromLocalFile(dir.filePath("second.png")));
    QVERIFY(!controller.busy());
    QVERIFY(!controller.errorMessage().isEmpty());
    QCOMPARE(controller.image().size(), QSize(3, 2));
    controller.openImageDiscardingChanges(QUrl::fromLocalFile(dir.filePath("missing.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(controller.dirty());
    QCOMPARE(controller.image().size(), QSize(3, 2));
    controller.openImageDiscardingChanges(QUrl::fromLocalFile(dir.filePath("second.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(!controller.dirty());
    QVERIFY(!controller.canUndo());
    QCOMPARE(controller.image().size(), QSize(4, 5));
}

void DocumentControllerTest::transformsAndHistory()
{
    QTemporaryDir dir;
    QImage original(2, 3, QImage::Format_RGB32);
    original.fill(Qt::black);
    original.setPixelColor(0, 0, Qt::red);
    original.setPixelColor(1, 0, Qt::green);
    original.setPixelColor(0, 2, Qt::blue);
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(QMetaObject::invokeMethod(&controller, "rotateClockwise"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image().size(), QSize(3, 2));
    QCOMPARE(controller.image().pixelColor(2, 0), QColor(Qt::red));
    QCOMPARE(controller.image().pixelColor(0, 0), QColor(Qt::blue));
    QVERIFY(controller.dirty());
    QVERIFY(controller.property("canUndo").toBool());
    QVERIFY(QMetaObject::invokeMethod(&controller, "flipHorizontal"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image().pixelColor(0, 0), QColor(Qt::red));
    QVERIFY(QMetaObject::invokeMethod(&controller, "undo"));
    QCOMPARE(controller.image().pixelColor(2, 0), QColor(Qt::red));
    QVERIFY(QMetaObject::invokeMethod(&controller, "undo"));
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.dirty());
    QVERIFY(controller.property("canRedo").toBool());
    QVERIFY(QMetaObject::invokeMethod(&controller, "redo"));
    QVERIFY(controller.dirty());
    QVERIFY(QMetaObject::invokeMethod(&controller, "rotateCounterClockwise"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image(), original);
    QVERIFY(!controller.property("canRedo").toBool());
    QVERIFY(QMetaObject::invokeMethod(&controller, "flipVertical"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.image().pixelColor(0, 0), QColor(Qt::blue));
}

void DocumentControllerTest::savePointAndHistoryBranch()
{
    QTemporaryDir dir;
    QImage original(2, 3, QImage::Format_RGB32);
    original.fill(Qt::red);
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(QMetaObject::invokeMethod(&controller, "rotateClockwise"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.saveAs(QUrl::fromLocalFile(dir.filePath("saved.png")), QStringLiteral("png"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
    QVERIFY(!controller.dirty());
    QVERIFY(QMetaObject::invokeMethod(&controller, "undo"));
    QVERIFY(controller.dirty());
    QVERIFY(QMetaObject::invokeMethod(&controller, "redo"));
    QVERIFY(!controller.dirty());
    QVERIFY(QMetaObject::invokeMethod(&controller, "undo"));
    QVERIFY(QMetaObject::invokeMethod(&controller, "flipHorizontal"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(controller.dirty());
    QVERIFY(!controller.property("canRedo").toBool());
    controller.saveImage();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
    QVERIFY(!controller.dirty());
    QCOMPARE(QImage(dir.filePath("saved.png")).size(), QSize(2, 3));
}

void DocumentControllerTest::openFilterIncludesInstalledFormats()
{
    DocumentController controller;
    const auto patterns = controller.property("readableImagePatterns").toStringList();
    QVERIFY(!patterns.isEmpty());
    for (const auto &format : QImageReader::supportedImageFormats()) {
        const auto extension = QString::fromLatin1(format).toLower();
        QVERIFY2(patterns.contains(QStringLiteral("*.") + extension), format.constData());
        QVERIFY2(patterns.contains(QStringLiteral("*.") + extension.toUpper()), format.constData());
    }
}

void DocumentControllerTest::opensImageAsynchronously()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(8, 6, QImage::Format_ARGB32);
    image.fill(QColor(25, 90, 160, 80));
    const auto path = dir.filePath("source.png");
    QVERIFY(image.save(path));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(path));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(controller.hasImage());
    QCOMPARE(controller.fileName(), QStringLiteral("source.png"));
    QCOMPARE(controller.imageWidth(), 8);
    QCOMPARE(controller.imageHeight(), 6);
    QCOMPARE(controller.image().pixelColor(0, 0), image.pixelColor(0, 0));
}

void DocumentControllerTest::failedOpenPreservesDocument()
{
    QTemporaryDir dir;
    QImage image(2, 2, QImage::Format_RGB32);
    image.fill(Qt::red);
    const auto path = dir.filePath("source.png");
    QVERIFY(image.save(path));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(path));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.openImage(QUrl::fromLocalFile(dir.filePath("missing.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(!controller.errorMessage().isEmpty());
    QCOMPARE(controller.fileName(), QStringLiteral("source.png"));
    QVERIFY(controller.hasImage());
}

void DocumentControllerTest::savesAsPng()
{
    QTemporaryDir dir;
    QImage image(2, 3, QImage::Format_RGB32);
    image.fill(Qt::green);
    const auto path = dir.filePath("source.png");
    const auto target = dir.filePath("result.png");
    QVERIFY(image.save(path));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(path));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.saveAs(QUrl::fromLocalFile(target), QStringLiteral("png"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
    QCOMPARE(QImage(target).pixelColor(0, 0), QColor(Qt::green));
    QCOMPARE(controller.fileName(), QStringLiteral("result.png"));
}

void DocumentControllerTest::saveAsSelectedFormat_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<QString>("format");
    QTest::addColumn<QString>("expectedName");
    QTest::addColumn<bool>("success");
    QTest::newRow("png without extension") << "result" << "png" << "result.png" << true;
    QTest::newRow("jpeg without extension") << "result" << "jpeg" << "result.jpg" << true;
    QTest::newRow("jpeg alternate extension") << "result.JPEG" << "jpeg" << "result.JPEG" << true;
    QTest::newRow("conflicting extension") << "result.png" << "jpeg" << "result.png" << false;
    QTest::newRow("unsupported extension") << "result.webp" << "png" << "result.webp" << false;
}

void DocumentControllerTest::saveAsSelectedFormat()
{
    QFETCH(QString, name);
    QFETCH(QString, format);
    QFETCH(QString, expectedName);
    QFETCH(bool, success);
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage image(2, 3, QImage::Format_RGB32);
    image.fill(Qt::green);
    const auto source = dir.filePath("source.png");
    QVERIFY(image.save(source));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(source));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.saveAs(QUrl::fromLocalFile(dir.filePath(name)), format);
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.errorMessage().isEmpty(), success);
    QCOMPARE(QFileInfo::exists(dir.filePath(expectedName)), success);
    if (success) QCOMPARE(controller.fileName(), expectedName);
    else QCOMPARE(controller.fileName(), QStringLiteral("source.png"));
}

void DocumentControllerTest::appendedExtensionDoesNotOverwrite()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QImage source(2, 2, QImage::Format_RGB32);
    source.fill(Qt::red);
    QVERIFY(source.save(dir.filePath("source.png")));
    QImage existing(2, 2, QImage::Format_RGB32);
    existing.fill(Qt::blue);
    QVERIFY(existing.save(dir.filePath("result.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    controller.saveAs(QUrl::fromLocalFile(dir.filePath("result")), QStringLiteral("png"));
    QVERIFY(!controller.errorMessage().isEmpty());
    QCOMPARE(QImage(dir.filePath("result.png")).pixelColor(0, 0), QColor(Qt::blue));
}

void DocumentControllerTest::selectsEveryRegistryFilterAndRejectsUnknown()
{
    QTemporaryDir dir;
    QImage original(16, 12, QImage::Format_RGBA64);
    original.fill(QColor::fromRgba64(40000, 20000, 10000, 65535));
    QVERIFY(original.save(dir.filePath("source.png")));
    DocumentController controller;
    controller.openImage(QUrl::fromLocalFile(dir.filePath("source.png")));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);

    const auto presets = NekoPic::Filters::presetIds();
    QCOMPARE(presets.size(), 13);
    for (const auto &preset : presets) {
        controller.selectFilter(preset);
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QCOMPARE(controller.filterPreset(), preset);
    }

    // Unknown ids are rejected without changing the committed look.
    controller.selectFilter(QStringLiteral("neko"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.filterPreset(), presets.last());
    controller.selectFilter(QString());
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QCOMPARE(controller.filterPreset(), presets.last());
}

QTEST_MAIN(DocumentControllerTest)
#include "documentcontroller_test.moc"
