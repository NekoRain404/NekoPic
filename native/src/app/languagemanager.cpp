#include "languagemanager.h"

#include <QCoreApplication>
#include <QQmlEngine>
#include <QSettings>
#include <QDebug>

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
    QVariantList locales;
    locales.reserve(static_cast<qsizetype>(kLocales.size()));
    for (const auto &entry : kLocales) {
        locales.append(QVariantMap{
            {QStringLiteral("id"), QString::fromLatin1(entry.id)},
            {QStringLiteral("nativeName"), QString::fromUtf8(entry.nativeName)},
        });
    }
    return locales;
}

bool LanguageManager::isSupported(const QString &locale)
{
    for (const auto &entry : kLocales) {
        if (locale == QLatin1String(entry.id))
            return true;
    }
    return false;
}

void LanguageManager::clearTranslator()
{
    if (translatorInstalled_)
        QCoreApplication::removeTranslator(&translator_);
    translatorInstalled_ = false;
}

void LanguageManager::setLanguage(const QString &locale)
{
    if (!isSupported(locale))
        qWarning() << "LanguageManager: unsupported locale" << locale << "- falling back to English";

    const auto requested = isSupported(locale) ? locale : QStringLiteral("en");
    const bool needsTranslator = requested != QLatin1String("en");
    if (requested == locale_ && translatorInstalled_ == needsTranslator)
        return;

    clearTranslator();
    if (needsTranslator) {
        const auto path = QStringLiteral(":/i18n/nekopic_%1.qm").arg(requested);
        if (translator_.load(path)) {
            QCoreApplication::installTranslator(&translator_);
            translatorInstalled_ = true;
            locale_ = requested;
        } else {
            // Never leave a half-installed translator behind: a missing
            // catalogue falls back to the English source strings.
            qWarning() << "LanguageManager: missing translation catalogue" << path
                       << "- falling back to English";
            locale_ = QStringLiteral("en");
        }
    } else {
        locale_ = QStringLiteral("en");
    }

    QSettings().setValue(QStringLiteral("ui/language"), locale_);
    engine_.retranslate();
    emit localeChanged();
}
