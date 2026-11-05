#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QUrl>

#include <optional>

namespace NekoPic::Io {

// Capabilities actually provided by the codecs compiled into this build.
// Extensions are reported without a leading dot and in lower case.
struct FormatCapability {
    QString id;
    QStringList readExtensions;
    QStringList writeExtensions;
    QString provider = QStringLiteral("qt");
    bool optional = false;
};

// Central, read-only view of what this build can decode and encode.
// Call after QGuiApplication exists so Qt image plugins are discoverable.
class FormatRegistry final {
public:
    static const FormatRegistry &instance();

    QList<FormatCapability> formats() const;
    QStringList readableExtensions() const;
    QStringList writableExtensions() const;
    QStringList readablePatterns() const;
    QStringList writablePatterns() const;

    bool canReadExtension(const QString &extension) const;
    bool canWriteExtension(const QString &extension) const;
    QString formatIdForUrl(const QUrl &url) const;
    QString writeFormatIdForUrl(const QUrl &url) const;

    std::optional<FormatCapability> capability(const QString &id) const;
    QString preferredSuffix(const QString &id) const;
    QString displayName(const QString &id) const;

private:
    FormatRegistry();
    QList<FormatCapability> formats_;
};

} // namespace NekoPic::Io
