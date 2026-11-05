#include "app/documentcontroller.h"
#include "app/recoverystore.h"

#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QtTest>

namespace {

QImage sampleImage(int width = 32, int height = 24)
{
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(QColor(12, 34, 56));
    image.setPixelColor(3, 4, QColor(200, 10, 30));
    image.setPixelColor(width - 1, height - 1, QColor(0, 220, 140));
    return image;
}

QString manifestFile(const QString &directory)
{
    return directory + QStringLiteral("/manifest.json");
}

QString snapshotFile(const QString &directory)
{
    return directory + QStringLiteral("/snapshot.png");
}

bool writeManifestObject(const QString &directory, const QJsonObject &object)
{
    QFile file(manifestFile(directory));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    return file.write(QJsonDocument(object).toJson(QJsonDocument::Compact)) > 0;
}

} // namespace

class RecoveryStoreTest final : public QObject {
    Q_OBJECT

private slots:
    void roundTripPreservesMetadataAndPixels();
    void rejectsCorruptManifest();
    void rejectsUnsupportedManifestVersion();
    void rejectsSnapshotWithWrongHash();
    void cleanSaveRemovesSnapshot();
    void cleanExitRemovesSnapshot();
    void restoreMarksDocumentDirtyAndPreservesPixels();
    void restoreRejectsCorruptSnapshotWithoutError();
};

void RecoveryStoreTest::roundTripPreservesMetadataAndPixels()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));

    QImage image = sampleImage();
    const QDateTime capturedAt =
        QDateTime::fromString(QStringLiteral("2026-11-05T08:30:15.250Z"),
                              Qt::ISODateWithMs);
    {
        RecoveryStore store(nullptr, recovery);
        QVERIFY(!store.hasRecovery());
        QVERIFY(store.writeSnapshot(image, QStringLiteral("/photos/vacation.jpg"),
                                    QStringLiteral("vacation.jpg"), capturedAt,
                                    QStringLiteral("9.9.9")));
        QVERIFY(store.hasRecovery());
        QCOMPARE(store.sourceName(), QStringLiteral("vacation.jpg"));
        QCOMPARE(store.sourcePath(), QStringLiteral("/photos/vacation.jpg"));
        QCOMPARE(store.imageWidth(), image.width());
        QCOMPARE(store.imageHeight(), image.height());
        QCOMPARE(store.imageSizeText(),
                 QStringLiteral("%1 × %2 px").arg(image.width()).arg(image.height()));
        QCOMPARE(store.capturedAtIso(), QStringLiteral("2026-11-05T08:30:15.250Z"));
        QVERIFY(store.flattened());

        QImage loaded;
        QVERIFY(store.readSnapshot(&loaded));
        QCOMPARE(loaded.size(), image.size());
        QCOMPARE(loaded.pixelColor(3, 4), QColor(200, 10, 30));
        QCOMPARE(loaded.pixelColor(image.width() - 1, image.height() - 1),
                 QColor(0, 220, 140));
    }

    // A second instance scans the same directory and reports the snapshot.
    RecoveryStore reopened(nullptr, recovery);
    QVERIFY(reopened.hasRecovery());
    QCOMPARE(reopened.sourceName(), QStringLiteral("vacation.jpg"));
    QVERIFY(QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(QFileInfo::exists(snapshotFile(recovery)));
}

void RecoveryStoreTest::rejectsCorruptManifest()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));
    {
        RecoveryStore store(nullptr, recovery);
        QVERIFY(store.writeSnapshot(sampleImage(), QStringLiteral("/tmp/a.png"),
                                    QStringLiteral("a.png"),
                                    QDateTime::currentDateTimeUtc(),
                                    QStringLiteral("0.1.0")));
    }

    QFile file(manifestFile(recovery));
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QVERIFY(file.write("{ this is not json") > 0);
    file.close();

    RecoveryStore store(nullptr, recovery);
    QVERIFY(!store.hasRecovery());
    // Corrupt snapshots are cleaned up rather than left to grow disk use.
    QVERIFY(!QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(!QFileInfo::exists(snapshotFile(recovery)));
}

void RecoveryStoreTest::rejectsUnsupportedManifestVersion()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));
    RecoveryStore writer(nullptr, recovery);
    QVERIFY(writer.writeSnapshot(sampleImage(), QStringLiteral("/tmp/a.png"),
                                 QStringLiteral("a.png"),
                                 QDateTime::currentDateTimeUtc(),
                                 QStringLiteral("0.1.0")));

    QFile file(manifestFile(recovery));
    QVERIFY(file.open(QIODevice::ReadOnly));
    auto object = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    object.insert(QStringLiteral("version"), 99);
    QVERIFY(writeManifestObject(recovery, object));

    RecoveryStore store(nullptr, recovery);
    QVERIFY(!store.hasRecovery());
    QVERIFY(!QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(!QFileInfo::exists(snapshotFile(recovery)));
}

