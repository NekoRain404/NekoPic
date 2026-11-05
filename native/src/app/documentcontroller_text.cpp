#include "documentcontroller.h"

#include "document/textobject.h"

#include <QFont>
#include <QTransform>

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

bool finiteCoordinate(qreal value)
{
    return std::isfinite(value) && std::abs(value) <= 1e7;
}

bool validRange(qreal value, qreal minimum, qreal maximum)
{
    return std::isfinite(value) && value >= minimum && value <= maximum;
}

// Selects the point of a box that an alignment anchors to: either edge, or
// the centre when neither horizontal/vertical flag is present.
qreal alignedAnchor(qreal low, qreal high, bool atLow, bool atHigh)
{
    if (atLow) return low;
    if (atHigh) return high;
    return (low + high) / 2.0;
}

qreal anchorXFor(const QRectF &box, Qt::Alignment alignment)
{
    return alignedAnchor(box.left(), box.right(), alignment & Qt::AlignLeft,
                         alignment & Qt::AlignRight);
}

qreal anchorYFor(const QRectF &box, Qt::Alignment alignment)
{
    return alignedAnchor(box.top(), box.bottom(), alignment & Qt::AlignTop,
                         alignment & Qt::AlignBottom);
}

} // namespace

void DocumentController::addText(const QString &text, qreal x, qreal y, qreal fontSize,
                                 const QColor &color, int alignment)
{
    // Keep the historical command unchanged by delegating to the styled path
    // with the defaults TextObject would otherwise use.
    addTextStyled(text, x, y, QFont().family(), QFont::Normal, fontSize, color, alignment,
                  QColor(Qt::transparent), 0.0, 1.0, 4.0);
}

void DocumentController::addTextStyled(const QString &text, qreal x, qreal y,
                                       const QString &fontFamily, int fontWeight,
                                       qreal fontSize, const QColor &color, int alignment,
                                       const QColor &outlineColor, qreal outlineWidth,
                                       qreal lineHeight, qreal padding)
{
    if (text.trimmed().isEmpty()) return;
    if (!finiteCoordinate(x) || !finiteCoordinate(y)) return;
    if (!std::isfinite(fontSize)) return;
    if (!validRange(outlineWidth, 0.0, 64.0)) return;
    if (!validRange(lineHeight, 0.5, 4.0)) return;
    if (!validRange(padding, 0.0, 256.0)) return;
    if (busy_ || !hasImage()) return;

    const qreal size = std::clamp(fontSize, 4.0, 512.0);
    const int weight = std::clamp(fontWeight, 1, 1000);
    const Qt::Alignment align = static_cast<Qt::Alignment>(alignment);
    const QColor ink = color.isValid() ? color : QColor(Qt::black);
    const QColor outline = outlineColor.isValid() ? outlineColor : QColor(Qt::transparent);
    const QString family = fontFamily.trimmed();

    startObjectEdit([text, x, y, family, weight, size, ink, align, outline, outlineWidth,
                     lineHeight, padding](NekoPic::Document::ObjectLayer &layer) {
        auto object = std::make_unique<NekoPic::Document::TextObject>(text);
        if (!family.isEmpty())
            object->setFontFamily(family);
        object->setFontWeight(weight);
        object->setFontPointSize(size);
        object->setColor(ink);
        object->setAlignment(align);
        object->setOutlineColor(outline);
        object->setOutlineWidth(outlineWidth);
        object->setLineHeight(lineHeight);
        object->setPadding(padding);

        // Place the selected point of the text box at the requested anchor,
        // matching addText(): horizontal and vertical flag groups select which
        // edge (or centre) of the box touches the anchor.
        const QRectF box = object->bounds();
        qreal dx = 0.0;
        if (align & Qt::AlignLeft)
            dx = x - box.left();
        else if (align & Qt::AlignRight)
            dx = x - box.right();
        else
            dx = x - box.center().x();

        qreal dy = 0.0;
        if (align & Qt::AlignTop)
            dy = y - box.top();
        else if (align & Qt::AlignBottom)
            dy = y - box.bottom();
        else
            dy = y - box.center().y();

        object->setTranslation(QPointF(dx, dy));
        return layer.add(std::move(object)) != NekoPic::Document::InvalidObjectId;
    });
}

