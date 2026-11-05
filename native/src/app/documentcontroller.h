#pragma once

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
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY documentChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY documentChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY documentChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY documentChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY documentChanged)
    Q_PROPERTY(QStringList readableImagePatterns READ readableImagePatterns CONSTANT)

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
    int imageWidth() const;
    int imageHeight() const;
    bool dirty() const;
    bool canUndo() const;
    bool canRedo() const;
    QStringList readableImagePatterns() const;
    QImage image() const;
    QImage baseImage() const;
    NekoPic::Adjustments::Parameters adjustmentParameters() const;

    Q_INVOKABLE void openImage(const QUrl &url);
    Q_INVOKABLE void openImageDiscardingChanges(const QUrl &url);
    Q_INVOKABLE void saveImage();
    Q_INVOKABLE void saveAs(const QUrl &url, const QString &format);
    Q_INVOKABLE void clearError();
    Q_INVOKABLE void rotateClockwise();
    Q_INVOKABLE void rotateCounterClockwise();
    Q_INVOKABLE void flipHorizontal();
    Q_INVOKABLE void flipVertical();
    Q_INVOKABLE void cropImage(const QRectF &area);
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

signals:
    void documentChanged();
    void busyChanged();
    void adjustingChanged();
    void adjustmentInteractiveChanged();
    void adjustmentPreviewChanged();
    void filterIntensityInteractiveChanged();
    void errorChanged();

private:
    enum class Transform { RotateClockwise, RotateCounterClockwise, FlipHorizontal, FlipVertical };
    void startTransform(Transform transform);
    void setBusy(bool busy);
    void setError(const QString &error);
    void applyEdit(QImage image, QImage base, NekoPic::Adjustments::Parameters parameters);
    void queueAdjustment(const QString &key, double value, bool finish);
    void startAdjustmentWorker();
    void endAdjustment(const QImage &result, bool failed);
    void queueFilterIntensity(double value, bool finish);
    void startMosaic(std::function<QImage(const QImage &)> operation);
    QImage image_;
    QImage baseImage_;
    NekoPic::Adjustments::Parameters parameters_;
    NekoPic::Adjustments::Parameters pendingParameters_;
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
};
