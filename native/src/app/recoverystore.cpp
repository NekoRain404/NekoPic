#include "recoverystore.h"

#include "documentcontroller.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QSaveFile>
#include <QStandardPaths>
#include <QtConcurrentRun>
#include <algorithm>

namespace {

constexpr int ManifestVersion = 1;
constexpr qint64 MaxManifestBytes = 64 * 1024;
const QString ManifestFileName = QStringLiteral("manifest.json");
const QString ImageFileName = QStringLiteral("snapshot.png");

QString manifestPath(const QString &directory)
{
    return QDir(directory).filePath(ManifestFileName);
}

QString imagePath(const QString &directory)
{
    return QDir(directory).filePath(ImageFileName);
}

QString defaultRecoveryDirectory()
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty())
        base = QDir(QDir::tempPath()).filePath(QStringLiteral("nekopic"));
    return QDir(base).filePath(QStringLiteral("recovery"));
}

bool isSha256Hex(const QString &value)
{
    if (value.size() != 64) return false;
    for (const QChar character : value) {
        const ushort code = character.unicode();
        const bool digit = code >= '0' && code <= '9';
        const bool lower = code >= 'a' && code <= 'f';
        if (!digit && !lower) return false;
    }
    return true;
}

/*! QSaveFile leaves only our two target names plus possible temp leftovers. */
void removeSnapshotFiles(const QString &directory)
{
    QFile::remove(manifestPath(directory));
    QFile::remove(imagePath(directory));
    QDir dir(directory);
    if (!dir.exists()) return;
    const auto entries = dir.entryInfoList(QDir::Files | QDir::Hidden | QDir::System);
    for (const auto &entry : entries) {
        const QString name = entry.fileName();
        if (name.startsWith(ManifestFileName) || name.startsWith(ImageFileName))
            dir.remove(name);
    }
}

struct ManifestRecord {
    bool valid = false;
    QString sourceName;
    QString sourcePath;
    QDateTime capturedAt;
    QSize imageSize;
    QString appVersion;
    bool flattened = false;
    QString sha256;
};

bool fileDigest(const QString &path, QByteArray *digest)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file)) return false;
    *digest = hash.result().toHex();
    return true;
}

