#include "app/documentcontroller.h"
#include "core/adjustments.h"

#include <QImage>
#include <QImageReader>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QtTest>

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
};

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

QTEST_MAIN(DocumentControllerTest)
#include "documentcontroller_test.moc"
