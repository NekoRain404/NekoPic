#include "document/textobject.h"

#include <QFontMetricsF>
#include <QPainter>
#include <QPainterPath>
#include <QStringList>

#include <algorithm>
#include <utility>

namespace NekoPic::Document {

namespace {

QString stripCarriageReturn(QString line)
{
    if (line.endsWith(QLatin1Char('\r')))
        line.chop(1);
    return line;
}

} // namespace

TextObject::TextObject()
    : DocumentObject(ObjectKind::Text)
{
    font_.setPointSizeF(24.0);
}

TextObject::TextObject(QString text)
    : TextObject()
{
    text_ = std::move(text);
}

void TextObject::setText(QString text)
{
    text_ = std::move(text);
}

void TextObject::setFont(const QFont &font)
{
    font_ = font;
}

void TextObject::setFontFamily(const QString &family)
{
    font_.setFamily(family);
}

void TextObject::setFontWeight(int weight)
{
    font_.setWeight(static_cast<QFont::Weight>(std::clamp(weight, 1, 1000)));
}

void TextObject::setFontPointSize(qreal size)
{
    if (size > 0.0)
        font_.setPointSizeF(size);
}

void TextObject::setAlignment(Qt::Alignment alignment)
{
    const Qt::Alignment horizontal = alignment & Qt::AlignHorizontal_Mask;
    alignment_ = horizontal != 0 ? horizontal : Qt::AlignLeft;
}

void TextObject::setLineHeight(qreal multiplier)
{
    lineHeight_ = std::max<qreal>(0.1, multiplier);
}

void TextObject::setOutlineWidth(qreal width)
{
    outlineWidth_ = std::max<qreal>(0.0, width);
}

void TextObject::setPadding(qreal padding)
{
    padding_ = std::max<qreal>(0.0, padding);
}

TextObject::Layout TextObject::layout() const
{
    Layout result;

    const QFontMetricsF metrics(font_);
    const qreal lineAdvance = std::max<qreal>(0.1, metrics.lineSpacing() * lineHeight_);
    const QStringList rawLines = text_.split(QLatin1Char('\n'), Qt::KeepEmptyParts);

    QList<QString> lines;
    QList<qreal> advances;
    lines.reserve(rawLines.size());
    advances.reserve(rawLines.size());

    qreal widest = 0.0;
    for (const QString &raw : rawLines) {
        const QString line = stripCarriageReturn(raw);
        const qreal advance = metrics.horizontalAdvance(line);
        lines.append(line);
        advances.append(advance);
        widest = std::max(widest, advance);
    }

    qreal y = padding_;
    for (qsizetype i = 0; i < lines.size(); ++i) {
        const QString &line = lines.at(i);
        const qreal advance = advances.at(i);

        qreal x = padding_;
        if (alignment_ & Qt::AlignRight)
            x += widest - advance;
        else if (alignment_ & Qt::AlignHCenter)
            x += (widest - advance) / 2.0;

        const qreal baseline = y + metrics.ascent();

        QRectF ink;
        if (!line.isEmpty()) {
            QPainterPath path;
            path.addText(QPointF(x, baseline), font_, line);
            ink = path.boundingRect();
        }

        LineLayout lineLayout;
        lineLayout.text = line;
        lineLayout.advance = advance;
        lineLayout.x = x;
        lineLayout.top = y;
        lineLayout.baseline = baseline;
        lineLayout.lineHeight = lineAdvance;
        lineLayout.ink = ink;
        result.lines.append(lineLayout);

        if (!ink.isNull())
            result.ink = result.ink.isNull() ? ink : result.ink.united(ink);

        y += lineAdvance;
    }

    const qreal contentHeight = lines.isEmpty()
        ? 0.0
        : (lines.size() - 1) * lineAdvance + metrics.height();
    result.box = QRectF(0.0, 0.0, widest + 2.0 * padding_, contentHeight + 2.0 * padding_);
    return result;
}

QRectF TextObject::localBounds() const
{
    const Layout laidOut = layout();
    QRectF bounds = laidOut.box;

    if (!laidOut.ink.isNull()) {
        QRectF ink = laidOut.ink;
        const qreal grow = outlineWidth_ * 0.5;
        if (grow > 0.0)
            ink.adjust(-grow, -grow, grow, grow);
        bounds = bounds.isNull() ? ink : bounds.united(ink);
    }

    return bounds;
}

void TextObject::renderLocal(QPainter &painter) const
{
    const Layout laidOut = layout();

    QPainterPath path;
    for (const LineLayout &line : laidOut.lines) {
        if (!line.text.isEmpty())
            path.addText(QPointF(line.x, line.baseline), font_, line.text);
    }
    if (path.isEmpty())
        return;

    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setBrush(color_.alpha() > 0 ? QBrush(color_) : QBrush(Qt::NoBrush));
    painter.setPen(outlineWidth_ > 0.0 && outlineColor_.alpha() > 0
        ? QPen(outlineColor_, outlineWidth_, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin)
        : QPen(Qt::NoPen));
    painter.drawPath(path);
}

bool TextObject::hitTestLocal(const QPointF &localPoint, qreal localTolerance) const
{
    // Per-line advance boxes follow the contract ("laid-out line boxes") and
    // avoid treating the ragged whitespace of aligned lines as hits.
    const Layout laidOut = layout();
    for (const LineLayout &line : laidOut.lines) {
        if (line.text.isEmpty())
            continue;

        QRectF lineBox(line.x, line.top, line.advance, line.lineHeight);
        lineBox.adjust(-localTolerance, -localTolerance,
                       localTolerance, localTolerance);
        if (lineBox.contains(localPoint))
            return true;
    }
    return false;
}

std::unique_ptr<DocumentObject> TextObject::cloneImpl() const
{
    return std::make_unique<TextObject>(*this);
}

} // namespace NekoPic::Document
