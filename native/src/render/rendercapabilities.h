#pragma once

#include <QObject>
#include <QString>

namespace NekoPic::Render {

// Reports what the scene graph actually uses so QML can decide between the
// GPU interactive preview and the CPU fallback. Probe after the first window
// exists; QQuickWindow::graphicsApi() is not meaningful before that.
class RenderCapabilities final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString backend READ backend NOTIFY changed)
    Q_PROPERTY(bool gpuPreviewAvailable READ gpuPreviewAvailable NOTIFY changed)
    Q_PROPERTY(bool softwareFallback READ softwareFallback NOTIFY changed)

public:
    explicit RenderCapabilities(QObject *parent = nullptr);

    QString backend() const;
    bool gpuPreviewAvailable() const;
    bool softwareFallback() const;

    void probe();

signals:
    void changed();

private:
    void setState(QString backend, bool gpuAvailable, bool software);

    QString backend_ = QStringLiteral("unknown");
    bool gpuPreviewAvailable_ = false;
    bool softwareFallback_ = true;
};

} // namespace NekoPic::Render
