#include "settingsmanager.h"

#include <QHash>
#include <QKeySequence>
#include <QSettings>
#include <QStringList>

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
const auto kRecoveryEnabledKey = QStringLiteral("ui/recoveryEnabled");
const auto kStartupToolKey = QStringLiteral("ui/startupTool");
const auto kUiFontFamilyKey = QStringLiteral("ui/fontFamily");
const auto kUiFontScaleKey = QStringLiteral("ui/fontScale");
const auto kUiScaleKey = QStringLiteral("ui/scale");
const auto kShortcutPrefix = QStringLiteral("ui/shortcuts/");

const auto kDefaultThemeMode = QStringLiteral("dark");
const auto kDefaultLocale = QStringLiteral("zh_CN");
const auto kDefaultStartupTool = QStringLiteral("adjust");
constexpr int kDefaultScale = 100;
constexpr int kMinFontScale = 80;
constexpr int kMaxFontScale = 140;
constexpr int kMinUiScale = 80;
constexpr int kMaxUiScale = 150;

const QStringList &supportedLocales()
{
    // Mirrors LanguageManager::kLocales; `ui/language` is shared by both.
    static const QStringList locales{
        QStringLiteral("en"), QStringLiteral("zh_CN"),
        QStringLiteral("ja_JP"), QStringLiteral("de_DE")
    };
    return locales;
}

const QStringList &startupTools()
{
    static const QStringList tools{
        QStringLiteral("adjust"), QStringLiteral("filters"), QStringLiteral("select"),
        QStringLiteral("pan"), QStringLiteral("brush"), QStringLiteral("text"),
        QStringLiteral("shapes"), QStringLiteral("mosaic"), QStringLiteral("eye"),
        QStringLiteral("crop")
    };
    return tools;
}

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
bool SettingsManager::recoveryEnabled() const { return recoveryEnabled_; }
QString SettingsManager::startupTool() const { return startupTool_; }
QString SettingsManager::uiFontFamily() const { return uiFontFamily_; }
int SettingsManager::uiFontScale() const { return uiFontScale_; }
int SettingsManager::uiScale() const { return uiScale_; }
QVariantMap SettingsManager::shortcuts() const { return shortcuts_; }

QString SettingsManager::normaliseThemeMode(const QString &mode)
{
    static const QStringList modes{
        QStringLiteral("system"), QStringLiteral("light"), QStringLiteral("dark"),
        QStringLiteral("midnight"), QStringLiteral("warm"), QStringLiteral("graphite"),
        QStringLiteral("contrast"), QStringLiteral("nordic"), QStringLiteral("sakura"),
        QStringLiteral("forest"), QStringLiteral("solarized")
    };
    if (modes.contains(mode))
        return mode;
    return kDefaultThemeMode;
}

QString SettingsManager::normaliseLocale(const QString &locale)
{
    return supportedLocales().contains(locale) ? locale : kDefaultLocale;
}

int SettingsManager::normaliseQuality(int quality)
{
    return qBound(-1, quality, 100);
}

QString SettingsManager::normaliseStartupTool(const QString &tool)
{
    return startupTools().contains(tool) ? tool : kDefaultStartupTool;
}

QColor SettingsManager::opaqueColor(const QColor &color)
{
    if (!color.isValid())
        return QColor(Qt::white);
    QColor result = color;
    result.setAlpha(255);
    return result;
}

int SettingsManager::normaliseFontScale(int percent)
{
    return qBound(kMinFontScale, percent, kMaxFontScale);
}

int SettingsManager::normaliseUiScale(int percent)
{
    return qBound(kMinUiScale, percent, kMaxUiScale);
}

QString SettingsManager::normaliseSequence(const QString &sequence)
{
    const auto trimmed = sequence.trimmed();
    if (trimmed.isEmpty())
        return {};
    const QKeySequence parsed = QKeySequence::fromString(trimmed, QKeySequence::PortableText);
    if (parsed.isEmpty())
        return {};
    return parsed.toString(QKeySequence::PortableText);
}

const QStringList &SettingsManager::shortcutKeys()
{
    // Kept in lockstep with the Action ids in Main.qml and the editable
    // catalogue in ShortcutsPage.qml.
    static const QStringList keys{
        QStringLiteral("open"), QStringLiteral("save"), QStringLiteral("saveAs"),
        QStringLiteral("settings"), QStringLiteral("commandPalette"),
        QStringLiteral("copy"), QStringLiteral("undo"), QStringLiteral("redo"),
        QStringLiteral("zoomIn"), QStringLiteral("zoomOut"), QStringLiteral("fit"),
        QStringLiteral("actual"), QStringLiteral("brush"), QStringLiteral("shape"),
        QStringLiteral("pan"), QStringLiteral("select"), QStringLiteral("text"),
        QStringLiteral("eyedropper"), QStringLiteral("crop")
    };
    return keys;
}

