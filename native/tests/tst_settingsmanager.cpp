#include "app/settingsmanager.h"

#include <QSettings>
#include <QSignalSpy>
#include <QtTest>

class SettingsManagerTest final : public QObject {
    Q_OBJECT

private slots:
    void init()
    {
        QCoreApplication::setOrganizationName(QStringLiteral("NekoPicTest"));
        QCoreApplication::setApplicationName(QStringLiteral("SettingsManagerTest"));
        QSettings().clear();
    }

    void cleanup()
    {
        QSettings().clear();
    }

    void defaults()
    {
        SettingsManager settings;

        QCOMPARE(settings.themeMode(), QStringLiteral("dark"));
        QCOMPARE(settings.reduceMotion(), false);
        QCOMPARE(settings.gpuPreviewEnabled(), true);
        QCOMPARE(settings.exportQuality(), -1);
        QVERIFY(settings.jpegBackground().isValid());
        QCOMPARE(settings.jpegBackground().alpha(), 255);
        QCOMPARE(settings.jpegBackground().rgb(), QColor(Qt::white).rgb());
        QCOMPARE(settings.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(settings.confirmOnClose(), true);
        QCOMPARE(settings.showCheckerboard(), true);
        QCOMPARE(settings.recoveryEnabled(), true);
        QCOMPARE(settings.startupTool(), QStringLiteral("adjust"));
    }

    void validatesThemeMode()
    {
        SettingsManager settings;

        settings.setThemeMode(QStringLiteral("system"));
        QCOMPARE(settings.themeMode(), QStringLiteral("system"));
        settings.setThemeMode(QStringLiteral("light"));
        QCOMPARE(settings.themeMode(), QStringLiteral("light"));
        settings.setThemeMode(QStringLiteral("dark"));
        QCOMPARE(settings.themeMode(), QStringLiteral("dark"));

        // Unknown values fall back to the documented default.
        settings.setThemeMode(QStringLiteral("neko"));
        QCOMPARE(settings.themeMode(), QStringLiteral("dark"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/themeMode")).toString(),
                 QStringLiteral("dark"));
    }

    void clampsExportQuality()
    {
        SettingsManager settings;

        settings.setExportQuality(250);
        QCOMPARE(settings.exportQuality(), 100);
        QCOMPARE(QSettings().value(QStringLiteral("ui/exportQuality")).toInt(), 100);

        settings.setExportQuality(-50);
        QCOMPARE(settings.exportQuality(), -1);
        QCOMPARE(QSettings().value(QStringLiteral("ui/exportQuality")).toInt(), -1);

        settings.setExportQuality(0);
        QCOMPARE(settings.exportQuality(), 0);
        settings.setExportQuality(100);
        QCOMPARE(settings.exportQuality(), 100);
        settings.setExportQuality(42);
        QCOMPARE(settings.exportQuality(), 42);
    }

    void keepsJpegBackgroundOpaque()
    {
        SettingsManager settings;

        settings.setJpegBackground(Qt::transparent);
        QCOMPARE(settings.jpegBackground().alpha(), 255);
        QCOMPARE(settings.jpegBackground().rgb(), QColor(Qt::black).rgb());

        settings.setJpegBackground(QColor(20, 40, 60, 0));
        QCOMPARE(settings.jpegBackground().alpha(), 255);
        QCOMPARE(settings.jpegBackground().red(), 20);
        QCOMPARE(settings.jpegBackground().green(), 40);
        QCOMPARE(settings.jpegBackground().blue(), 60);
        QCOMPARE(QSettings().value(QStringLiteral("ui/jpegBackground")).toString(),
                 QStringLiteral("#14283c"));

        // An invalid colour is replaced by the white default rather than stored.
        settings.setJpegBackground(QColor());
        QCOMPARE(settings.jpegBackground().rgb(), QColor(Qt::white).rgb());
        QCOMPARE(settings.jpegBackground().alpha(), 255);
    }

    void validatesLocale()
    {
        SettingsManager settings;

        settings.setLocale(QStringLiteral("en"));
        QCOMPARE(settings.locale(), QStringLiteral("en"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(),
                 QStringLiteral("en"));

        settings.setLocale(QStringLiteral("fr"));
        QCOMPARE(settings.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(),
                 QStringLiteral("zh_CN"));
    }

    void validatesStartupTool()
    {
        SettingsManager settings;

        settings.setStartupTool(QStringLiteral("brush"));
        QCOMPARE(settings.startupTool(), QStringLiteral("brush"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/startupTool")).toString(),
                 QStringLiteral("brush"));

        settings.setStartupTool(QStringLiteral("adjust"));
        QCOMPARE(settings.startupTool(), QStringLiteral("adjust"));

        // Unknown tools fall back to the documented default.
        settings.setStartupTool(QStringLiteral("neko"));
        QCOMPARE(settings.startupTool(), QStringLiteral("adjust"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/startupTool")).toString(),
                 QStringLiteral("adjust"));
    }

    void persistsAcrossInstances()
    {
        {
            SettingsManager settings;
            settings.setThemeMode(QStringLiteral("light"));
            settings.setReduceMotion(true);
            settings.setGpuPreviewEnabled(false);
            settings.setExportQuality(73);
            settings.setJpegBackground(QColor(10, 20, 30));
            settings.setLocale(QStringLiteral("en"));
            settings.setConfirmOnClose(false);
            settings.setShowCheckerboard(false);
            settings.setRecoveryEnabled(false);
            settings.setStartupTool(QStringLiteral("brush"));
        }

        SettingsManager restored;
        QCOMPARE(restored.themeMode(), QStringLiteral("light"));
        QCOMPARE(restored.reduceMotion(), true);
        QCOMPARE(restored.gpuPreviewEnabled(), false);
        QCOMPARE(restored.exportQuality(), 73);
        QCOMPARE(restored.jpegBackground().red(), 10);
        QCOMPARE(restored.jpegBackground().green(), 20);
        QCOMPARE(restored.jpegBackground().blue(), 30);
        QCOMPARE(restored.jpegBackground().alpha(), 255);
        QCOMPARE(restored.locale(), QStringLiteral("en"));
        QCOMPARE(restored.confirmOnClose(), false);
        QCOMPARE(restored.showCheckerboard(), false);
        QCOMPARE(restored.recoveryEnabled(), false);
        QCOMPARE(restored.startupTool(), QStringLiteral("brush"));
    }

    void migratesLegacyDarkTheme_data()
    {
        QTest::addColumn<bool>("legacyDark");
        QTest::addColumn<QString>("expected");

        QTest::newRow("legacy dark -> dark") << true << QStringLiteral("dark");
        QTest::newRow("legacy light -> light") << false << QStringLiteral("light");
    }

    void migratesLegacyDarkTheme()
    {
        QFETCH(bool, legacyDark);
        QFETCH(QString, expected);

        QSettings().setValue(QStringLiteral("ui/darkTheme"), legacyDark);

        SettingsManager settings;
        QCOMPARE(settings.themeMode(), expected);
        QVERIFY(!QSettings().contains(QStringLiteral("ui/darkTheme")));
        QCOMPARE(QSettings().value(QStringLiteral("ui/themeMode")).toString(), expected);
    }

    void explicitThemeModeWinsOverLegacyKey()
    {
        QSettings().setValue(QStringLiteral("ui/darkTheme"), true);
        QSettings().setValue(QStringLiteral("ui/themeMode"), QStringLiteral("system"));

        SettingsManager settings;
        QCOMPARE(settings.themeMode(), QStringLiteral("system"));
    }

    void resetRestoresDefaultsAndSignals()
    {
        SettingsManager settings;
        settings.setThemeMode(QStringLiteral("system"));
        settings.setReduceMotion(true);
        settings.setGpuPreviewEnabled(false);
        settings.setExportQuality(64);
        settings.setJpegBackground(QColor(1, 2, 3));
        settings.setLocale(QStringLiteral("en"));
        settings.setConfirmOnClose(false);
        settings.setShowCheckerboard(false);
        settings.setRecoveryEnabled(false);
        settings.setStartupTool(QStringLiteral("brush"));

        QSignalSpy changed(&settings, &SettingsManager::changed);
        QSignalSpy theme(&settings, &SettingsManager::themeModeChanged);
        QSignalSpy motion(&settings, &SettingsManager::reduceMotionChanged);
        QSignalSpy gpu(&settings, &SettingsManager::gpuPreviewEnabledChanged);
        QSignalSpy quality(&settings, &SettingsManager::exportQualityChanged);
        QSignalSpy background(&settings, &SettingsManager::jpegBackgroundChanged);
        QSignalSpy locale(&settings, &SettingsManager::localeChanged);
        QSignalSpy close(&settings, &SettingsManager::confirmOnCloseChanged);
        QSignalSpy checkerboard(&settings, &SettingsManager::showCheckerboardChanged);
        QSignalSpy recovery(&settings, &SettingsManager::recoveryEnabledChanged);
        QSignalSpy startupTool(&settings, &SettingsManager::startupToolChanged);

        settings.resetToDefaults();

        QCOMPARE(settings.themeMode(), QStringLiteral("dark"));
        QCOMPARE(settings.reduceMotion(), false);
        QCOMPARE(settings.gpuPreviewEnabled(), true);
        QCOMPARE(settings.exportQuality(), -1);
        QCOMPARE(settings.jpegBackground().rgb(), QColor(Qt::white).rgb());
        QCOMPARE(settings.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(settings.confirmOnClose(), true);
        QCOMPARE(settings.showCheckerboard(), true);
        QCOMPARE(settings.recoveryEnabled(), true);
        QCOMPARE(settings.startupTool(), QStringLiteral("adjust"));

        QCOMPARE(changed.count(), 1);
        QCOMPARE(theme.count(), 1);
        QCOMPARE(motion.count(), 1);
        QCOMPARE(gpu.count(), 1);
        QCOMPARE(quality.count(), 1);
        QCOMPARE(background.count(), 1);
        QCOMPARE(locale.count(), 1);
        QCOMPARE(close.count(), 1);
        QCOMPARE(checkerboard.count(), 1);
        QCOMPARE(recovery.count(), 1);
        QCOMPARE(startupTool.count(), 1);

        SettingsManager restored;
        QCOMPARE(restored.themeMode(), QStringLiteral("dark"));
        QCOMPARE(restored.reduceMotion(), false);
        QCOMPARE(restored.gpuPreviewEnabled(), true);
        QCOMPARE(restored.exportQuality(), -1);
        QCOMPARE(restored.jpegBackground().rgb(), QColor(Qt::white).rgb());
        QCOMPARE(restored.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(restored.confirmOnClose(), true);
        QCOMPARE(restored.showCheckerboard(), true);
        QCOMPARE(restored.recoveryEnabled(), true);
        QCOMPARE(restored.startupTool(), QStringLiteral("adjust"));
    }

    void changedOnlyWhenValueDiffers()
    {
        SettingsManager settings;
        QSignalSpy changed(&settings, &SettingsManager::changed);
        QSignalSpy theme(&settings, &SettingsManager::themeModeChanged);
        QSignalSpy motion(&settings, &SettingsManager::reduceMotionChanged);

        settings.setThemeMode(QStringLiteral("dark"));      // already default
        settings.setReduceMotion(false);                    // already default
        QCOMPARE(changed.count(), 0);
        QCOMPARE(theme.count(), 0);
        QCOMPARE(motion.count(), 0);

        settings.setReduceMotion(true);
        QCOMPARE(changed.count(), 1);
        QCOMPARE(motion.count(), 1);

        settings.setReduceMotion(true);                     // duplicate
        QCOMPARE(changed.count(), 1);
        QCOMPARE(motion.count(), 1);

        settings.setThemeMode(QStringLiteral("light"));
        QCOMPARE(changed.count(), 2);
        QCOMPARE(theme.count(), 1);
    }
};

QTEST_MAIN(SettingsManagerTest)
#include "tst_settingsmanager.moc"
