#pragma once

#include <QPointF>
#include <QRectF>
#include <QTransform>
#include <memory>

class QPainter;

namespace NekoPic::Document {

// Stable, process-wide monotonic identifier. Ids are never reused, so a
// selection or history entry that refers to an object can be validated after
// removal by looking it up in the owning ObjectLayer.
using ObjectId = quint64;
inline constexpr ObjectId InvalidObjectId = 0;

enum class ObjectKind { Text, Shape, Stroke };

// Abstract editable object.
//
// Coordinate contract: all geometry and public hit-test/bounds values are in
// continuous document image pixels - origin at the image's top-left corner,
// y pointing down. The stored transform maps local object coordinates into
// document coordinates. Rotation/flip/scale are therefore applied once to
// the object's transform (and equivalently to pixels by the caller) instead
// of mutating each object's geometry.
//
// Object state (visibility, lock, opacity) is applied by the non-virtual
// entry points below; subclasses only render and hit-test their local shape.
class DocumentObject {
public:
    virtual ~DocumentObject();

    ObjectId id() const { return id_; }
    ObjectKind kind() const { return kind_; }

    bool isVisible() const { return visible_; }
    void setVisible(bool visible) { visible_ = visible; }

    // Locked objects are skipped by ObjectLayer::hitTest, matching the
    // contract that the UI cannot select them.
    bool isLocked() const { return locked_; }
    void setLocked(bool locked) { locked_ = locked; }

    qreal opacity() const { return opacity_; }
    void setOpacity(qreal opacity); // clamped to [0, 1]

    const QTransform &transform() const { return transform_; }
    void setTransform(const QTransform &transform) { transform_ = transform; }

    // Translation component of the affine transform. Setting it keeps the
    // linear part (rotation/scale/flip) intact. Projective components are
    // not supported.
    QPointF translation() const;
    void setTranslation(const QPointF &translation);

    // Applies a transform expressed in document coordinates after the
    // object's current mapping (p * current * transform in Qt's row-vector
    // convention). This rotates/flips/translates the object exactly like the
    // pixels it sits on.
    void applyTransform(const QTransform &transform);

    // Axis-aligned bounding box in document coordinates, after transform.
    QRectF bounds() const;

    // Applies transform_ and opacity_ before delegating to renderLocal().
    // Invisible or fully transparent objects draw nothing.
    void render(QPainter &painter) const;

    // Point and tolerance are in document pixels. Locked/invisible objects
    // never hit. Non-invertible transforms never hit either.
    bool hitTest(const QPointF &point, qreal tolerance) const;

    // Deep copy with a fresh ObjectId; the copy is independent of this object.
    std::unique_ptr<DocumentObject> clone() const;

    // Deep copy that keeps the source ObjectId. Document history snapshots use
    // this so undo/redo restores the exact object set, including the ids that a
    // selection or tool may still refer to. The copy is independent otherwise.
    std::unique_ptr<DocumentObject> clonePreservingId() const;

protected:
    explicit DocumentObject(ObjectKind kind);
    DocumentObject(const DocumentObject &other); // fresh id, copied state
    DocumentObject &operator=(const DocumentObject &other) = delete;

    // Local-space geometry (before transform_).
    virtual QRectF localBounds() const = 0;
    virtual void renderLocal(QPainter &painter) const = 0;
    // Tolerance has already been converted from document to local units.
    virtual bool hitTestLocal(const QPointF &localPoint, qreal localTolerance) const = 0;
    virtual std::unique_ptr<DocumentObject> cloneImpl() const = 0;

    QTransform transform_;

private:
    ObjectId id_;
    ObjectKind kind_;
    bool visible_ = true;
    bool locked_ = false;
    qreal opacity_ = 1.0;
};

} // namespace NekoPic::Document
