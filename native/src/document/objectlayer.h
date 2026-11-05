#pragma once

#include "document/object.h"

#include <QImage>
#include <QList>
#include <QPoint>
#include <QRect>
#include <QTransform>

#include <memory>
#include <vector>

namespace NekoPic::Document {

// Ordered, owning collection of document objects. Index 0 is the bottom of
// the z-order; the last element is painted last and is therefore on top.
// All coordinates are document image pixels (see object.h).
class ObjectLayer {
public:
    ObjectLayer() = default;

    ObjectLayer(const ObjectLayer &) = delete;
    ObjectLayer &operator=(const ObjectLayer &) = delete;

    // Moving transfers ownership of the object list and is used to install a
    // freshly built layer (for example a transformed clone) atomically.
    ObjectLayer(ObjectLayer &&) noexcept = default;
    ObjectLayer &operator=(ObjectLayer &&) noexcept = default;

    // Takes ownership and returns the object's stable id. Null is ignored.
    ObjectId add(std::unique_ptr<DocumentObject> object);

    // Removes and returns ownership; nullptr when the id is unknown.
    std::unique_ptr<DocumentObject> take(ObjectId id);
    bool remove(ObjectId id);
    void clear();

    qsizetype size() const { return static_cast<qsizetype>(objects_.size()); }
    bool isEmpty() const { return objects_.empty(); }

    DocumentObject *object(ObjectId id);
    const DocumentObject *object(ObjectId id) const;
    DocumentObject *objectAt(qsizetype index);
    const DocumentObject *objectAt(qsizetype index) const;
    qsizetype indexOf(ObjectId id) const;
    QList<ObjectId> ids() const; // bottom to top

    const std::vector<std::unique_ptr<DocumentObject>> &objects() const { return objects_; }

    // Reordering. Each returns false when the id is unknown or the move is a
    // no-op (already at the requested end).
    bool raise(ObjectId id);        // one step towards the top
    bool lower(ObjectId id);        // one step towards the bottom
    bool bringToFront(ObjectId id); // topmost
    bool sendToBack(ObjectId id);   // bottom-most
    bool moveTo(ObjectId id, qsizetype index); // final z-index

    // Paints visible objects over the target, preserving the target's format,
    // colour space, DPI and existing alpha (SourceOver composition). The
    // target may already contain the merged image or be transparent.
    void renderOnto(QImage &target) const;

    // Topmost object whose local shape contains point (document pixels).
    // Invisible and locked objects are skipped. Returns InvalidObjectId on a
    // miss.
    ObjectId hitTest(const QPointF &point, qreal tolerance = 0.0) const;

    // Applies the same document-space transform to every object, for image
    // rotate/flip/scale. The same matrix should be applied to the pixels by
    // the caller.
    void applyTransform(const QTransform &transform);

    // After a crop, remove objects entirely outside kept and translate the
    // remaining coordinates by offset (normally -kept.topLeft()). Objects that
    // partially overlap kept stay whole; rendering into the cropped target
    // clips them visually. The kept rectangle is in pre-crop coordinates.
    void crop(const QRect &kept, const QPoint &offset);
    // Convenience overload: new origin becomes kept.topLeft().
    void crop(const QRect &kept);

    // Deep copy of every object, preserving ids. The returned layer is owned
    // by the caller and shares no mutable state with this one. Used to take
    // immutable history snapshots and to stage worker-thread edits.
    std::shared_ptr<ObjectLayer> clone() const;

    // Replaces the contents with a deep copy of other, preserving ids. The
    // source (normally a history snapshot) is left untouched.
    void restoreFrom(const ObjectLayer &other);

private:
    std::vector<std::unique_ptr<DocumentObject>> objects_;
};

} // namespace NekoPic::Document
