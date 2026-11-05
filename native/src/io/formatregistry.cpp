#include "formatregistry.h"

#include <QFileInfo>
#include <QImageReader>
#include <QImageWriter>
#include <QCoreApplication>
#include <QHash>
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

QString preferredSuffixFor(const QString &id)
{
    if (id == QLatin1String("jpeg")) return QStringLiteral("jpg");
    if (id == QLatin1String("tiff")) return QStringLiteral("tif");
    return id;
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

QString FormatRegistry::writeFormatIdForUrl(const QUrl &url) const
{
    const auto suffix = QFileInfo(url.toLocalFile()).suffix().toLower();
    for (const auto &format : formats_) {
        if (format.writeExtensions.contains(suffix)) return format.id;
    }
    return {};
}

std::optional<FormatCapability> FormatRegistry::capability(const QString &id) const
{
    const auto normalized = id.trimmed().toLower();
    for (const auto &format : formats_) {
        if (format.id == normalized) return format;
    }
    return std::nullopt;
}

QString FormatRegistry::preferredSuffix(const QString &id) const
{
    const auto format = capability(id);
    if (!format || format->writeExtensions.isEmpty()) return {};
    return preferredSuffixFor(format->id);
}

QString FormatRegistry::displayName(const QString &id) const
{
    // Literals go through tr() so the catalogue can translate them.
    static const QHash<QString, QString> names{
        {QStringLiteral("png"), QCoreApplication::translate("FormatRegistry", "PNG image")},
        {QStringLiteral("jpeg"), QCoreApplication::translate("FormatRegistry", "JPEG image")},
        {QStringLiteral("webp"), QCoreApplication::translate("FormatRegistry", "WebP image")},
        {QStringLiteral("tiff"), QCoreApplication::translate("FormatRegistry", "TIFF image")},
        {QStringLiteral("avif"), QCoreApplication::translate("FormatRegistry", "AVIF image")},
        {QStringLiteral("heic"), QCoreApplication::translate("FormatRegistry", "HEIC image")},
        {QStringLiteral("heif"), QCoreApplication::translate("FormatRegistry", "HEIF image")},
        {QStringLiteral("jxl"), QCoreApplication::translate("FormatRegistry", "JPEG XL image")},
        {QStringLiteral("qoi"), QCoreApplication::translate("FormatRegistry", "QOI image")},
        {QStringLiteral("bmp"), QCoreApplication::translate("FormatRegistry", "BMP image")},
        {QStringLiteral("tga"), QCoreApplication::translate("FormatRegistry", "TGA image")},
        {QStringLiteral("exr"), QCoreApplication::translate("FormatRegistry", "OpenEXR image")},
        {QStringLiteral("ico"), QCoreApplication::translate("FormatRegistry", "ICO image")},
    };
    const auto found = names.constFind(id);
    return found != names.cend() ? *found : id.toUpper() + QStringLiteral(" image");
}

} // namespace NekoPic::Io