/*!
    Validates the manifest and the PNG container (header/size/hash) without
    decoding pixels, so startup validation stays cheap. Pixel decode errors are
    still caught by loadSnapshotImage() at restore time.
*/
bool parseManifest(const QString &directory, ManifestRecord *record)
{
    QFile manifestFile(manifestPath(directory));
    if (!manifestFile.exists() || manifestFile.size() > MaxManifestBytes)
        return false;
    if (!manifestFile.open(QIODevice::ReadOnly)) return false;

    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(manifestFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return false;
    const auto object = document.object();

    const auto version = object.value(QStringLiteral("version"));
    if (!version.isDouble() || version.toInt() != ManifestVersion) return false;
    const auto width = object.value(QStringLiteral("width"));
    const auto height = object.value(QStringLiteral("height"));
    if (!width.isDouble() || !height.isDouble()) return false;
    if (width.toInt() <= 0 || height.toInt() <= 0) return false;

    const auto imageFileValue = object.value(QStringLiteral("imageFile"));
    if (!imageFileValue.isString() || imageFileValue.toString() != ImageFileName)
        return false;
    const auto shaValue = object.value(QStringLiteral("sha256"));
    if (!shaValue.isString() || !isSha256Hex(shaValue.toString()))
        return false;

    const auto timestampValue = object.value(QStringLiteral("timestamp"));
    if (!timestampValue.isString()) return false;
    QDateTime capturedAt = QDateTime::fromString(timestampValue.toString(), Qt::ISODateWithMs);
    if (!capturedAt.isValid())
        capturedAt = QDateTime::fromString(timestampValue.toString(), Qt::ISODate);
    if (!capturedAt.isValid()) return false;

    const QSize size(width.toInt(), height.toInt());
    const QString snapshot = imagePath(directory);
    if (!QFileInfo::exists(snapshot)) return false;
    QImageReader reader(snapshot, QByteArrayLiteral("PNG"));
    if (!reader.canRead() || reader.size() != size) return false;

    QByteArray digest;
    if (!fileDigest(snapshot, &digest)) return false;
    if (digest != shaValue.toString().toLatin1()) return false;

    record->sourcePath = object.value(QStringLiteral("sourcePath")).toString();
    record->sourceName = object.value(QStringLiteral("sourceName")).toString();
    if (record->sourceName.isEmpty())
        record->sourceName = QFileInfo(record->sourcePath).fileName();
    record->capturedAt = capturedAt;
    record->imageSize = size;
    record->appVersion = object.value(QStringLiteral("appVersion")).toString();
    record->flattened = object.value(QStringLiteral("flattened")).toBool(true);
    record->sha256 = shaValue.toString();
    record->valid = true;
    return true;
}

bool loadSnapshotImage(const QString &directory, const ManifestRecord &record, QImage *image)
{
    QImageReader reader(imagePath(directory), QByteArrayLiteral("PNG"));
    if (!reader.canRead() || reader.size() != record.imageSize) return false;
    QImage loaded = reader.read();
    if (loaded.isNull() || loaded.size() != record.imageSize) return false;

    QByteArray digest;
    if (!fileDigest(imagePath(directory), &digest)) return false;
    if (digest != record.sha256.toLatin1()) return false;

    *image = std::move(loaded);
    return true;
}

/*! Encodes and atomically commits the PNG first, then its manifest. */
bool writeSnapshotFiles(const QString &directory, const QImage &image,
                        const QString &sourcePath, const QString &sourceName,
                        const QDateTime &capturedAt, const QString &appVersion)
{
    if (image.isNull() || !QDir().mkpath(directory)) return false;

    QByteArray png;
    QBuffer buffer(&png);
    if (!buffer.open(QIODevice::WriteOnly)) return false;
    if (!image.save(&buffer, "PNG") || png.isEmpty()) return false;
    buffer.close();
    const QByteArray digest =
        QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex();

    QSaveFile imageFile(imagePath(directory));
    if (!imageFile.open(QIODevice::WriteOnly)) return false;
    if (imageFile.write(png) != png.size()) {
        imageFile.cancelWriting();
        return false;
    }
    if (!imageFile.commit()) return false;

    QString name = sourceName;
    if (name.isEmpty()) name = QFileInfo(sourcePath).fileName();
    const QJsonObject manifest{
        {QStringLiteral("version"), ManifestVersion},
        {QStringLiteral("sourceName"), name},
        {QStringLiteral("sourcePath"), sourcePath},
        {QStringLiteral("timestamp"), capturedAt.toUTC().toString(Qt::ISODateWithMs)},
        {QStringLiteral("width"), image.width()},
        {QStringLiteral("height"), image.height()},
        {QStringLiteral("appVersion"), appVersion},
        {QStringLiteral("flattened"), true},
        {QStringLiteral("imageFile"), ImageFileName},
        {QStringLiteral("sha256"), QString::fromLatin1(digest)},
    };

    QSaveFile manifestFile(manifestPath(directory));
    if (!manifestFile.open(QIODevice::WriteOnly)) {
        QFile::remove(imagePath(directory));
        return false;
    }
    const QByteArray json = QJsonDocument(manifest).toJson(QJsonDocument::Compact);
    if (manifestFile.write(json) != json.size() || !manifestFile.commit()) {
        manifestFile.cancelWriting();
        QFile::remove(imagePath(directory));
        return false;
    }
    return true;
}

} // namespace

