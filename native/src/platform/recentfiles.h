#pragma once

#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

namespace NekoPic::Platform {

// Small, persistent most-recently-used list for the File menu.
// Entries are newest first; duplicates move to the front.
class RecentFiles final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(int maximum READ maximum CONSTANT)

public:
    explicit RecentFiles(int maximum = 10, QObject *parent = nullptr);

    QVariantList entries() const;
    int maximum() const;

    void add(const QUrl &url);
    Q_INVOKABLE void remove(const QUrl &url);
    Q_INVOKABLE void clear();

signals:
    void changed();

private:
    void load();
    void save() const;

    QStringList storedPaths_;
    int maximum_;
};

} // namespace NekoPic::Platform
