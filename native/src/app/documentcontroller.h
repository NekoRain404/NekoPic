#pragma once

#include <QColor>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QList>
#include <QVariantMap>
#include <QRectF>
#include <QVariantList>
#include <functional>
#include "core/adjustments.h"
#include "document/history.h"
#include "document/objectlayer.h"

class DocumentController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString fileName READ fileName NOTIFY documentChanged)
    Q_PROPERTY(QUrl imageUrl READ imageUrl NOTIFY documentChanged)
    Q_PROPERTY(QUrl baseImageUrl READ baseImageUrl NOTIFY documentChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool adjusting READ adjusting NOTIFY adjustingChanged)
    Q_PROPERTY(bool adjustmentInteractive READ adjustmentInteractive NOTIFY adjustmentInteractiveChanged)
    Q_PROPERTY(bool adjustmentPreviewGpuEligible READ adjustmentPreviewGpuEligible NOTIFY adjustmentInteractiveChanged)
    Q_PROPERTY(QVariantMap adjustmentValues READ adjustmentValues NOTIFY documentChanged)
    Q_PROPERTY(QVariantMap pendingAdjustmentValues READ pendingAdjustmentValues NOTIFY adjustmentPreviewChanged)
    Q_PROPERTY(QVariantList histogramBins READ histogramBins NOTIFY documentChanged)
    Q_PROPERTY(QString filterPreset READ filterPreset NOTIFY documentChanged)
    Q_PROPERTY(double filterIntensity READ filterIntensity NOTIFY documentChanged)
    Q_PROPERTY(bool filterIntensityInteractive READ filterIntensityInteractive NOTIFY filterIntensityInteractiveChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(bool hasImage READ hasImage NOTIFY documentChanged)
    Q_PROPERTY(bool hasObjects READ hasObjects NOTIFY documentChanged)
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY documentChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY documentChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY documentChanged)
    Q_PROPERTY(bool hasPath READ hasPath NOTIFY documentChanged)
    Q_PROPERTY(bool recovered READ recovered NOTIFY documentChanged)
    Q_PROPERTY(QString sourcePath READ sourcePath NOTIFY documentChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY documentChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY documentChanged)
    // Live object-drag preview: two crops around the selection. `base` has the
    // selected objects removed (unselected objects stay); `object` contains
    // only the selected objects. QML translates the object crop while the
    // pointer moves, so dragging is GPU-composited and the committed document
    // is still rendered once on release.
    Q_PROPERTY(QUrl objectMoveBaseUrl READ objectMoveBaseUrl NOTIFY objectMovePreviewChanged)
    Q_PROPERTY(QUrl objectMoveObjectUrl READ objectMoveObjectUrl NOTIFY objectMovePreviewChanged)
    Q_PROPERTY(QRectF objectMoveBounds READ objectMoveBounds NOTIFY objectMovePreviewChanged)
    Q_PROPERTY(bool objectMovePreviewReady READ objectMovePreviewReady NOTIFY objectMovePreviewChanged)
    Q_PROPERTY(QStringList readableImagePatterns READ readableImagePatterns CONSTANT)
    Q_PROPERTY(QVariantList writableFormats READ writableFormats CONSTANT)
    Q_PROPERTY(int exportQuality READ exportQuality WRITE setExportQuality NOTIFY exportOptionsChanged)
    Q_PROPERTY(QColor jpegBackground READ jpegBackground WRITE setJpegBackground NOTIFY exportOptionsChanged)

