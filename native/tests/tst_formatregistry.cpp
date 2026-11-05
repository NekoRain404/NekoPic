#include "io/formatregistry.h"

#include <QGuiApplication>
#include <QtTest>

using NekoPic::Io::FormatRegistry;

class FormatRegistryTest final : public QObject {
    Q_OBJECT
private slots:
    void reportsPngAsReadableAndWritable()
    {
        const auto &registry = FormatRegistry::instance();
        QVERIFY(registry.canReadExtension(QStringLiteral("png")));
        QVERIFY(registry.canWriteExtension(QStringLiteral("png")));
        QVERIFY(registry.readablePatterns().contains(QStringLiteral("*.png")));
    }

    void normalizesExtensionCase()
    {
        const auto &registry = FormatRegistry::instance();
        QVERIFY(registry.canReadExtension(QStringLiteral(" JPG ")));
        QCOMPARE(registry.formatIdForUrl(QUrl::fromLocalFile(QStringLiteral("/tmp/photo.JPEG"))),
                 QStringLiteral("jpeg"));
    }

    void rejectsUnknownExtension()
    {
        const auto &registry = FormatRegistry::instance();
        QVERIFY(!registry.canReadExtension(QStringLiteral("neko")));
        QVERIFY(registry.formatIdForUrl(QUrl::fromLocalFile(QStringLiteral("/tmp/a.neko"))).isEmpty());
    }

    void formatsHaveConsistentIds()
    {
        for (const auto &format : FormatRegistry::instance().formats()) {
            QVERIFY(!format.id.isEmpty());
            QVERIFY(format.readExtensions.contains(format.id) || format.writeExtensions.contains(format.id));
        }
    }
};

QTEST_MAIN(FormatRegistryTest)
#include "tst_formatregistry.moc"
