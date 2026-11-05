#include "documentcontroller.h"

#include <QFutureWatcher>
#include <QtConcurrentRun>
#include <cmath>
#include <utility>

void DocumentController::cropImage(const QRectF &area)
{
    if (busy_ || !hasImage()) return;
    for (const auto value : {area.x(), area.y(), area.width(), area.height(),
                             area.right(), area.bottom()}) {
        if (!std::isfinite(value) || std::abs(value) > 1e7) return;
    }
    // QML selections use continuous pixel edges; retain every touched pixel.
    const auto clipped = area.normalized().intersected(QRectF(baseImage_.rect()));
    if (clipped.isEmpty()) return;
    const auto rectangle = clipped.toAlignedRect().intersected(baseImage_.rect());
    if (rectangle.isEmpty() || rectangle == baseImage_.rect()) return;

    const auto source = image_;
    const auto base = baseImage_;
    const auto parameters = parameters_;
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<QPair<QImage, QImage>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, parameters] {
        try {
            auto result = watcher->result();
            if (result.first.isNull() || result.second.isNull())
                setError(tr("Could not crop the image."));
            else
                applyEdit(std::move(result.first), std::move(result.second), parameters);
        } catch (...) {
            setError(tr("Could not crop the image."));
        }
        watcher->deleteLater();
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([source, base, rectangle] {
        auto cropped = source.copy(rectangle);
        auto croppedBase = source.cacheKey() == base.cacheKey() ? cropped : base.copy(rectangle);
        return qMakePair(std::move(cropped), std::move(croppedBase));
    }));
}
