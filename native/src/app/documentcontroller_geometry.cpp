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

    const auto base = baseImage_;
    const auto parameters = parameters_;
    const auto objects = objects_.clone();
    setError({});
    setBusy(true);
    auto *watcher = new QFutureWatcher<EditResult>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        try {
            auto result = watcher->result();
            if (result.image.isNull() || result.base.isNull())
                setError(tr("Could not crop the image."));
            else
                commitEdit(std::move(result));
        } catch (...) {
            setError(tr("Could not crop the image."));
        }
        watcher->deleteLater();
        setBusy(false);
    });
    watcher->setFuture(QtConcurrent::run([base, parameters, objects, rectangle] {
        auto croppedBase = base.copy(rectangle);
        if (croppedBase.isNull()) return EditResult{};
        // Objects outside the kept rectangle are dropped; survivors move by the
        // same offset as the pixels. Partial overlaps stay whole and are
        // clipped visually by the smaller target image.
        objects->crop(rectangle, -rectangle.topLeft());
        auto rendered = DocumentController::composeImage(croppedBase, parameters, objects.get());
        return EditResult{std::move(rendered), std::move(croppedBase), parameters, objects};
    }));
}
