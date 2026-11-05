#include "documentcontroller.h"
#include "filterpreviews.h"
#include "io/formatregistry.h"
#include "languagemanager.h"
#include "platform/recentfiles.h"
#include "recoverystore.h"
#include "settingsmanager.h"
#include "render/rendercapabilities.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QSettings>
#include <QTextStream>
#include <QTimer>
#include <QVariantMap>

#include <memory>

class DocumentImageProvider final : public QQuickImageProvider {
public:
    explicit DocumentImageProvider(const DocumentController &controller)
        : QQuickImageProvider(QQuickImageProvider::Image), controller_(controller) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &) override
    {
        QImage image;
        if (id.startsWith(QLatin1String("movebase")))
            image = controller_.objectMoveBaseImage();
        else if (id.startsWith(QLatin1String("moveobject")))
            image = controller_.objectMoveObjectImage();
        else if (id.startsWith(QLatin1String("base")))
            image = controller_.baseImage();
        else
            image = controller_.image();
        if (size) *size = image.size();
        return image;
    }
private:
    const DocumentController &controller_;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/nekopic.png")));
    QCoreApplication::setOrganizationName(QStringLiteral("NekoPic"));
    QCoreApplication::setApplicationName(QStringLiteral("NekoPic"));
    QCoreApplication::setApplicationVersion(QStringLiteral(NEKOPIC_VERSION));
    // Keep the Wayland app_id / X11 WM_CLASS tied to the installed desktop
    // entry so the launcher icon, StartupWMClass and task grouping match.
    QGuiApplication::setDesktopFileName(QStringLiteral("nekopic"));

    const auto earlyArguments = app.arguments();
    if (earlyArguments.contains(QStringLiteral("--version"))) {
        QTextStream(stdout) << "NekoPic " << QCoreApplication::applicationVersion() << "\n";
        return 0;
    }
    if (earlyArguments.contains(QStringLiteral("--help"))) {
        QTextStream(stdout)
            << "Usage: nekopic [image] [--language <locale>] [--screenshot <file>]\n"
               "  image               open an image on start\n"
               "  --language <locale> start in en, zh_CN, ja_JP or de_DE\n"
               "  --screenshot <file> render the window to a PNG and exit\n"
               "  --version           print the version\n"
               "  --help              show this help\n";
        return 0;
    }
    DocumentController editor;
    RecoveryStore recovery(&editor);
    FilterPreviews filterPreviews(editor);
    NekoPic::Render::RenderCapabilities renderCapabilities;
    NekoPic::Platform::RecentFiles recentFiles;
    SettingsManager settings;
    QQmlApplicationEngine engine;
    LanguageManager language(engine);
    engine.rootContext()->setContextProperty(QStringLiteral("editor"), &editor);
    engine.rootContext()->setContextProperty(QStringLiteral("recovery"), &recovery);
    engine.rootContext()->setContextProperty(QStringLiteral("filterPreviews"), &filterPreviews);
    engine.rootContext()->setContextProperty(QStringLiteral("language"), &language);
    engine.rootContext()->setContextProperty(QStringLiteral("renderCapabilities"), &renderCapabilities);
    engine.rootContext()->setContextProperty(QStringLiteral("recentFiles"), &recentFiles);
    engine.rootContext()->setContextProperty(QStringLiteral("settings"), &settings);

    // Read-only capability summary for the settings page's About section.
    const auto &formatRegistry = NekoPic::Io::FormatRegistry::instance();
    QVariantMap formatInfo;
    formatInfo.insert(QStringLiteral("readableCount"), formatRegistry.readableExtensions().size());
    formatInfo.insert(QStringLiteral("writableCount"), formatRegistry.writableExtensions().size());
    formatInfo.insert(QStringLiteral("readable"), formatRegistry.readableExtensions());
    formatInfo.insert(QStringLiteral("writable"), formatRegistry.writableExtensions());
    engine.rootContext()->setContextProperty(QStringLiteral("formatRegistryInfo"), formatInfo);
    QObject::connect(&editor, &DocumentController::imageOpened, &recentFiles,
                     [&recentFiles](const QUrl &url) { recentFiles.add(url); });
    engine.addImageProvider(QStringLiteral("document"), new DocumentImageProvider(editor));
    engine.addImageProvider(QStringLiteral("filterpreview"), filterPreviews.createImageProvider().release());
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    // Optional command-line image: `nekopic photo.jpg`.
    const auto arguments = app.arguments();
    QString screenshotPath;
    QString startTool;
    QString languageOverride;
    bool openSettingsOnStart = false;
    for (int index = 1; index < arguments.size(); ++index) {
        const auto argument = arguments.at(index);
        if (argument == QLatin1String("--screenshot") && index + 1 < arguments.size()) {
            screenshotPath = arguments.at(++index);
            continue;
        }
        if (argument == QLatin1String("--language") && index + 1 < arguments.size()) {
            languageOverride = arguments.at(++index);
            continue;
        }
        if (argument == QLatin1String("--tool") && index + 1 < arguments.size()) {
            startTool = arguments.at(++index);
            continue;
        }
        if (argument == QLatin1String("--settings")) {
            openSettingsOnStart = true;
            continue;
        }
        if (argument.startsWith(QLatin1String("--"))) continue;
        editor.openImage(QUrl::fromLocalFile(argument));
    }

    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
    if (!startTool.isEmpty() && window) {
        window->setProperty("startupTool", startTool);
        window->setProperty("activeTool", startTool);
    }
    if (!languageOverride.isEmpty()) {
        // Launch-time override for screenshot/i18n QA: switch for this run but
        // keep the user's persisted language choice untouched.
        const auto persisted = QSettings().value(QStringLiteral("ui/language"));
        language.setLanguage(languageOverride);
        settings.setLocale(languageOverride);
        if (persisted.isValid())
            QSettings().setValue(QStringLiteral("ui/language"), persisted);
        else
            QSettings().remove(QStringLiteral("ui/language"));
    }
    if (openSettingsOnStart && window)
        QMetaObject::invokeMethod(window, "openSettings", Qt::QueuedConnection);

    // Development/visual-regression hook: render the window offscreen once the
    // document is idle, then exit. Never used by normal launches.
    if (!screenshotPath.isEmpty()) {
        if (window) {
            auto *poll = new QTimer(&app);
            auto attempts = std::make_shared<int>(0);
            QObject::connect(poll, &QTimer::timeout, &app, [&, window, poll, attempts, screenshotPath] {
                if (editor.busy() && ++(*attempts) < 40) return;
                poll->stop();
                window->grabWindow().save(screenshotPath);
                QCoreApplication::quit();
            });
            poll->start(100);
        }
    }

    renderCapabilities.probe();
    return app.exec();
}
