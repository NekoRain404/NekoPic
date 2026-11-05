#include "formatregistry.h"

#include <QFileInfo>
#include <QImageReader>
#include <QImageWriter>
#include <QMap>
#include <algorithm>

namespace NekoPic::Io {
namespace {

const QStringList &preferredOrder()
{
    static const QStringList order{QStringLiteral("png"), QStringLiteral("jpeg"),
                                   QStringLiteral("webp"), QStringLiteral("tiff"),
                                   QStringLiteral("gif"), QStringLiteral("bmp")};
    return order;
}

void appendUnique(QStringList &target, const QString &value)
{
    const auto normalized = value.trimmed().toLower();
    if (!normalized.isEmpty() && !target.contains(normalized))
        target.append(normalized);
}

int orderIndex(const QString &id)
{
    const int index = preferredOrder().indexOf(id);
    return index < 0 ? preferredOrder().size() : index;
}

} // namespace

FormatRegistry::FormatRegistry()
{
    QMap<QString, FormatCapability> byId;
    const auto readerFormats = QImageReader::supportedImageFormats();
    for (const auto &raw : readerFormats) {
        const auto id = QString::fromLatin1(raw).toLower();
        auto &capability = byId[id];
        capability.id = id;
        appendUnique(capability.readExtensions, id);
    }
    const auto writerFormats = QImageWriter::supportedImageFormats();
    for (const auto &raw : writerFormats) {
        const auto id = QString::fromLatin1(raw).toLower();
        auto &capability = byId[id];
        capability.id = id;
        appendUnique(capability.writeExtensions, id);
    }

    // Common aliases users expect in file dialogs.
    if (byId.contains(QStringLiteral("jpeg"))) {
        appendUnique(byId[QStringLiteral("jpeg")].readExtensions, QStringLiteral("jpg"));
        appendUnique(byId[QStringLiteral("jpeg")].writeExtensions, QStringLiteral("jpg"));
    }
    if (byId.contains(QStringLiteral("tiff"))) {
        appendUnique(byId[QStringLiteral("tiff")].readExtensions, QStringLiteral("tif"));
        appendUnique(byId[QStringLiteral("tiff")].writeExtensions, QStringLiteral("tif"));
    }

    formats_ = byId.values();
    std::sort(formats_.begin(), formats_.end(), [](const auto &left, const auto &right) {
        const int leftOrder = orderIndex(left.id);
        const int rightOrder = orderIndex(right.id);
        if (leftOrder != rightOrder) return leftOrder < rightOrder;
        return left.id < right.id;
    });
}

const FormatRegistry &FormatRegistry::instance()
{
    static const FormatRegistry registry;
    return registry;
}

QList<FormatCapability> FormatRegistry::formats() const { return formats_; }

QStringList FormatRegistry::readableExtensions() const
{
    QStringList result;
    for (const auto &format : formats_) {
        for (const auto &extension : format.readExtensions)
            appendUnique(result, extension);
    }
    return result;
}

QStringList FormatRegistry::writableExtensions() const
{
    QStringList result;
    for (const auto &format : formats_) {
        for (const auto &extension : format.writeExtensions)
            appendUnique(result, extension);
    }
    return result;
}

QStringList FormatRegistry::readablePatterns() const
{
    QStringList patterns;
    for (const auto &extension : readableExtensions()) {
        patterns.append(QStringLiteral("*.") + extension);
        patterns.append(QStringLiteral("*.") + extension.toUpper());
    }
    return patterns;
}

QStringList FormatRegistry::writablePatterns() const
{
    QStringList patterns;
    for (const auto &extension : writableExtensions()) {
        patterns.append(QStringLiteral("*.") + extension);
        patterns.append(QStringLiteral("*.") + extension.toUpper());
    }
    return patterns;
}

bool FormatRegistry::canReadExtension(const QString &extension) const
{
    const auto normalized = extension.trimmed().toLower();
    for (const auto &format : formats_) {
        if (format.readExtensions.contains(normalized)) return true;
    }
    return false;
}

bool FormatRegistry::canWriteExtension(const QString &extension) const
{
    const auto normalized = extension.trimmed().toLower();
    for (const auto &format : formats_) {
        if (format.writeExtensions.contains(normalized)) return true;
    }
    return false;
}

QString FormatRegistry::formatIdForUrl(const QUrl &url) const
{
    const auto suffix = QFileInfo(url.toLocalFile()).suffix().toLower();
    for (const auto &format : formats_) {
        if (format.readExtensions.contains(suffix)) return format.id;
    }
    return {};
}

} // namespace NekoPic::Io
