#include "documentcontroller.h"

#include "document/textobject.h"

#include <QFont>

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
