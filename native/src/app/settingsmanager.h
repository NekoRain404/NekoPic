#pragma once

#include <QColor>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

/*!
    SettingsManager — persisted, validated user preferences.

    Owns every preference shown on the settings page and stores it under the
    `ui` QSettings category. Every setter validates its input, writes through
    immediately and emits a property-specific signal followed by changed().

    Typography and interface scale use `ui/fontFamily`, `ui/fontScale` and
    `ui/scale`. Shortcut overrides are stored one key at a time under
    `ui/shortcuts/<action>` so adding a new action never invalidates an
    existing settings file.

    Must be used from the GUI thread only: QSettings and the QML bindings that
    observe this object are not thread-safe.
*/
class SettingsManager final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY reduceMotionChanged)
    Q_PROPERTY(bool gpuPreviewEnabled READ gpuPreviewEnabled WRITE setGpuPreviewEnabled NOTIFY gpuPreviewEnabledChanged)
    Q_PROPERTY(int exportQuality READ exportQuality WRITE setExportQuality NOTIFY exportQualityChanged)
    Q_PROPERTY(QColor jpegBackground READ jpegBackground WRITE setJpegBackground NOTIFY jpegBackgroundChanged)
    Q_PROPERTY(QString locale READ locale WRITE setLocale NOTIFY localeChanged)
    Q_PROPERTY(bool confirmOnClose READ confirmOnClose WRITE setConfirmOnClose NOTIFY confirmOnCloseChanged)
    Q_PROPERTY(bool showCheckerboard READ showCheckerboard WRITE setShowCheckerboard NOTIFY showCheckerboardChanged)
    Q_PROPERTY(bool recoveryEnabled READ recoveryEnabled WRITE setRecoveryEnabled NOTIFY recoveryEnabledChanged)
    Q_PROPERTY(QString startupTool READ startupTool WRITE setStartupTool NOTIFY startupToolChanged)
    /*! Empty means "use the system UI font". Applied by main.cpp. */
    Q_PROPERTY(QString uiFontFamily READ uiFontFamily WRITE setUiFontFamily NOTIFY uiFontFamilyChanged)
    /*! UI text scale in percent; 80–140, default 100. Applied live through Theme.fontScale. */
    Q_PROPERTY(int uiFontScale READ uiFontScale WRITE setUiFontScale NOTIFY uiFontScaleChanged)
    /*! Whole-interface scale in percent; 80–150, default 100. Applied on next launch. */
    Q_PROPERTY(int uiScale READ uiScale WRITE setUiScale NOTIFY uiScaleChanged)
    /*! Only explicitly overridden actions are present. */
    Q_PROPERTY(QVariantMap shortcuts READ shortcuts NOTIFY shortcutsChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    /*! "system" | "light" | "dark"; defaults to "dark". */
    QString themeMode() const;
    bool reduceMotion() const;
    bool gpuPreviewEnabled() const;
    /*! -1 means "use the codec default"; otherwise 0–100. */
    int exportQuality() const;
    /*! Always valid and opaque. */
    QColor jpegBackground() const;
    /*! "en" | "zh_CN" | "ja_JP" | "de_DE"; stored in the same key LanguageManager uses. */
    QString locale() const;
    bool confirmOnClose() const;
    bool showCheckerboard() const;
    /*! Whether dirty documents are snapshotted for crash recovery. */
    bool recoveryEnabled() const;
    /*! Tool selected after the next image opens; defaults to "adjust". */
    QString startupTool() const;

    QString uiFontFamily() const;
    int uiFontScale() const;
    int uiScale() const;
    QVariantMap shortcuts() const;

    void setThemeMode(const QString &mode);
    void setReduceMotion(bool enabled);
    void setGpuPreviewEnabled(bool enabled);
    void setExportQuality(int quality);
    void setJpegBackground(const QColor &color);
    void setLocale(const QString &locale);
    void setConfirmOnClose(bool enabled);
    void setShowCheckerboard(bool enabled);
    void setRecoveryEnabled(bool enabled);
    void setStartupTool(const QString &tool);
    void setUiFontFamily(const QString &family);
    void setUiFontScale(int percent);
    void setUiScale(int percent);

    /*!
        Effective shortcut for `key`: the stored override, otherwise
        `fallback`. Unknown keys simply return the fallback.
    */
    Q_INVOKABLE QString shortcutFor(const QString &key, const QString &fallback) const;
    /*!
        Stores an override for `key`, normalised to portable text. Returns false
        for an unknown key or when another known action already uses the same
        sequence. An empty sequence removes the override (reset-one); when the
        sequence equals the action's built-in default the override is removed
        too, keeping the persisted map minimal.
    */
    Q_INVOKABLE bool setShortcut(const QString &key, const QString &sequence);
    /*! Removes the override for one action. Unknown keys return false. */
    Q_INVOKABLE bool resetShortcut(const QString &key);
    /*! Removes every shortcut override. */
    Q_INVOKABLE void resetShortcuts();
    /*!
        Portable text for a key and modifier mask, matching the capture
        control's expectations: keySequence(Qt.Key_O, Qt.ControlModifier) is
        "Ctrl+O".
    */
    Q_INVOKABLE QString keySequence(int key, int modifiers) const;

    /*! Restores every preference to its documented default and persists them. */
    Q_INVOKABLE void resetToDefaults();

signals:
    /*! Emitted once after any property actually changes. */
    void changed();
    void themeModeChanged();
    void reduceMotionChanged();
    void gpuPreviewEnabledChanged();
    void exportQualityChanged();
    void jpegBackgroundChanged();
    void localeChanged();
    void confirmOnCloseChanged();
    void showCheckerboardChanged();
    void recoveryEnabledChanged();
    void startupToolChanged();
    void uiFontFamilyChanged();
    void uiFontScaleChanged();
    void uiScaleChanged();
    void shortcutsChanged();

private:
    static QString normaliseThemeMode(const QString &mode);
    static QString normaliseLocale(const QString &locale);
    static int normaliseQuality(int quality);
    static QString normaliseStartupTool(const QString &tool);
    static QColor opaqueColor(const QColor &color);
    static int normaliseFontScale(int percent);
    static int normaliseUiScale(int percent);
    static QString normaliseSequence(const QString &sequence);
    static const QStringList &shortcutKeys();
    static QString defaultShortcut(const QString &key);
    QString effectiveShortcut(const QString &key) const;
    void load();

    QString themeMode_ = QStringLiteral("dark");
    bool reduceMotion_ = false;
    bool gpuPreviewEnabled_ = true;
    int exportQuality_ = -1;
    QColor jpegBackground_ = Qt::white;
    QString locale_ = QStringLiteral("zh_CN");
    bool confirmOnClose_ = true;
    bool showCheckerboard_ = true;
    bool recoveryEnabled_ = true;
    QString startupTool_ = QStringLiteral("adjust");
    QString uiFontFamily_;
    int uiFontScale_ = 100;
    int uiScale_ = 100;
    QVariantMap shortcuts_;
};
