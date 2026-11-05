#include "document/object.h"

#include <QPainter>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <utility>

namespace NekoPic::Document {

namespace {

std::atomic<ObjectId> g_nextObjectId{1};

ObjectId allocateObjectId()
{
    return g_nextObjectId.fetch_add(1, std::memory_order_relaxed);
}

} // namespace

DocumentObject::DocumentObject(ObjectKind kind)
    : id_(allocateObjectId())
    , kind_(kind)
{
}

DocumentObject::DocumentObject(const DocumentObject &other)
    : transform_(other.transform_)
    , id_(allocateObjectId())
    , kind_(other.kind_)
    , visible_(other.visible_)
    , locked_(other.locked_)
    , opacity_(other.opacity_)
{
}

DocumentObject::~DocumentObject() = default;

void DocumentObject::setOpacity(qreal opacity)
{
    opacity_ = std::clamp(opacity, 0.0, 1.0);
}

QPointF DocumentObject::translation() const
{
    return QPointF(transform_.dx(), transform_.dy());
}

void DocumentObject::setTranslation(const QPointF &translation)
{
    transform_ = QTransform(transform_.m11(), transform_.m12(),
                            transform_.m21(), transform_.m22(),
                            translation.x(), translation.y());
}

void DocumentObject::applyTransform(const QTransform &transform)
{
    // Qt maps points as p' = p * M. The object's current mapping takes local
    // coordinates into document space, so the external document-space
    // transform must be applied after it: p * (current * external).
    transform_ = transform_ * transform;
}

QRectF DocumentObject::bounds() const
{
    return transform_.mapRect(localBounds());
}

void DocumentObject::render(QPainter &painter) const
{
    if (!visible_ || opacity_ <= 0.0)
        return;

    painter.save();
    painter.setTransform(transform_, true);
    painter.setOpacity(painter.opacity() * opacity_);
    renderLocal(painter);
    painter.restore();
}

bool DocumentObject::hitTest(const QPointF &point, qreal tolerance) const
{
    if (!visible_ || locked_)
        return false;

    bool invertible = false;
    const QTransform inverse = transform_.inverted(&invertible);
    if (!invertible)
        return false;

    // Tolerance is expressed in document pixels. Convert it into the object's
    // local space using the (uniform) scale of the inverse mapping. For the
    // non-uniform/sheared transforms allowed by QTransform this is an
    // approximation that keeps hit testing stable.
    const qreal determinant = std::abs(transform_.determinant());
    const qreal scale = determinant > 1e-12 ? std::sqrt(determinant) : 0.0;
    const qreal localTolerance = scale > 0.0 ? std::max<qreal>(0.0, tolerance) / scale : 0.0;

    return hitTestLocal(inverse.map(point), localTolerance);
}

std::unique_ptr<DocumentObject> DocumentObject::clone() const
{
    return cloneImpl();
}

std::unique_ptr<DocumentObject> DocumentObject::clonePreservingId() const
{
    auto copy = cloneImpl();
    // cloneImpl() allocates a fresh id; history snapshots must keep the
    // original so selections survive undo/redo.
    copy->id_ = id_;
    return copy;
}

} // namespace NekoPic::Document
