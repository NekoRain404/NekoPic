#pragma once

#include <QDateTime>
#include <QFutureWatcher>
#include <QImage>
#include <QObject>
#include <QSize>
#include <QString>
#include <QTimer>

class DocumentController;

/*!
    RecoveryStore — crash-recovery snapshots for the current document.

    H5 keeps a temporary IndexedDB copy of the editor bitmap. This is the
    native equivalent: after a debounce, the rendered document image is written
    as PNG next to a small versioned manifest under
    `QStandardPaths::AppLocalDataLocation/recovery/`.

    Design contract:

    - Only one snapshot exists at a time (a PNG plus its manifest), so disk use
      is bounded by the current image. Writes use QSaveFile (temp file + atomic
      rename) and are performed with QtConcurrent; the GUI thread only copies
      the implicitly shared QImage and never encodes PNG.
    - The manifest records a schema version, source file name/path, capture
      time (UTC ISO-8601 with milliseconds), image size, application version
      and a `flattened` flag. The PNG is the rendered result (`image()`), so
      adjustments, filters, text and shapes are visually exact; object
      editability is *not* preserved in this first version.
    - A snapshot is kept across a crash. It is removed when the document is
      saved cleanly, when the document returns to its saved state, and when the
      application exits normally without unsaved changes.
    - Corrupt or incomplete snapshots are discarded silently (one debug log
      line); recovery never blocks startup with an error dialog.

    The object must live on the GUI thread. `writeSnapshot()` is a synchronous
    helper for tests and diagnostics; normal autosaving is asynchronous.
*/
class RecoveryStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasRecovery READ hasRecovery NOTIFY recoveryChanged)
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY recoveryChanged)
    Q_PROPERTY(QString sourcePath READ sourcePath NOTIFY recoveryChanged)
    Q_PROPERTY(QString capturedAtText READ capturedAtText NOTIFY recoveryChanged)
    Q_PROPERTY(QString capturedAtIso READ capturedAtIso NOTIFY recoveryChanged)
    Q_PROPERTY(QString imageSizeText READ imageSizeText NOTIFY recoveryChanged)
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY recoveryChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY recoveryChanged)
    Q_PROPERTY(bool flattened READ flattened NOTIFY recoveryChanged)
    Q_PROPERTY(bool autosaveEnabled READ autosaveEnabled WRITE setAutosaveEnabled
               NOTIFY autosaveEnabledChanged)

public:
    /*!
        `storageDirectory` empty means
        `QStandardPaths::AppLocalDataLocation/recovery`. A null `document`
        disables autosave wiring; the store can still read, write and discard
        snapshots explicitly (used by unit tests).
    */
    explicit RecoveryStore(DocumentController *document,
                           const QString &storageDirectory = QString(),
                           QObject *parent = nullptr);
    ~RecoveryStore() override;

    bool hasRecovery() const;
    QString sourceName() const;
    QString sourcePath() const;
    /*! Localised capture time, e.g. "2026-11-05 10:20". */
    QString capturedAtText() const;
    /*! UTC ISO-8601 with milliseconds as stored in the manifest. */
    QString capturedAtIso() const;
    /*! "W × H px". */
    QString imageSizeText() const;
    int imageWidth() const;
    int imageHeight() const;
    /*! Always true for snapshots written by this version. */
    bool flattened() const;
    QString storageDirectory() const;

    /*! Debounce delay after the last document change. */
    void setAutosaveDelay(int milliseconds);
    int autosaveDelay() const;

    /*!
        Whether dirty documents schedule crash snapshots. Disabling stops the
        pending debounce but leaves any existing snapshot on disk so a user can
        still recover it; enabling immediately reschedules a dirty document.
    */
    bool autosaveEnabled() const;
    void setAutosaveEnabled(bool enabled);

    /*!
        Synchronously writes a snapshot (PNG + manifest) and refreshes the
        exposed metadata. Returns false on any failure. GUI thread only; the
        asynchronous autosave path uses an equivalent private writer.
    */
    bool writeSnapshot(const QImage &image, const QString &sourcePath,
                       const QString &sourceName, const QDateTime &capturedAt,
                       const QString &appVersion);

    /*! Loads and validates the snapshot image. False if missing/corrupt. */
    bool readSnapshot(QImage *image) const;

    /*! Deletes the snapshot and cancels any in-flight autosave write. */
    Q_INVOKABLE void discardRecovery();

    /*!
        Loads the snapshot into the controller as a dirty "Recovered session"
        document. The original file is never modified: the controller keeps an
        empty save path and reports no destination until Save As. The snapshot
        is consumed (a fresh one is written on the next document change) and
        the boolean says whether a document is available.
    */
    Q_INVOKABLE bool restoreRecovery();

signals:
    void recoveryChanged();
    void autosaveEnabledChanged();

private:
    struct SnapshotMeta {
        bool valid = false;
        QString sourceName;
        QString sourcePath;
        QDateTime capturedAt;
        QSize imageSize;
        QString appVersion;
        bool flattened = false;
        QString sha256;
    };

    void scheduleAutosave();
    void startWrite();
    void finishWrite();
    void scan();
    void applyMeta(const SnapshotMeta &meta);
    void consumeSnapshotFiles();

    DocumentController *document_ = nullptr;
    QString directory_;
    SnapshotMeta meta_;
    QTimer debounce_;
    QFutureWatcher<bool> writeWatcher_;
    bool writePending_ = false;
    quint64 writeGeneration_ = 0;
    quint64 activeWriteGeneration_ = 0;
    int autosaveDelay_ = 1200;
    bool autosaveEnabled_ = true;
};
