#include "recentfiles.h"

#include <QFileInfo>
#include <QSettings>

namespace NekoPic::Platform {
namespace {
constexpr auto kKey = "recent/files";
}

RecentFiles::RecentFiles(int maximum, QObject *parent)
    : QObject(parent), maximum_(maximum > 0 ? maximum : 10)
{
    load();
}

QVariantList RecentFiles::entries() const
{
    QVariantList result;
    result.reserve(storedPaths_.size());
    for (const auto &path : storedPaths_) {
        result.append(QVariantMap{
            {QStringLiteral("url"), QUrl::fromLocalFile(path)},
            {QStringLiteral("name"), QFileInfo(path).fileName()},
            {QStringLiteral("path"), path},
        });
    }
    return result;
}

int RecentFiles::maximum() const { return maximum_; }

void RecentFiles::add(const QUrl &url)
{
    if (!url.isLocalFile()) return;
    const auto path = url.toLocalFile();
    if (path.isEmpty()) return;
    storedPaths_.removeAll(path);
    storedPaths_.prepend(path);
    while (storedPaths_.size() > maximum_)
        storedPaths_.removeLast();
    save();
    emit changed();
}

void RecentFiles::remove(const QUrl &url)
{
    if (!url.isLocalFile()) return;
    if (storedPaths_.removeAll(url.toLocalFile()) == 0) return;
    save();
    emit changed();
}

void RecentFiles::clear()
{
    if (storedPaths_.isEmpty()) return;
    storedPaths_.clear();
    save();
    emit changed();
}

void RecentFiles::load()
{
    storedPaths_ = QSettings().value(QLatin1String(kKey)).toStringList();
    storedPaths_.removeAll(QString());
    while (storedPaths_.size() > maximum_)
        storedPaths_.removeLast();
}

void RecentFiles::save() const
{
    QSettings().setValue(QLatin1String(kKey), storedPaths_);
}

} // namespace NekoPic::Platform