QString SettingsManager::defaultShortcut(const QString &key)
{
    static const QHash<QString, QString> defaults{
        {QStringLiteral("open"), QStringLiteral("Ctrl+O")},
        {QStringLiteral("save"), QStringLiteral("Ctrl+S")},
        {QStringLiteral("saveAs"), QStringLiteral("Ctrl+Shift+S")},
        {QStringLiteral("settings"), QStringLiteral("Ctrl+,")},
        {QStringLiteral("commandPalette"), QStringLiteral("Ctrl+K")},
        {QStringLiteral("copy"), QStringLiteral("Ctrl+Shift+C")},
        {QStringLiteral("undo"), QStringLiteral("Ctrl+Z")},
        {QStringLiteral("redo"), QStringLiteral("Ctrl+Shift+Z")},
        {QStringLiteral("zoomIn"), QStringLiteral("Ctrl+=")},
        {QStringLiteral("zoomOut"), QStringLiteral("Ctrl+-")},
        {QStringLiteral("fit"), QStringLiteral("Ctrl+0")},
        {QStringLiteral("actual"), QStringLiteral("Ctrl+1")},
        {QStringLiteral("brush"), QStringLiteral("B")},
        {QStringLiteral("shape"), QStringLiteral("U")},
        {QStringLiteral("pan"), QStringLiteral("H")},
        {QStringLiteral("select"), QStringLiteral("V")},
        {QStringLiteral("text"), QStringLiteral("T")},
        {QStringLiteral("eyedropper"), QStringLiteral("I")},
        {QStringLiteral("crop"), QStringLiteral("C")}
    };
    return defaults.value(key);
}

