#include "platform/recentfiles.h"

#include <QSettings>
#include <QTemporaryDir>
#include <QtTest>

using NekoPic::Platform::RecentFiles;

namespace {
QUrl urlFor(const QString &path) { return QUrl::fromLocalFile(path); }
}

class RecentFilesTest final : public QObject {
    Q_OBJECT
private slots:
    void init()
    {
        QCoreApplication::setOrganizationName(QStringLiteral("NekoPicTest"));
        QCoreApplication::setApplicationName(QStringLiteral("RecentFilesTest"));
        QSettings().clear();
    }

    void addsNewestFirstAndDeduplicates()
    {
        RecentFiles recent;
        recent.add(urlFor(QStringLiteral("/tmp/a.png")));
        recent.add(urlFor(QStringLiteral("/tmp/b.png")));
        recent.add(urlFor(QStringLiteral("/tmp/a.png")));
        const auto entries = recent.entries();
        QCOMPARE(entries.size(), 2);
        QCOMPARE(entries.first().toMap().value(QStringLiteral("path")).toString(),
                 QStringLiteral("/tmp/a.png"));
        QCOMPARE(entries.last().toMap().value(QStringLiteral("name")).toString(),
                 QStringLiteral("b.png"));
    }

    void enforcesMaximum()
    {
        RecentFiles recent(3);
        for (int i = 0; i < 5; ++i)
            recent.add(urlFor(QStringLiteral("/tmp/%1.png").arg(i)));
        QCOMPARE(recent.entries().size(), 3);
        QCOMPARE(recent.entries().first().toMap().value(QStringLiteral("path")).toString(),
                 QStringLiteral("/tmp/4.png"));
    }

    void persistsAcrossInstances()
    {
        RecentFiles first;
        first.add(urlFor(QStringLiteral("/tmp/keep.png")));
        RecentFiles second;
        QCOMPARE(second.entries().size(), 1);
        QCOMPARE(second.entries().first().toMap().value(QStringLiteral("path")).toString(),
                 QStringLiteral("/tmp/keep.png"));
    }

    void removesAndClears()
    {
        RecentFiles recent;
        recent.add(urlFor(QStringLiteral("/tmp/a.png")));
        recent.add(urlFor(QStringLiteral("/tmp/b.png")));
        recent.remove(urlFor(QStringLiteral("/tmp/a.png")));
        QCOMPARE(recent.entries().size(), 1);
        recent.clear();
        QCOMPARE(recent.entries().size(), 0);
        QCOMPARE(QSettings().value(QStringLiteral("recent/files")).toStringList().size(), 0);
    }

    void ignoresNonLocalUrls()
    {
        RecentFiles recent;
        recent.add(QUrl(QStringLiteral("https://example.com/a.png")));
        QCOMPARE(recent.entries().size(), 0);
    }
};

QTEST_MAIN(RecentFilesTest)
#include "tst_recentfiles.moc"
