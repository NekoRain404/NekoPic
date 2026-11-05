#pragma once

#include <QColor>
#include <QImage>
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
    Q_PROPERTY(QVariantMap adjustmentValues READ adjustmentValues NOTIFY documentChanged)
    Q_PROPERTY(QVariantMap pendingAdjustmentValues READ pendingAdjustmentValues NOTIFY adjustmentPreviewChanged)
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
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY documentChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY documentChanged)
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
    QVariantMap adjustmentValues() const;
    QVariantMap pendingAdjustmentValues() const;
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

    Q_INVOKABLE void openImage(const QUrl &url);
    Q_INVOKABLE void openImageDiscardingChanges(const QUrl &url);
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
    Q_INVOKABLE bool removeObject(quint64 id);
    Q_INVOKABLE void clearObjects();
    Q_INVOKABLE void moveObject(quint64 id, qreal dx, qreal dy);
    Q_INVOKABLE quint64 objectAt(qreal x, qreal y) const;
    Q_INVOKABLE QRectF objectBounds(quint64 id) const;
    Q_INVOKABLE QVariantList objectIds() const;
    Q_INVOKABLE void addBrushStroke(const QVariantList &points, double diameter, const QColor &color);
    Q_INVOKABLE void addShape(const QString &kind, const QRectF &rect,
                              const QColor &fillColor, const QColor &strokeColor,
                              double strokeWidth, double cornerRadius);

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

private:
    enum class Transform { RotateClockwise, RotateCounterClockwise, FlipHorizontal, FlipVertical };

    // Result of a worker that rebuilds pixels and/or the object layer.
    struct EditResult {
        QImage image;
        QImage base;
        NekoPic::Adjustments::Parameters parameters;
        std::shared_ptr<NekoPic::Document::ObjectLayer> objects;
    };

    void startTransform(Transform transform);
    void setBusy(bool busy);
    void setError(const QString &error);

    // Renders the document: adjustments/filters over base, then objects on top.
    // Pure function, safe to call from a worker thread with private snapshots.
    static QImage composeImage(const QImage &base,
                               const NekoPic::Adjustments::Parameters &parameters,
                               const NekoPic::Document::ObjectLayer *objects);

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
    QString error_;
    bool busy_ = false;
    bool adjusting_ = false;
    bool adjustmentWorkerRunning_ = false;
    bool adjustmentFinishing_ = false;
    QString adjustmentKey_;
    QImage adjustmentSource_;
    double adjustmentValue_ = 0.0;
    quint64 adjustmentSequence_ = 0;
    quint64 revision_ = 0;
    quint64 currentState_ = 0;
    quint64 savedState_ = 0;
    quint64 nextState_ = 0;
    NekoPic::Document::HistoryStore history_;
    int exportQuality_ = -1;
    QColor jpegBackground_ = Qt::white;
};
