#include "app/languagemanager.h"

#include <QQmlEngine>
#include <QSettings>
#include <QtTest>

class LanguageManagerTest final : public QObject {
    Q_OBJECT
private slots:
    void init()
    {
        QCoreApplication::setOrganizationName(QStringLiteral("NekoPicTest"));
        QCoreApplication::setApplicationName(QStringLiteral("LanguageManagerTest"));
        QSettings().clear();
    }

    void defaultsToSimplifiedChinese()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        QCOMPARE(language.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(language.availableLocales().size(), 2);
    }

    void switchesAndPersists()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        QSignalSpy changed(&language, &LanguageManager::localeChanged);
        language.setLanguage(QStringLiteral("en"));
        QCOMPARE(language.locale(), QStringLiteral("en"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("en"));
        QVERIFY(changed.count() >= 1);

        language.setLanguage(QStringLiteral("zh_CN"));
        QCOMPARE(language.locale(), QStringLiteral("zh_CN"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("zh_CN"));
    }

    void rejectsUnknownLocale()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        language.setLanguage(QStringLiteral("neko"));
        QCOMPARE(language.locale(), QStringLiteral("en"));
    }

    void restoresStoredChoice()
    {
        QSettings().setValue(QStringLiteral("ui/language"), QStringLiteral("en"));
        QQmlEngine engine;
        LanguageManager language(engine);
        QCOMPARE(language.locale(), QStringLiteral("en"));
    }
};

QTEST_MAIN(LanguageManagerTest)
#include "tst_languagemanager.moc"