RecoveryStore::RecoveryStore(DocumentController *document,
                             const QString &storageDirectory, QObject *parent)
    : QObject(parent)
    , document_(document)
    , directory_(storageDirectory.isEmpty() ? defaultRecoveryDirectory() : storageDirectory)
{
    debounce_.setParent(this);
    debounce_.setSingleShot(true);
    connect(&debounce_, &QTimer::timeout, this, &RecoveryStore::startWrite);
    connect(&writeWatcher_, &QFutureWatcherBase::finished,
            this, &RecoveryStore::finishWrite);

    if (document_) {
        connect(document_, &DocumentController::documentChanged, this, [this] {
            if (!document_) return;
            // Saving cleanly (or undoing back to the saved state) makes the
            // crash copy redundant. Keep it only while there is dirty work.
            if (!document_->hasImage() || !document_->dirty()) {
                discardRecovery();
                return;
            }
            scheduleAutosave();
        });
        connect(document_, &DocumentController::busyChanged, this, [this] {
            if (document_ && !document_->busy() && document_->hasImage()
                && document_->dirty())
                scheduleAutosave();
        });
        connect(document_, &DocumentController::imageSaved,
                this, &RecoveryStore::discardRecovery);
    }
    scan();
}

RecoveryStore::~RecoveryStore()
{
    debounce_.stop();
    if (document_ && !document_->dirty()) {
        // A normal exit with no unsaved work must leave nothing behind. Wait
        // for an in-flight encode so it cannot recreate the files we delete.
        if (writeWatcher_.isRunning())
            writeWatcher_.waitForFinished();
        discardRecovery();
    } else {
        // Crash-equivalent exit with dirty work: leave the snapshot in place,
        // and make any in-flight write unable to resurrect after disposal.
        ++writeGeneration_;
    }
}

bool RecoveryStore::hasRecovery() const { return meta_.valid; }
QString RecoveryStore::sourceName() const { return meta_.sourceName; }
QString RecoveryStore::sourcePath() const { return meta_.sourcePath; }
QString RecoveryStore::capturedAtText() const
{
    if (!meta_.capturedAt.isValid()) return {};
    return QLocale().toString(meta_.capturedAt.toLocalTime(), QLocale::ShortFormat);
}
QString RecoveryStore::capturedAtIso() const
{
    return meta_.capturedAt.isValid()
        ? meta_.capturedAt.toUTC().toString(Qt::ISODateWithMs) : QString();
}
QString RecoveryStore::imageSizeText() const
{
    if (!meta_.valid) return {};
    return QStringLiteral("%1 × %2 px").arg(meta_.imageSize.width()).arg(meta_.imageSize.height());
}
int RecoveryStore::imageWidth() const { return meta_.imageSize.width(); }
int RecoveryStore::imageHeight() const { return meta_.imageSize.height(); }
bool RecoveryStore::flattened() const { return meta_.flattened; }
QString RecoveryStore::storageDirectory() const { return directory_; }

void RecoveryStore::setAutosaveDelay(int milliseconds)
{
    autosaveDelay_ = std::max(0, milliseconds);
}
int RecoveryStore::autosaveDelay() const { return autosaveDelay_; }

bool RecoveryStore::writeSnapshot(const QImage &image, const QString &sourcePath,
                                  const QString &sourceName,
                                  const QDateTime &capturedAt,
                                  const QString &appVersion)
{
    if (!writeSnapshotFiles(directory_, image, sourcePath, sourceName,
                            capturedAt, appVersion))
        return false;
    scan();
    return true;
}

bool RecoveryStore::readSnapshot(QImage *image) const
{
    if (!image) return false;
    ManifestRecord record;
    if (!parseManifest(directory_, &record)) return false;
    return loadSnapshotImage(directory_, record, image);
}

void RecoveryStore::discardRecovery()
{
    debounce_.stop();
    writePending_ = false;
    ++writeGeneration_;
    removeSnapshotFiles(directory_);
    applyMeta({});
}