QString SettingsManager::effectiveShortcut(const QString &key) const
{
    const auto it = shortcuts_.constFind(key);
    if (it != shortcuts_.constEnd()) {
        const auto stored = it.value().toString();
        if (!stored.isEmpty())
            return stored;
    }
    return defaultShortcut(key);
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
    recoveryEnabled_ = settings.value(kRecoveryEnabledKey, true).toBool();
    startupTool_ = normaliseStartupTool(
        settings.value(kStartupToolKey, kDefaultStartupTool).toString());

    uiFontFamily_ = settings.value(kUiFontFamilyKey, QString()).toString().trimmed();
    uiFontScale_ = normaliseFontScale(
        settings.value(kUiFontScaleKey, kDefaultScale).toInt());
    uiScale_ = normaliseUiScale(settings.value(kUiScaleKey, kDefaultScale).toInt());

    shortcuts_.clear();
    for (const auto &key : shortcutKeys()) {
        const auto stored = settings.value(kShortcutPrefix + key).toString();
        const auto normalised = normaliseSequence(stored);
        if (!normalised.isEmpty())
            shortcuts_.insert(key, normalised);
    }
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

void SettingsManager::setRecoveryEnabled(bool enabled)
{
    if (enabled == recoveryEnabled_)
        return;
    recoveryEnabled_ = enabled;
    QSettings().setValue(kRecoveryEnabledKey, recoveryEnabled_);
    emit recoveryEnabledChanged();
    emit changed();
}

void SettingsManager::setStartupTool(const QString &tool)
{
    const auto normalised = normaliseStartupTool(tool);
    if (normalised == startupTool_)
        return;
    startupTool_ = normalised;
    QSettings().setValue(kStartupToolKey, startupTool_);
    emit startupToolChanged();
    emit changed();
}

void SettingsManager::setUiFontFamily(const QString &family)
{
    const auto normalised = family.trimmed();
    if (normalised == uiFontFamily_)
        return;
    uiFontFamily_ = normalised;
    QSettings().setValue(kUiFontFamilyKey, uiFontFamily_);
    emit uiFontFamilyChanged();
    emit changed();
}

void SettingsManager::setUiFontScale(int percent)
{
    const auto normalised = normaliseFontScale(percent);
    if (normalised == uiFontScale_)
        return;
    uiFontScale_ = normalised;
    QSettings().setValue(kUiFontScaleKey, uiFontScale_);
    emit uiFontScaleChanged();
    emit changed();
}

void SettingsManager::setUiScale(int percent)
{
    const auto normalised = normaliseUiScale(percent);
    if (normalised == uiScale_)
        return;
    uiScale_ = normalised;
    QSettings().setValue(kUiScaleKey, uiScale_);
    emit uiScaleChanged();
    emit changed();
}

QString SettingsManager::shortcutFor(const QString &key, const QString &fallback) const
{
    const auto it = shortcuts_.constFind(key);
    if (it == shortcuts_.constEnd())
        return fallback;
    const auto stored = it.value().toString();
    return stored.isEmpty() ? fallback : stored;
}

bool SettingsManager::setShortcut(const QString &key, const QString &sequence)
{
    if (!shortcutKeys().contains(key))
        return false;

    const auto normalised = normaliseSequence(sequence);
    if (normalised.isEmpty())
        return resetShortcut(key);

    // Setting an action back to its built-in default should not leave a
    // redundant override behind.
    if (normalised == defaultShortcut(key))
        return resetShortcut(key);

    for (const auto &other : shortcutKeys()) {
        if (other == key)
            continue;
        if (effectiveShortcut(other).compare(normalised, Qt::CaseInsensitive) == 0)
            return false;
    }

    if (shortcuts_.value(key).toString() == normalised)
        return true;

    shortcuts_.insert(key, normalised);
    QSettings().setValue(kShortcutPrefix + key, normalised);
    emit shortcutsChanged();
    emit changed();
    return true;
}

bool SettingsManager::resetShortcut(const QString &key)
{
    if (!shortcutKeys().contains(key))
        return false;
    if (!shortcuts_.contains(key))
        return true;

    shortcuts_.remove(key);
    QSettings().remove(kShortcutPrefix + key);
    emit shortcutsChanged();
    emit changed();
    return true;
}

void SettingsManager::resetShortcuts()
{
    if (shortcuts_.isEmpty())
        return;

    shortcuts_.clear();
    QSettings settings;
    for (const auto &key : shortcutKeys())
        settings.remove(kShortcutPrefix + key);
    emit shortcutsChanged();
    emit changed();
}

QString SettingsManager::keySequence(int key, int modifiers) const
{
    if (key <= 0)
        return {};
    const QKeySequence sequence(key | modifiers);
    return sequence.toString(QKeySequence::PortableText);
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
    const bool recoveryChanged = !recoveryEnabled_;
    const bool startupPrefChanged = startupTool_ != kDefaultStartupTool;
    const bool fontFamilyChanged = !uiFontFamily_.isEmpty();
    const bool fontScaleChanged = uiFontScale_ != kDefaultScale;
    const bool uiScaleChangedValue = uiScale_ != kDefaultScale;
    const bool shortcutsChangedValue = !shortcuts_.isEmpty();

    themeMode_ = kDefaultThemeMode;
    reduceMotion_ = false;
    gpuPreviewEnabled_ = true;
    exportQuality_ = -1;
    jpegBackground_ = QColor(Qt::white);
    locale_ = kDefaultLocale;
    confirmOnClose_ = true;
    showCheckerboard_ = true;
    recoveryEnabled_ = true;
    startupTool_ = kDefaultStartupTool;
    uiFontFamily_.clear();
    uiFontScale_ = kDefaultScale;
    uiScale_ = kDefaultScale;
    shortcuts_.clear();

    if (themeChanged) emit themeModeChanged();
    if (motionChanged) emit reduceMotionChanged();
    if (gpuChanged) emit gpuPreviewEnabledChanged();
    if (qualityChanged) emit exportQualityChanged();
    if (backgroundChanged) emit jpegBackgroundChanged();
    if (localeChangedValue) emit localeChanged();
    if (closeChanged) emit confirmOnCloseChanged();
    if (checkerboardChanged) emit showCheckerboardChanged();
    if (recoveryChanged) emit recoveryEnabledChanged();
    if (startupPrefChanged) emit startupToolChanged();
    if (fontFamilyChanged) emit uiFontFamilyChanged();
    if (fontScaleChanged) emit uiFontScaleChanged();
    if (uiScaleChangedValue) emit uiScaleChanged();
    if (shortcutsChangedValue) emit shortcutsChanged();

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
    settings.setValue(kRecoveryEnabledKey, recoveryEnabled_);
    settings.setValue(kStartupToolKey, startupTool_);
    settings.setValue(kUiFontFamilyKey, uiFontFamily_);
    settings.setValue(kUiFontScaleKey, uiFontScale_);
    settings.setValue(kUiScaleKey, uiScale_);
    for (const auto &key : shortcutKeys())
        settings.remove(kShortcutPrefix + key);
    settings.remove(kLegacyDarkThemeKey);

    if (themeChanged || motionChanged || gpuChanged || qualityChanged || backgroundChanged
        || localeChangedValue || closeChanged || checkerboardChanged || recoveryChanged
        || startupPrefChanged || fontFamilyChanged || fontScaleChanged
        || uiScaleChangedValue || shortcutsChangedValue) {
        emit changed();
    }
}
