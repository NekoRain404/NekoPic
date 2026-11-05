#include "rendercapabilities.h"

#include <QQuickWindow>
#include <utility>

namespace NekoPic::Render {

RenderCapabilities::RenderCapabilities(QObject *parent) : QObject(parent) {}

QString RenderCapabilities::backend() const { return backend_; }
bool RenderCapabilities::gpuPreviewAvailable() const { return gpuPreviewAvailable_; }
bool RenderCapabilities::softwareFallback() const { return softwareFallback_; }

void RenderCapabilities::probe()
{
    QString name;
    bool gpu = false;
    switch (QQuickWindow::graphicsApi()) {
    case QSGRendererInterface::OpenGL:
        name = QStringLiteral("opengl");
        gpu = true;
        break;
    case QSGRendererInterface::Vulkan:
        name = QStringLiteral("vulkan");
        gpu = true;
        break;
    case QSGRendererInterface::Metal:
        name = QStringLiteral("metal");
        gpu = true;
        break;
    case QSGRendererInterface::Direct3D11:
    case QSGRendererInterface::Direct3D12:
        name = QStringLiteral("d3d");
        gpu = true;
        break;
    case QSGRendererInterface::Software:
        name = QStringLiteral("software");
        break;
    default:
        name = QStringLiteral("unknown");
        break;
    }
    setState(name, gpu, !gpu);
}

void RenderCapabilities::setState(QString backend, bool gpuAvailable, bool software)
{
    if (backend_ == backend && gpuPreviewAvailable_ == gpuAvailable
        && softwareFallback_ == software)
        return;
    backend_ = std::move(backend);
    gpuPreviewAvailable_ = gpuAvailable;
    softwareFallback_ = software;
    emit changed();
}

} // namespace NekoPic::Render
