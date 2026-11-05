#include "document/objectlayer.h"

#include <QPainter>

#include <algorithm>
#include <cmath>
#include <utility>

namespace NekoPic::Document {

ObjectId ObjectLayer::add(std::unique_ptr<DocumentObject> object)
{
    if (!object)
        return InvalidObjectId;
    const ObjectId id = object->id();
    objects_.push_back(std::move(object));
    return id;
}

std::unique_ptr<DocumentObject> ObjectLayer::take(ObjectId id)
{
    const qsizetype index = indexOf(id);
    if (index < 0)
        return nullptr;

    auto owned = std::move(objects_[static_cast<size_t>(index)]);
    objects_.erase(objects_.begin() + index);
    return owned;
}

bool ObjectLayer::remove(ObjectId id)
{
    return take(id) != nullptr;
}

void ObjectLayer::clear()
{
    objects_.clear();
}

DocumentObject *ObjectLayer::object(ObjectId id)
{
    const qsizetype index = indexOf(id);
    return index < 0 ? nullptr : objectAt(index);
}

const DocumentObject *ObjectLayer::object(ObjectId id) const
{
    const qsizetype index = indexOf(id);
    return index < 0 ? nullptr : objectAt(index);
}

DocumentObject *ObjectLayer::objectAt(qsizetype index)
{
    if (index < 0 || index >= size())
        return nullptr;
    return objects_[static_cast<size_t>(index)].get();
}

const DocumentObject *ObjectLayer::objectAt(qsizetype index) const
{
    if (index < 0 || index >= size())
        return nullptr;
    return objects_[static_cast<size_t>(index)].get();
}

qsizetype ObjectLayer::indexOf(ObjectId id) const
{
    for (qsizetype i = 0; i < size(); ++i) {
        if (objects_[static_cast<size_t>(i)]->id() == id)
            return i;
    }
    return -1;
}

QList<ObjectId> ObjectLayer::ids() const
{
    QList<ObjectId> result;
    result.reserve(size());
    for (const auto &object : objects_)
        result.append(object->id());
    return result;
}

bool ObjectLayer::raise(ObjectId id)
{
    const qsizetype index = indexOf(id);
    if (index < 0 || index + 1 >= size())
        return false;
    return moveTo(id, index + 1);
}

bool ObjectLayer::lower(ObjectId id)
{
    const qsizetype index = indexOf(id);
    if (index <= 0)
        return false;
    return moveTo(id, index - 1);
}

bool ObjectLayer::bringToFront(ObjectId id)
{
    const qsizetype index = indexOf(id);
    if (index < 0 || index == size() - 1)
        return false;
    return moveTo(id, size() - 1);
}

bool ObjectLayer::sendToBack(ObjectId id)
{
    const qsizetype index = indexOf(id);
    if (index <= 0)
        return false;
    return moveTo(id, 0);
}

bool ObjectLayer::moveTo(ObjectId id, qsizetype index)
{
    const auto it = std::find_if(objects_.begin(), objects_.end(),
        [id](const std::unique_ptr<DocumentObject> &object) {
            return object->id() == id;
        });
    if (it == objects_.end())
        return false;

    const qsizetype from = static_cast<qsizetype>(std::distance(objects_.begin(), it));
    const qsizetype last = size() - 1;
    const qsizetype target = std::clamp<qsizetype>(index, 0, last);
    if (target == from)
        return false;

    auto owned = std::move(*it);
    objects_.erase(it);
    // The erase shrinks the container by one; clamping against the new size
    // gives `target` the intended final z-index.
    const qsizetype insertion = std::clamp<qsizetype>(target, 0, size());
    objects_.insert(objects_.begin() + insertion, std::move(owned));
    return true;
}

void ObjectLayer::renderOnto(QImage &target) const
{
    if (target.isNull())
        return;

    QPainter painter(&target);
    if (!painter.isActive())
        return;

    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setCompositionMode(QPainter::CompositionMode_SourceOver);

    // The target image is never re-created or converted, so its format,
    // colour space, DPI and untouched alpha are preserved by construction.
    for (const auto &object : objects_) {
        if (object->isVisible())
            object->render(painter);
    }
}

ObjectId ObjectLayer::hitTest(const QPointF &point, qreal tolerance) const
{
    for (auto it = objects_.rbegin(); it != objects_.rend(); ++it) {
        const DocumentObject *object = it->get();
        if (!object->isVisible() || object->isLocked())
            continue;
        if (object->hitTest(point, tolerance))
            return object->id();
    }
    return InvalidObjectId;
}

void ObjectLayer::applyTransform(const QTransform &transform)
{
    for (const auto &object : objects_)
        object->applyTransform(transform);
}

void ObjectLayer::crop(const QRect &kept, const QPoint &offset)
{
    const QRectF keptRect = QRectF(kept).normalized();

    for (auto it = objects_.begin(); it != objects_.end();) {
        if ((*it)->bounds().intersects(keptRect))
            ++it;
        else
            it = objects_.erase(it);
    }

    if (!offset.isNull())
        applyTransform(QTransform::fromTranslate(offset.x(), offset.y()));
}

void ObjectLayer::crop(const QRect &kept)
{
    crop(kept, -kept.topLeft());
}

} // namespace NekoPic::Document
