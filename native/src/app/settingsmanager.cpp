#include "settingsmanager.h"

#include <QSettings>

namespace {

// QSettings keys are documented in the module report; `ui/language` is
// deliberately shared with LanguageManager so both objects observe the same
// persisted choice.
const auto kThemeModeKey = QStringLiteral("ui/themeMode");
const auto kLegacyDarkThemeKey = QStringLiteral("ui/darkTheme");
const auto kReduceMotionKey = QStringLiteral("ui/reduceMotion");
const auto kGpuPreviewKey = QStringLiteral("ui/gpuPreviewEnabled");
const auto kExportQualityKey = QStringLiteral("ui/exportQuality");
const auto kJpegBackgroundKey = QStringLiteral("ui/jpegBackground");
const auto kLocaleKey = QStringLiteral("ui/language");
const auto kConfirmOnCloseKey = QStringLiteral("ui/confirmOnClose");
const auto kCheckerboardKey = QStringLiteral("ui/showCheckerboard");

const auto kDefaultThemeMode = QStringLiteral("dark");
const auto kDefaultLocale = QStringLiteral("zh_CN");

} // namespace

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
{
    load();
}

QString SettingsManager::themeMode() const { return themeMode_; }
bool SettingsManager::reduceMotion() const { return reduceMotion_; }
bool SettingsManager::gpuPreviewEnabled() const { return gpuPreviewEnabled_; }
int SettingsManager::exportQuality() const { return exportQuality_; }
QColor SettingsManager::jpegBackground() const { return jpegBackground_; }
QString SettingsManager::locale() const { return locale_; }
bool SettingsManager::confirmOnClose() const { return confirmOnClose_; }
bool SettingsManager::showCheckerboard() const { return showCheckerboard_; }

QString SettingsManager::normaliseThemeMode(const QString &mode)
{
    if (mode == QLatin1String("system") || mode == QLatin1String("light")
        || mode == QLatin1String("dark")) {
        return mode;
    }
    return kDefaultThemeMode;
}

QString SettingsManager::normaliseLocale(const QString &locale)
{
    if (locale == QLatin1String("en") || locale == QLatin1String("zh_CN"))
        return locale;
    return kDefaultLocale;
}

int SettingsManager::normaliseQuality(int quality)
{
    return qBound(-1, quality, 100);
}

QColor SettingsManager::opaqueColor(const QColor &color)
{
    if (!color.isValid())
        return QColor(Qt::white);
    QColor result = color;
    result.setAlpha(255);
    return result;
}

void SettingsManager::load()
{
    QSettings settings;

    // Complete the one-way migration from the old Settings { darkTheme } alias
    // so the obsolete key cannot override the new preference later.
    const auto storedTheme = settings.value(kThemeModeKey).toString();
    if (storedTheme.isEmpty() && settings.contains(kLegacyDarkThemeKey)) {
        themeMode_ = settings.value(kLegacyDarkThemeKey).toBool()
                         ? QStringLiteral("dark")
                         : QStringLiteral("light");
        settings.setValue(kThemeModeKey, themeMode_);
        settings.remove(kLegacyDarkThemeKey);
    } else {
        themeMode_ = normaliseThemeMode(storedTheme);
    }

    reduceMotion_ = settings.value(kReduceMotionKey, false).toBool();
    gpuPreviewEnabled_ = settings.value(kGpuPreviewKey, true).toBool();
    exportQuality_ = normaliseQuality(settings.value(kExportQualityKey, -1).toInt());
    jpegBackground_ = opaqueColor(
        QColor(settings.value(kJpegBackgroundKey, QStringLiteral("#ffffff")).toString()));
    locale_ = normaliseLocale(settings.value(kLocaleKey, kDefaultLocale).toString());
    confirmOnClose_ = settings.value(kConfirmOnCloseKey, true).toBool();
    showCheckerboard_ = settings.value(kCheckerboardKey, true).toBool();
}

void SettingsManager::setThemeMode(const QString &mode)
{
    const auto normalised = normaliseThemeMode(mode);
    if (normalised == themeMode_)
        return;
    themeMode_ = normalised;
    QSettings().setValue(kThemeModeKey, themeMode_);
    emit themeModeChanged();
    emit changed();
}

void SettingsManager::setReduceMotion(bool enabled)
{
    if (enabled == reduceMotion_)
        return;
    reduceMotion_ = enabled;
    QSettings().setValue(kReduceMotionKey, reduceMotion_);
    emit reduceMotionChanged();
    emit changed();
}