void RecoveryStoreTest::rejectsSnapshotWithWrongHash()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));
    RecoveryStore writer(nullptr, recovery);
    QVERIFY(writer.writeSnapshot(sampleImage(), QStringLiteral("/tmp/a.png"),
                                 QStringLiteral("a.png"),
                                 QDateTime::currentDateTimeUtc(),
                                 QStringLiteral("0.1.0")));

    // Same dimensions, different pixels: the manifest still parses and the
    // PNG header matches, so only the content hash can reject it.
    QImage replacement = sampleImage();
    replacement.fill(QColor(250, 250, 250));
    replacement.setPixelColor(3, 4, QColor(1, 2, 3));
    QVERIFY(replacement.save(snapshotFile(recovery), "PNG"));

    RecoveryStore store(nullptr, recovery);
    QVERIFY(!store.hasRecovery());
    QImage loaded;
    QVERIFY(!store.readSnapshot(&loaded));
    QVERIFY(!QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(!QFileInfo::exists(snapshotFile(recovery)));
}

void RecoveryStoreTest::cleanSaveRemovesSnapshot()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString source = dir.filePath(QStringLiteral("source.png"));
    QVERIFY(sampleImage(64, 48).save(source, "PNG"));

    DocumentController controller;
    RecoveryStore store(&controller, dir.filePath(QStringLiteral("recovery")));
    store.setAutosaveDelay(10);
    controller.openImage(QUrl::fromLocalFile(source));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(!controller.dirty());
    QVERIFY(!store.hasRecovery());

    controller.rotateClockwise();
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY(controller.dirty());
    QTRY_VERIFY_WITH_TIMEOUT(store.hasRecovery(), 5000);

    const QString target = dir.filePath(QStringLiteral("saved.png"));
    controller.saveAs(QUrl::fromLocalFile(target), QStringLiteral("png"));
    QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
    QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
    QVERIFY(!controller.dirty());
    QVERIFY(!store.hasRecovery());
    QVERIFY(!QFileInfo::exists(manifestFile(store.storageDirectory())));
    QVERIFY(!QFileInfo::exists(snapshotFile(store.storageDirectory())));
}

void RecoveryStoreTest::cleanExitRemovesSnapshot()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));

    // A snapshot can survive from an earlier session, but an application that
    // exits normally without unsaved work must not offer it again.
    {
        DocumentController controller;
        RecoveryStore store(&controller, recovery);
        QVERIFY(store.writeSnapshot(sampleImage(), QStringLiteral("/tmp/a.png"),
                                    QStringLiteral("a.png"),
                                    QDateTime::currentDateTimeUtc(),
                                    QStringLiteral("0.1.0")));
        QVERIFY(store.hasRecovery());
        QVERIFY(!controller.dirty());
    }

    QVERIFY(!QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(!QFileInfo::exists(snapshotFile(recovery)));
}

void RecoveryStoreTest::restoreMarksDocumentDirtyAndPreservesPixels()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));
    const QString original = dir.filePath(QStringLiteral("original.png"));
    {
        QFile file(original);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("untouched");
    }

    DocumentController controller;
    RecoveryStore store(&controller, recovery);
    // Keep the asynchronous autosave out of this test's assertions.
    store.setAutosaveDelay(5000);

    const QImage image = sampleImage(40, 30);
    QVERIFY(store.writeSnapshot(image, original, QStringLiteral("original.png"),
                                QDateTime::currentDateTimeUtc(),
                                QStringLiteral("0.1.0")));
    QVERIFY(store.restoreRecovery());

    QVERIFY(controller.hasImage());
    QVERIFY(controller.dirty());
    QVERIFY(controller.recovered());
    QVERIFY(!controller.hasPath());
    QCOMPARE(controller.fileName(), QStringLiteral("Recovered session"));
    QCOMPARE(controller.sourcePath(), original);
    QCOMPARE(controller.image().size(), image.size());
    QCOMPARE(controller.image().pixelColor(3, 4), QColor(200, 10, 30));

    // The snapshot was consumed; the recovered document is dirty so the next
    // edit writes a fresh copy through the autosave path.
    QVERIFY(!store.hasRecovery());

    QFile file(original);
    QVERIFY(file.open(QIODevice::ReadOnly));
    QCOMPARE(file.readAll(), QByteArray("untouched"));
}

void RecoveryStoreTest::restoreRejectsCorruptSnapshotWithoutError()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString recovery = dir.filePath(QStringLiteral("recovery"));
    DocumentController controller;
    RecoveryStore store(&controller, recovery);

    QVERIFY(store.writeSnapshot(sampleImage(), QStringLiteral("/tmp/a.png"),
                                QStringLiteral("a.png"),
                                QDateTime::currentDateTimeUtc(),
                                QStringLiteral("0.1.0")));
    QVERIFY(store.hasRecovery());

    // Corrupt the payload after the store scanned it. Restore must fail
    // quietly, discard the copy and leave the controller untouched.
    QFile file(snapshotFile(recovery));
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write("not a png");
    file.close();

    QVERIFY(!store.restoreRecovery());
    QVERIFY(!controller.hasImage());
    QVERIFY(controller.errorMessage().isEmpty());
    QVERIFY(!store.hasRecovery());
    QVERIFY(!QFileInfo::exists(manifestFile(recovery)));
    QVERIFY(!QFileInfo::exists(snapshotFile(recovery)));
}

QTEST_MAIN(RecoveryStoreTest)
#include "tst_recoverystore.moc"
