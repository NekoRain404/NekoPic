#pragma once

#include <QObject>
#include <QTranslator>
#include <QVariantList>

#include <array>

class QQmlEngine;

// Owns the active UI language, persists the choice and reloads translations.
// English is the source language and needs no catalogue; every other entry in
// kLocales ships a compiled :/i18n/nekopic_<locale>.qm catalogue. The table is
// the single source of truth for both the menu and validation, so adding a
// language only requires a catalogue and one row here.
class LanguageManager final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString locale READ locale NOTIFY localeChanged)
    Q_PROPERTY(QVariantList availableLocales READ availableLocales CONSTANT)

public:
    explicit LanguageManager(QQmlEngine &engine, QObject *parent = nullptr);

    QString locale() const;
    QVariantList availableLocales() const;

    Q_INVOKABLE void setLanguage(const QString &locale);

signals:
    void localeChanged();

private:
    struct LocaleEntry {
        const char *id;
        const char *nativeName;
    };
    static constexpr std::array<LocaleEntry, 4> kLocales{{
        {"en", "English"},
        {"zh_CN", "简体中文"},
        {"ja_JP", "日本語"},
        {"de_DE", "Deutsch"},
    }};

    static bool isSupported(const QString &locale);
    void clearTranslator();

    QQmlEngine &engine_;
    QTranslator translator_;
    QString locale_ = QStringLiteral("en");
    bool translatorInstalled_ = false;
};