public:
    explicit DocumentController(QObject *parent = nullptr);
    ~DocumentController() override;
    QString fileName() const;
    QUrl imageUrl() const;
    QUrl baseImageUrl() const;
    bool busy() const;
    bool adjusting() const;
    bool adjustmentInteractive() const;
    bool adjustmentPreviewGpuEligible() const;
    QVariantMap adjustmentValues() const;
    QVariantMap pendingAdjustmentValues() const;
    QVariantList histogramBins() const;
    QString filterPreset() const;
    double filterIntensity() const;
    bool filterIntensityInteractive() const;
    QString errorMessage() const;
    bool hasImage() const;
    bool hasObjects() const;
    int imageWidth() const;
    int imageHeight() const;
    bool dirty() const;
    bool hasPath() const;
    /*! True while this document came from a crash-recovery snapshot. */
    bool recovered() const;
    /*!
        Original file path of a recovered document (empty otherwise). A
        recovered document has no save destination and never overwrites the
        original until the user saves through Save As.
    */
    QString sourcePath() const;
    bool canUndo() const;
    bool canRedo() const;
    QStringList readableImagePatterns() const;
    QVariantList writableFormats() const;
    int exportQuality() const;
    void setExportQuality(int quality);
    QColor jpegBackground() const;
    void setJpegBackground(const QColor &color);
    QImage image() const;
    QImage baseImage() const;
    NekoPic::Adjustments::Parameters adjustmentParameters() const;

    // Live-drag crops (see the Q_PROPERTY block above). The provider reads
    // these under the preview mutex; QML only needs the URLs and bounds.
    QImage objectMoveBaseImage() const;
    QImage objectMoveObjectImage() const;
    QUrl objectMoveBaseUrl() const;
    QUrl objectMoveObjectUrl() const;
    QRectF objectMoveBounds() const;
    bool objectMovePreviewReady() const;

    Q_INVOKABLE void openImage(const QUrl &url);
    Q_INVOKABLE void openImageDiscardingChanges(const QUrl &url);
    /*!
        Adopts a crash-recovery snapshot as a dirty document. The document is
        named "Recovered session", keeps no save path (so Save routes through
        Save As and the original file is untouched) and starts a fresh history.
        Returns false while busy or when the image is null.
    */
    bool restoreRecovery(const QImage &image, const QString &sourcePath = QString());
    Q_INVOKABLE void saveImage();
    Q_INVOKABLE void saveAs(const QUrl &url, const QString &format);
    Q_INVOKABLE void clearError();
    Q_INVOKABLE void copyImageToClipboard();
    Q_INVOKABLE QColor colorAt(qreal x, qreal y) const;
    Q_INVOKABLE void rotateClockwise();
    Q_INVOKABLE void rotateCounterClockwise();
    Q_INVOKABLE void flipHorizontal();
    Q_INVOKABLE void flipVertical();
    Q_INVOKABLE void cropImage(const QRectF &area);
    Q_INVOKABLE void resizeImage(int width, int height);
    Q_INVOKABLE void resizeCanvas(int width, int height, int anchor, const QColor &background);
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    Q_INVOKABLE void beginAdjustment(const QString &key);
    Q_INVOKABLE void previewAdjustment(const QString &key, double value);
    Q_INVOKABLE void finishAdjustment(const QString &key, double value);
    Q_INVOKABLE void resetAdjustments();
    Q_INVOKABLE void autoEnhance();
    Q_INVOKABLE void selectFilter(const QString &preset);
    Q_INVOKABLE void beginFilterIntensity();
    Q_INVOKABLE void previewFilterIntensity(double value);
    Q_INVOKABLE void finishFilterIntensity(double value);
    Q_INVOKABLE void mosaicRectangle(const QRectF &area, int blockSize);
    Q_INVOKABLE void mosaicStroke(const QVariantList &points, double diameter, int blockSize);
    Q_INVOKABLE void blurRectangle(const QRectF &area, int radius);
    Q_INVOKABLE void blurStroke(const QVariantList &points, int radius);
    Q_INVOKABLE void addText(const QString &text, qreal x, qreal y, qreal fontSize,
                             const QColor &color, int alignment);
    Q_INVOKABLE void addTextStyled(const QString &text, qreal x, qreal y,
                                   const QString &fontFamily, int fontWeight,
                                   qreal fontSize, const QColor &color, int alignment,
                                   const QColor &outlineColor, qreal outlineWidth,
                                   qreal lineHeight, qreal padding);
    // Reads editable state for a text object. Returns an empty map for
    // unknown or non-text ids. `x`/`y` are the *anchor* in document pixels
    // and use the same alignment convention as addTextStyled(): the horizontal
    // and vertical alignment flags select which edge (or centre) of the text
    // box touches the anchor. TextObject persists only the horizontal
    // alignment component, so the reported vertical anchor is always the box
    // centre (`alignment` includes Qt::AlignVCenter) and that is also the
    // anchor updateText() uses when the flag is present. info -> update ->
    // info is stable; the current box position is preserved exactly.
    Q_INVOKABLE QVariantMap textInfo(quint64 id) const;
    // Replaces the text, style and position of an existing text object while
    // preserving its id and z-order. `x`/`y` are the anchor described above.
    // One undo step. Returns false for unknown/non-text ids, invalid input,
    // while busy, or when no image is open.
    Q_INVOKABLE bool updateText(quint64 id, const QString &text, qreal x, qreal y,
                                const QString &fontFamily, int fontWeight, qreal fontSize,
                                const QColor &color, int alignment, const QColor &outlineColor,
                                qreal outlineWidth, qreal lineHeight, qreal padding);
    Q_INVOKABLE bool removeObject(quint64 id);
    Q_INVOKABLE void clearObjects();
    Q_INVOKABLE void moveObject(quint64 id, qreal dx, qreal dy);
    Q_INVOKABLE quint64 objectAt(qreal x, qreal y) const;
    Q_INVOKABLE QRectF objectBounds(quint64 id) const;
    Q_INVOKABLE QVariantList objectIds() const;
    // One map per object, topmost first. Keys: id (qulonglong), kind
    // ("text" | "shape" | "stroke"), name (short text preview or shape kind),
    // bounds (QRectF in document pixels), visible (bool), locked (bool).
    // Pure query: never mutates the document or touches history.
    Q_INVOKABLE QVariantList objectSummaries() const;
    // Per-object state. Each is one undo step, validates the id, and returns
    // false for unknown ids, while busy, when no image is open, or when the
    // requested value already matches (no-op edits create no history).
    Q_INVOKABLE bool setObjectVisible(quint64 id, bool visible);
    Q_INVOKABLE bool setObjectLocked(quint64 id, bool locked);
    // Z-order commands around the existing single-object layer operations.
    // Return false for unknown ids or when the object is already at the
    // requested end / next to a boundary (no undo step is created).
    Q_INVOKABLE bool raiseObject(quint64 id);
    Q_INVOKABLE bool lowerObject(quint64 id);
    Q_INVOKABLE bool bringObjectToFront(quint64 id);
    Q_INVOKABLE bool sendObjectToBack(quint64 id);
    // Group commands. Unknown/invalid ids are ignored; duplicates collapse.
    // Both are one undo step for all objects and return false when no live
    // object is targeted, when the delta is zero/non-finite, or while busy.
    Q_INVOKABLE bool removeObjects(const QVariantList &ids);
    Q_INVOKABLE bool moveObjects(const QVariantList &ids, qreal dx, qreal dy);
    // Starts a live-drag preview for `ids`; the drag itself only translates the
    // QML object crop. Release should call moveObjects() once and then
    // clearObjectMovePreview() after the commit. False while busy, for an
    // empty/invalid selection, or when no adjusted base can be prepared.
    Q_INVOKABLE bool beginObjectMovePreview(const QVariantList &ids);
    Q_INVOKABLE void clearObjectMovePreview();
    // Aligns every selected object to the image edge or centre selected by the
    // matching Qt alignment flag (AlignLeft/HCenter/Right and/or
    // AlignTop/VCenter/Bottom). One undo step; false for no flags, no valid
    // ids, or when nothing would move.
    Q_INVOKABLE bool alignObjects(const QVariantList &ids, int alignment);
    Q_INVOKABLE void addBrushStroke(const QVariantList &points, double diameter,
                                    const QColor &color, double softness = 0.0);
    Q_INVOKABLE void addShape(const QString &kind, const QRectF &rect,
                              const QColor &fillColor, const QColor &strokeColor,
                              double strokeWidth, double cornerRadius);
    Q_INVOKABLE void addPolygon(const QVariantList &points, const QColor &fillColor,
                                const QColor &strokeColor, double strokeWidth);