bool RecoveryStore::restoreRecovery()
{
    if (!document_ || document_->busy()) return false;
    if (!meta_.valid) scan();
    if (!meta_.valid) return false;

    QImage image;
    if (!readSnapshot(&image)) {
        // The snapshot decayed between startup validation and the click.
        discardRecovery();
        return false;
    }
    if (!document_->restoreRecovery(image, meta_.sourcePath)) return false;

    // Consume the old copy but keep the debounce that the controller's
    // documentChanged just started, so the recovered document is protected
    // again as soon as the user pauses.
    consumeSnapshotFiles();
    return true;
}

void RecoveryStore::scheduleAutosave()
{
    if (!document_ || !document_->hasImage() || !document_->dirty()) return;
    debounce_.start(autosaveDelay_);
}

void RecoveryStore::startWrite()
{
    if (!document_) return;
    if (document_->busy()) {
        // Let the current edit finish before reading image().
        debounce_.start(autosaveDelay_);
        return;
    }
    if (!document_->hasImage() || !document_->dirty()) return;
    if (writeWatcher_.isRunning()) {
        writePending_ = true;
        return;
    }

    const QImage image = document_->image();
    if (image.isNull()) return;
    const QString sourcePath = document_->sourcePath();
    QString sourceName = QFileInfo(sourcePath).fileName();
    if (sourceName.isEmpty()) sourceName = document_->fileName();
    const QDateTime capturedAt = QDateTime::currentDateTimeUtc();
    const QString appVersion = QCoreApplication::applicationVersion();
    const QString directory = directory_;

    activeWriteGeneration_ = ++writeGeneration_;
    writePending_ = false;
    // Only immutable values cross the thread boundary; PNG encoding happens
    // here, never on the GUI thread.
    writeWatcher_.setFuture(QtConcurrent::run(
        [directory, image, sourcePath, sourceName, capturedAt, appVersion] {
            return writeSnapshotFiles(directory, image, sourcePath, sourceName,
                                      capturedAt, appVersion);
        }));
}

void RecoveryStore::finishWrite()
{
    bool written = false;
    try {
        written = writeWatcher_.result();
    } catch (...) {
        written = false;
    }

    const bool stale = activeWriteGeneration_ != writeGeneration_;
    if (stale) {
        // discardRecovery()/restoreRecovery() won the race; remove whatever
        // this worker just committed instead of surfacing an obsolete copy.
        removeSnapshotFiles(directory_);
        applyMeta({});
    } else if (written) {
        scan();
    } else {
        qDebug("RecoveryStore: could not write the recovery snapshot");
    }

    if (!stale && writePending_) {
        writePending_ = false;
        debounce_.start(autosaveDelay_);
    }
}

void RecoveryStore::scan()
{
    ManifestRecord record;
    if (!parseManifest(directory_, &record)) {
        if (QFileInfo::exists(manifestPath(directory_))
            || QFileInfo::exists(imagePath(directory_))) {
            qDebug("RecoveryStore: discarding an invalid recovery snapshot");
        }
        removeSnapshotFiles(directory_);
        applyMeta({});
        return;
    }

    SnapshotMeta meta;
    meta.valid = true;
    meta.sourceName = record.sourceName;
    meta.sourcePath = record.sourcePath;
    meta.capturedAt = record.capturedAt;
    meta.imageSize = record.imageSize;
    meta.appVersion = record.appVersion;
    meta.flattened = record.flattened;
    meta.sha256 = record.sha256;
    applyMeta(meta);
}

void RecoveryStore::applyMeta(const SnapshotMeta &meta)
{
    const bool changed = meta_.valid != meta.valid
        || meta_.sourceName != meta.sourceName
        || meta_.sourcePath != meta.sourcePath
        || meta_.capturedAt != meta.capturedAt
        || meta_.imageSize != meta.imageSize
        || meta_.appVersion != meta.appVersion
        || meta_.flattened != meta.flattened
        || meta_.sha256 != meta.sha256;
    meta_ = meta;
    if (changed) emit recoveryChanged();
}

void RecoveryStore::consumeSnapshotFiles()
{
    ++writeGeneration_;
    removeSnapshotFiles(directory_);
    applyMeta({});
}
