#include "languagemanager.h"

#include <QCoreApplication>
#include <QQmlEngine>
#include <QSettings>

LanguageManager::LanguageManager(QQmlEngine &engine, QObject *parent)
    : QObject(parent), engine_(engine)
{
    setLanguage(QSettings().value(QStringLiteral("ui/language"), QStringLiteral("zh_CN")).toString());
}

void LanguageManager::setLanguage(const QString &locale)
{
    QCoreApplication::removeTranslator(&translator_);
    if (locale == QLatin1String("zh_CN")) {
        if (translator_.load(QStringLiteral(":/i18n/nekopic_zh_CN.qm")))
            QCoreApplication::installTranslator(&translator_);
    }
    QSettings().setValue(QStringLiteral("ui/language"), locale);
    engine_.retranslate();
}