signals:
    void documentChanged();
    void busyChanged();
    void adjustingChanged();
    void adjustmentInteractiveChanged();
    void adjustmentPreviewChanged();
    void filterIntensityInteractiveChanged();
    void errorChanged();
    void imageOpened(const QUrl &url);
    void imageCopied();
    void imageSaved();
    void exportOptionsChanged();
    void objectMovePreviewChanged();

private:
    enum class Transform { RotateClockwise, RotateCounterClockwise, FlipHorizontal, FlipVertical };

    // Result of a worker that rebuilds pixels and/or the object layer.
    struct EditResult {
        QImage image;
        QImage base;
        NekoPic::Adjustments::Parameters parameters;
        std::shared_ptr<NekoPic::Document::ObjectLayer> objects;
    };

    // Result of an object edit rendered over a cached adjusted base. The
    // worker returns the adjusted base as well so a cache miss can populate
    // the cache without a second full-resolution adjustment pass.
    struct ObjectEditResult {
        QImage image;
        QImage adjustedBase;
    };

    void startTransform(Transform transform);
    void setBusy(bool busy);
    void setError(const QString &error);

    // Renders the document: adjustments/filters over base, then objects on top.
    // Pure function, safe to call from a worker thread with private snapshots.
    static QImage composeImage(const QImage &base,
                               const NekoPic::Adjustments::Parameters &parameters,
                               const NekoPic::Document::ObjectLayer *objects);

    // Exact field-by-field comparison used for the adjusted-base cache key.
    // Deliberately avoids serialisation: object edits run on a hot path.
    static bool parametersEqual(const NekoPic::Adjustments::Parameters &a,
                                const NekoPic::Adjustments::Parameters &b);

    // Downscaled source for interactive adjustment previews. Built lazily on
    // the GUI thread and reused until the base image or the active adjustment
    // source changes.
    QImage previewProxySource(const QImage &source);
    bool hasValidAdjustedBaseCache() const;
    void invalidateAdjustedBaseCache();

    void applyEdit(QImage image, QImage base, NekoPic::Adjustments::Parameters parameters,
                   std::shared_ptr<NekoPic::Document::ObjectLayer> objects = {});
    void commitEdit(EditResult result);

    // Clones the live layer, applies mutation on the GUI thread, then rasterises
    // the result in a worker. A false return from mutation rejects the edit
    // without touching history or busy state.
    void startObjectEdit(std::function<bool(NekoPic::Document::ObjectLayer &)> mutation);
    void queueAdjustment(const QString &key, double value, bool finish);
    void startAdjustmentWorker();
    void endAdjustment(const QImage &result, bool failed);
    void queueFilterIntensity(double value, bool finish);
    void startPixelEdit(std::function<QImage(const QImage &)> operation,
                        const QString &failureMessage);
    QImage image_;
    QImage baseImage_;
    NekoPic::Adjustments::Parameters parameters_;
    NekoPic::Adjustments::Parameters pendingParameters_;
    NekoPic::Document::ObjectLayer objects_;
    QString path_;
    // Original file behind a recovered session; never used as a save target.
    QString sourcePath_;
    bool recovered_ = false;
    QString error_;
    bool busy_ = false;
    bool adjusting_ = false;
    bool adjustmentWorkerRunning_ = false;
    bool adjustmentFinishing_ = false;
    QString adjustmentKey_;
    QImage adjustmentSource_;
    // Display-resolution proxy source, keyed by the base image identity and
    // the adjustmentSource_ of the drag that asked for it.
    QImage previewProxySource_;
    qint64 previewProxySourceKey_ = 0;
    qint64 previewProxyAdjustmentKey_ = 0;
    // Adjustments::apply(baseImage_, parameters_), before object compositing.
    QImage adjustedBaseCache_;
    NekoPic::Adjustments::Parameters adjustedBaseCacheParameters_;
    qint64 adjustedBaseCacheSourceKey_ = 0;
    bool adjustedBaseCacheValid_ = false;
    // Live object-drag crops, guarded because the QML image provider may read
    // them from the scene-graph thread.
    QList<quint64> movePreviewIds_;
    QImage movePreviewBaseCrop_;
    QImage movePreviewObjectCrop_;
    QRectF movePreviewBounds_;
    quint64 movePreviewRevision_ = 0;
    bool movePreviewReady_ = false;
    mutable QMutex movePreviewMutex_;
    double adjustmentValue_ = 0.0;
    quint64 adjustmentSequence_ = 0;
    quint64 revision_ = 0;
    quint64 currentState_ = 0;
    quint64 savedState_ = 0;
    quint64 nextState_ = 0;
    NekoPic::Document::HistoryStore history_;
    mutable QVariantList histogramCache_;
    mutable quint64 histogramCacheRevision_ = ~quint64(0);
    int exportQuality_ = -1;
    QColor jpegBackground_ = Qt::white;
};
