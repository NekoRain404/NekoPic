#pragma once

#include <QObject>
#include <QTranslator>
#include <QVariantList>

class QQmlEngine;

// Owns the active UI language, persists the choice and reloads translations.
// English is the source language; Simplified Chinese ships a .qm catalogue.
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
    static bool isSupported(const QString &locale);

    QQmlEngine &engine_;
    QTranslator translator_;
    QString locale_ = QStringLiteral("en");
};
