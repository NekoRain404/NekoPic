#pragma once

#include <QColor>
#include <QObject>
#include <QString>

/*!
    SettingsManager — persisted, validated user preferences.

    Owns every preference shown on the settings page and stores it under the
    `ui` QSettings category. Every setter validates its input, writes through
    immediately and emits a property-specific signal followed by changed().

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

private:
    static QString normaliseThemeMode(const QString &mode);
    static QString normaliseLocale(const QString &locale);
    static int normaliseQuality(int quality);
    static QString normaliseStartupTool(const QString &tool);
    static QColor opaqueColor(const QColor &color);

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
};
