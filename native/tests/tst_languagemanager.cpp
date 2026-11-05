#include "app/languagemanager.h"

#include <QQmlEngine>
#include <QSettings>
#include <QStringList>
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
    }

    void exposesEverySupportedLocale()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        const auto locales = language.availableLocales();
        QCOMPARE(locales.size(), 4);

        QStringList ids;
        QStringList nativeNames;
        for (const auto &value : locales) {
            const auto entry = value.toMap();
            ids.append(entry.value(QStringLiteral("id")).toString());
            nativeNames.append(entry.value(QStringLiteral("nativeName")).toString());
        }
        QCOMPARE(ids, QStringList({QStringLiteral("en"), QStringLiteral("zh_CN"),
                                   QStringLiteral("ja_JP"), QStringLiteral("de_DE")}));
        QCOMPARE(nativeNames, QStringList({QStringLiteral("English"), QStringLiteral("简体中文"),
                                           QStringLiteral("日本語"), QStringLiteral("Deutsch")}));
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

    void switchesToNewCatalogues()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        QSignalSpy changed(&language, &LanguageManager::localeChanged);

        language.setLanguage(QStringLiteral("ja_JP"));
        QCOMPARE(language.locale(), QStringLiteral("ja_JP"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("ja_JP"));

        language.setLanguage(QStringLiteral("de_DE"));
        QCOMPARE(language.locale(), QStringLiteral("de_DE"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("de_DE"));
        QVERIFY(changed.count() >= 2);

        language.setLanguage(QStringLiteral("en"));
        QCOMPARE(language.locale(), QStringLiteral("en"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("en"));
    }

    void knownStringsDifferFromSource_data()
    {
        QTest::addColumn<QString>("locale");
        QTest::addColumn<QString>("expected");

        QTest::newRow("ja_JP") << QStringLiteral("ja_JP") << QStringLiteral("言語");
        QTest::newRow("de_DE") << QStringLiteral("de_DE") << QStringLiteral("Sprache");
    }

    void knownStringsDifferFromSource()
    {
        QFETCH(QString, locale);
        QFETCH(QString, expected);

        QQmlEngine engine;
        LanguageManager language(engine);
        language.setLanguage(locale);
        QCOMPARE(language.locale(), locale);

        const auto translated = QCoreApplication::translate("Main", "Language");
        QCOMPARE(translated, expected);
        QVERIFY(translated != QStringLiteral("Language"));
    }

    void rejectsUnknownLocale()
    {
        QQmlEngine engine;
        LanguageManager language(engine);
        language.setLanguage(QStringLiteral("neko"));
        // Unsupported locales never install a translator and fall back to the
        // English source strings.
        QCOMPARE(language.locale(), QStringLiteral("en"));
        QCOMPARE(QCoreApplication::translate("Main", "Language"), QStringLiteral("Language"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("en"));
    }

    void restoresStoredChoice()
    {
        QSettings().setValue(QStringLiteral("ui/language"), QStringLiteral("en"));
        QQmlEngine engine;
        LanguageManager language(engine);
        QCOMPARE(language.locale(), QStringLiteral("en"));
    }

    void restoresStoredNewCatalogue()
    {
        QSettings().setValue(QStringLiteral("ui/language"), QStringLiteral("de_DE"));
        QQmlEngine engine;
        LanguageManager language(engine);
        QCOMPARE(language.locale(), QStringLiteral("de_DE"));
    }
};

QTEST_MAIN(LanguageManagerTest)
#include "tst_languagemanager.moc"
