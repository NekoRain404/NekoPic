#pragma once

#include "document/object.h"

#include <QColor>
#include <QFont>
#include <QList>
#include <QString>

namespace NekoPic::Document {

// Multi-line text object. Line breaks are explicit ('\n'); there is no
// automatic word wrapping. Text is rendered as vector glyph outlines through
// QPainterPath::addText, which resolves system font fallback for CJK and
// other scripts. Bounds (document pixels) cover the ink plus padding and half
// of any outline width.
class TextObject final : public DocumentObject {
public:
    TextObject();
    explicit TextObject(QString text);

    QString text() const { return text_; }
    void setText(QString text);

    const QFont &font() const { return font_; }
    void setFont(const QFont &font);

    QString fontFamily() const { return font_.family(); }
    void setFontFamily(const QString &family);

    int fontWeight() const { return static_cast<int>(font_.weight()); }
    void setFontWeight(int weight); // QFont weight, clamped to [1, 1000]

    qreal fontPointSize() const { return font_.pointSizeF(); }
    void setFontPointSize(qreal size);

    QColor color() const { return color_; }
    void setColor(const QColor &color) { color_ = color; }

    Qt::Alignment alignment() const { return alignment_; }
    void setAlignment(Qt::Alignment alignment); // horizontal component only

    // Multiplier applied to the font's natural line spacing (1.0 = normal).
    qreal lineHeight() const { return lineHeight_; }
    void setLineHeight(qreal multiplier);

    QColor outlineColor() const { return outlineColor_; }
    void setOutlineColor(const QColor &color) { outlineColor_ = color; }

    qreal outlineWidth() const { return outlineWidth_; }
    void setOutlineWidth(qreal width);

    // Space between the text ink and the object's box on every side.
    qreal padding() const { return padding_; }
    void setPadding(qreal padding);

protected:
    QRectF localBounds() const override;
    void renderLocal(QPainter &painter) const override;
    bool hitTestLocal(const QPointF &localPoint, qreal localTolerance) const override;
    std::unique_ptr<DocumentObject> cloneImpl() const override;

private:
    struct LineLayout {
        QString text;
        qreal advance = 0.0;
        qreal x = 0.0;
        qreal top = 0.0;
        qreal baseline = 0.0;
        qreal lineHeight = 0.0;
        QRectF ink;
    };

    struct Layout {
        QList<LineLayout> lines;
        QRectF ink;
        QRectF box;
    };

    // Layouts the text in local coordinates. Alignment is computed against
    // the widest line, so alignment has an effect without an explicit width.
    Layout layout() const;

    QString text_;
    QFont font_;
    QColor color_ = QColor(Qt::black);
    Qt::Alignment alignment_ = Qt::AlignLeft;
    qreal lineHeight_ = 1.0;
    QColor outlineColor_ = QColor(Qt::transparent);
    qreal outlineWidth_ = 0.0;
    qreal padding_ = 4.0;
};

} // namespace NekoPic::Document