QVariantMap DocumentController::textInfo(quint64 id) const
{
    if (id == NekoPic::Document::InvalidObjectId) return {};
    const auto *base = objects_.object(id);
    if (!base || base->kind() != NekoPic::Document::ObjectKind::Text) return {};

    const auto *object = static_cast<const NekoPic::Document::TextObject *>(base);
    // The stored transform is normally a pure translation. Deriving the
    // anchor from the document-space bounds means the value stays correct
    // after moveObject(), not just after creation.
    const QRectF box = object->bounds();
    // TextObject persists only the horizontal component of its alignment:
    // vertical flags are a placement-only hint. Report the vertical centre
    // anchor, which is the same default addTextStyled() uses when no vertical
    // flag is present, so info -> update -> info is stable.
    Qt::Alignment alignment = object->alignment();
    if (!(alignment & Qt::AlignVertical_Mask))
        alignment |= Qt::AlignVCenter;

    QVariantMap info;
    info.insert(QStringLiteral("id"), QVariant::fromValue<qulonglong>(id));
    info.insert(QStringLiteral("text"), object->text());
    info.insert(QStringLiteral("x"), anchorXFor(box, alignment));
    info.insert(QStringLiteral("y"), anchorYFor(box, alignment));
    info.insert(QStringLiteral("fontFamily"), object->fontFamily());
    info.insert(QStringLiteral("fontWeight"), object->fontWeight());
    info.insert(QStringLiteral("fontSize"), object->fontPointSize());
    info.insert(QStringLiteral("color"), object->color());
    info.insert(QStringLiteral("alignment"), static_cast<int>(alignment));
    info.insert(QStringLiteral("outlineColor"), object->outlineColor());
    info.insert(QStringLiteral("outlineWidth"), object->outlineWidth());
    info.insert(QStringLiteral("lineHeight"), object->lineHeight());
    info.insert(QStringLiteral("padding"), object->padding());
    return info;
}

bool DocumentController::updateText(quint64 id, const QString &text, qreal x, qreal y,
                                    const QString &fontFamily, int fontWeight, qreal fontSize,
                                    const QColor &color, int alignment,
                                    const QColor &outlineColor, qreal outlineWidth,
                                    qreal lineHeight, qreal padding)
{
    // Same validation as addTextStyled(); anything it would reject or ignore
    // is reported as a failed update here.
    if (text.trimmed().isEmpty()) return false;
    if (!finiteCoordinate(x) || !finiteCoordinate(y)) return false;
    if (!std::isfinite(fontSize)) return false;
    if (!validRange(outlineWidth, 0.0, 64.0)) return false;
    if (!validRange(lineHeight, 0.5, 4.0)) return false;
    if (!validRange(padding, 0.0, 256.0)) return false;
    if (busy_ || !hasImage()) return false;

    const auto *existing = objects_.object(id);
    if (!existing || existing->kind() != NekoPic::Document::ObjectKind::Text)
        return false;

    const qreal size = std::clamp(fontSize, 4.0, 512.0);
    const int weight = std::clamp(fontWeight, 1, 1000);
    const Qt::Alignment align = static_cast<Qt::Alignment>(alignment);
    const QColor ink = color.isValid() ? color : QColor(Qt::black);
    const QColor outline = outlineColor.isValid() ? outlineColor : QColor(Qt::transparent);
    const QString family = fontFamily.trimmed();
    // An empty family means the system default, matching addTextStyled().
    const QString resolvedFamily = family.isEmpty() ? QFont().family() : family;

    startObjectEdit([id, text, x, y, resolvedFamily, weight, size, ink, align, outline,
                     outlineWidth, lineHeight, padding](
                        NekoPic::Document::ObjectLayer &layer) {
        auto *base = layer.object(id);
        if (!base || base->kind() != NekoPic::Document::ObjectKind::Text)
            return false;
        auto *object = static_cast<NekoPic::Document::TextObject *>(base);

        // Rebuild the editable state in place: keep the id and z-order, but
        // replace text, style and position. Drop only the translation so the
        // anchor calculation below works in document space. The linear part
        // (rotation/flip/scale from a document transform) is preserved.
        const QTransform current = object->transform();
        object->setTransform(QTransform(current.m11(), current.m12(),
                                        current.m21(), current.m22(), 0.0, 0.0));
        object->setText(text);
        object->setFontFamily(resolvedFamily);
        object->setFontWeight(weight);
        object->setFontPointSize(size);
        object->setColor(ink);
        object->setAlignment(align);
        object->setOutlineColor(outline);
        object->setOutlineWidth(outlineWidth);
        object->setLineHeight(lineHeight);
        object->setPadding(padding);

        const QRectF box = object->bounds();
        const qreal dx = x - anchorXFor(box, align);
        const qreal dy = y - anchorYFor(box, align);
        object->setTranslation(QPointF(dx, dy));
        return true;
    });
    return true;
}
