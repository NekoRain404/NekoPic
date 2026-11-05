#include "languagemanager.h"

#include <QCoreApplication>
#include <QQmlEngine>
#include <QSettings>

LanguageManager::LanguageManager(QQmlEngine &engine, QObject *parent)
    : QObject(parent), engine_(engine)
{
    Q_INIT_RESOURCE(translations);
    const auto stored = QSettings().value(QStringLiteral("ui/language"), QStringLiteral("zh_CN")).toString();
    setLanguage(stored);
}

QString LanguageManager::locale() const { return locale_; }

QVariantList LanguageManager::availableLocales() const
{
    return {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("en")},
                    {QStringLiteral("nativeName"), QStringLiteral("English")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("zh_CN")},
                    {QStringLiteral("nativeName"), QStringLiteral("简体中文")}},
    };
}

bool LanguageManager::isSupported(const QString &locale)
{
    return locale == QLatin1String("en") || locale == QLatin1String("zh_CN");
}

void LanguageManager::setLanguage(const QString &locale)
{
    const auto requested = isSupported(locale) ? locale : QStringLiteral("en");
    if (requested == locale_ && !translator_.isEmpty() == (requested == QLatin1String("zh_CN")))
        return;

    QCoreApplication::removeTranslator(&translator_);
    if (requested == QLatin1String("zh_CN")
        && !translator_.load(QStringLiteral(":/i18n/nekopic_zh_CN.qm"))) {
        // Fall back to source strings rather than leaving a half-translated UI.
        locale_ = QStringLiteral("en");
    } else {
        locale_ = requested;
        if (locale_ == QLatin1String("zh_CN"))
            QCoreApplication::installTranslator(&translator_);
    }

    QSettings().setValue(QStringLiteral("ui/language"), locale_);
    engine_.retranslate();
    emit localeChanged();
}