void SettingsManager::setGpuPreviewEnabled(bool enabled)
{
    if (enabled == gpuPreviewEnabled_)
        return;
    gpuPreviewEnabled_ = enabled;
    QSettings().setValue(kGpuPreviewKey, gpuPreviewEnabled_);
    emit gpuPreviewEnabledChanged();
    emit changed();
}

void SettingsManager::setExportQuality(int quality)
{
    const auto normalised = normaliseQuality(quality);
    if (normalised == exportQuality_)
        return;
    exportQuality_ = normalised;
    QSettings().setValue(kExportQualityKey, exportQuality_);
    emit exportQualityChanged();
    emit changed();
}

void SettingsManager::setJpegBackground(const QColor &color)
{
    const auto normalised = opaqueColor(color);
    if (normalised == jpegBackground_)
        return;
    jpegBackground_ = normalised;
    QSettings().setValue(kJpegBackgroundKey, jpegBackground_.name(QColor::HexRgb));
    emit jpegBackgroundChanged();
    emit changed();
}

void SettingsManager::setLocale(const QString &locale)
{
    const auto normalised = normaliseLocale(locale);
    if (normalised == locale_)
        return;
    locale_ = normalised;
    QSettings().setValue(kLocaleKey, locale_);
    emit localeChanged();
    emit changed();
}

void SettingsManager::setConfirmOnClose(bool enabled)
{
    if (enabled == confirmOnClose_)
        return;
    confirmOnClose_ = enabled;
    QSettings().setValue(kConfirmOnCloseKey, confirmOnClose_);
    emit confirmOnCloseChanged();
    emit changed();
}

void SettingsManager::setShowCheckerboard(bool enabled)
{
    if (enabled == showCheckerboard_)
        return;
    showCheckerboard_ = enabled;
    QSettings().setValue(kCheckerboardKey, showCheckerboard_);
    emit showCheckerboardChanged();
    emit changed();
}

void SettingsManager::resetToDefaults()
{
    const bool themeChanged = themeMode_ != kDefaultThemeMode;
    const bool motionChanged = reduceMotion_;
    const bool gpuChanged = !gpuPreviewEnabled_;
    const bool qualityChanged = exportQuality_ != -1;
    const bool backgroundChanged = jpegBackground_ != QColor(Qt::white);
    const bool localeChangedValue = locale_ != kDefaultLocale;
    const bool closeChanged = !confirmOnClose_;
    const bool checkerboardChanged = !showCheckerboard_;

    themeMode_ = kDefaultThemeMode;
    reduceMotion_ = false;
    gpuPreviewEnabled_ = true;
    exportQuality_ = -1;
    jpegBackground_ = QColor(Qt::white);
    locale_ = kDefaultLocale;
    confirmOnClose_ = true;
    showCheckerboard_ = true;

    if (themeChanged) emit themeModeChanged();
    if (motionChanged) emit reduceMotionChanged();
    if (gpuChanged) emit gpuPreviewEnabledChanged();
    if (qualityChanged) emit exportQualityChanged();
    if (backgroundChanged) emit jpegBackgroundChanged();
    if (localeChangedValue) emit localeChanged();
    if (closeChanged) emit confirmOnCloseChanged();
    if (checkerboardChanged) emit showCheckerboardChanged();

    // Persist defaults even when the in-memory values already matched, and
    // discard the legacy key so a future launch cannot resurrect it.
    QSettings settings;
    settings.setValue(kThemeModeKey, themeMode_);
    settings.setValue(kReduceMotionKey, reduceMotion_);
    settings.setValue(kGpuPreviewKey, gpuPreviewEnabled_);
    settings.setValue(kExportQualityKey, exportQuality_);
    settings.setValue(kJpegBackgroundKey, jpegBackground_.name(QColor::HexRgb));
    settings.setValue(kLocaleKey, locale_);
    settings.setValue(kConfirmOnCloseKey, confirmOnClose_);
    settings.setValue(kCheckerboardKey, showCheckerboard_);
    settings.remove(kLegacyDarkThemeKey);

    if (themeChanged || motionChanged || gpuChanged || qualityChanged || backgroundChanged
        || localeChangedValue || closeChanged || checkerboardChanged) {
        emit changed();
    }
}
