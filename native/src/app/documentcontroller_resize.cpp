#include "documentcontroller.h"

#include "core/adjustments.h"
#include "io/imageio.h"

#include <QColorSpace>
#include <QFutureWatcher>
#include <QPainter>
#include <QThreadPool>
#include <QtConcurrentRun>
#include <utility>

namespace {

// Qt alignment bits describe the anchor; default to the centre.
QPoint canvasOffset(const QSize &target, const QSize &source, int anchor)
{
    const int x = (anchor & Qt::AlignLeft) ? 0
        : (anchor & Qt::AlignRight) ? target.width() - source.width()
                                    : (target.width() - source.width()) / 2;
    const int y = (anchor & Qt::AlignTop) ? 0
        : (anchor & Qt::AlignBottom) ? target.height() - source.height()
                                     : (target.height() - source.height()) / 2;
    return {x, y};
}

bool withinLimits(int width, int height)
{
    const NekoPic::ImageIO::Limits limits;
    return width > 0 && height > 0 && width <= limits.maxDimension && height <= limits.maxDimension
        && qint64(width) * height <= limits.maxPixels;
}

QImage scalePreservingMetadata(const QImage &source, int width, int height)
{
    auto scaled = source.scaled(width, height, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    if (scaled.isNull()) return {};
    scaled.setColorSpace(source.colorSpace());
    scaled.setDotsPerMeterX(source.dotsPerMeterX());
    scaled.setDotsPerMeterY(source.dotsPerMeterY());
    return scaled;
}

QImage canvasPreservingMetadata(const QImage &source, int width, int height,
                                const QPoint &offset, const QColor &background)
{
    QImage canvas(width, height, source.format());
    if (canvas.isNull()) return {};
    canvas.setColorSpace(source.colorSpace());
    canvas.setDotsPerMeterX(source.dotsPerMeterX());
    canvas.setDotsPerMeterY(source.dotsPerMeterY());
    canvas.fill(background);
    QPainter painter(&canvas);
    painter.drawImage(offset, source);
    return canvas;
}

} // namespace

void DocumentController::resizeImage(int width, int height)
{
    if (busy_ || !hasImage()) return;
    if (width == imageWidth() && height == imageHeight()) return;
    if (!withinLimits(width, height)) {
        setError(tr("The requested image size is not supported."));
        return;
    }
    const auto base = baseImage_;
    const auto parameters = parameters_;
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<QPair<QImage, QImage>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, parameters] {
        auto result = watcher->result();
        watcher->deleteLater();
        if (result.first.isNull() || result.second.isNull())
            setError(tr("Could not resize the image."));
        else
            applyEdit(std::move(result.first), std::move(result.second), parameters);
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, parameters, width, height] {
        auto scaledBase = scalePreservingMetadata(base, width, height);
        auto rendered = scaledBase.isNull() ? QImage{}
                                            : NekoPic::Adjustments::apply(scaledBase, parameters);
        return qMakePair(std::move(rendered), std::move(scaledBase));
    }));
}

void DocumentController::resizeCanvas(int width, int height, int anchor, const QColor &background)
{
    if (busy_ || !hasImage()) return;
    if (width == imageWidth() && height == imageHeight()) return;
    if (!withinLimits(width, height)) {
        setError(tr("The requested canvas size is not supported."));
        return;
    }
    if (!background.isValid()) {
        setError(tr("The canvas background color is invalid."));
        return;
    }
    const auto base = baseImage_;
    const auto rendered = image_;
    const auto parameters = parameters_;
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<QPair<QImage, QImage>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, parameters] {
        auto result = watcher->result();
        watcher->deleteLater();
        if (result.first.isNull() || result.second.isNull())
            setError(tr("Could not change the canvas size."));
        else
            applyEdit(std::move(result.first), std::move(result.second), parameters);
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, rendered, width, height, anchor, background] {
        const auto offset = canvasOffset(QSize(width, height), base.size(), anchor);
        auto newBase = canvasPreservingMetadata(base, width, height, offset, background);
        auto newRendered = canvasPreservingMetadata(rendered, width, height, offset, background);
        return qMakePair(std::move(newRendered), std::move(newBase));
    }));
}
