#include "documentcontroller.h"
#include "filterpreviews.h"
#include "languagemanager.h"
#include "platform/recentfiles.h"
#include "settingsmanager.h"
#include "render/rendercapabilities.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QTextStream>
#include <QTimer>

#include <memory>

class DocumentImageProvider final : public QQuickImageProvider {
public:
    explicit DocumentImageProvider(const DocumentController &controller)
        : QQuickImageProvider(QQuickImageProvider::Image), controller_(controller) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &) override
    {
        auto image = id.startsWith(QLatin1String("base")) ? controller_.baseImage()
                                                          : controller_.image();
        if (size) *size = image.size();
        return image;
    }
private:
    const DocumentController &controller_;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("NekoPic"));
    QCoreApplication::setApplicationName(QStringLiteral("NekoPic"));
    QCoreApplication::setApplicationVersion(QStringLiteral(NEKOPIC_VERSION));

    const auto earlyArguments = app.arguments();
    if (earlyArguments.contains(QStringLiteral("--version"))) {
        QTextStream(stdout) << "NekoPic " << QCoreApplication::applicationVersion() << "\n";
        return 0;
    }
    if (earlyArguments.contains(QStringLiteral("--help"))) {
        QTextStream(stdout)
            << "Usage: nekopic [image] [--screenshot <file>]\n"
               "  image               open an image on start\n"
               "  --screenshot <file> render the window to a PNG and exit\n"
               "  --version           print the version\n"
               "  --help              show this help\n";
        return 0;
    }
    DocumentController editor;
    FilterPreviews filterPreviews(editor);
    NekoPic::Render::RenderCapabilities renderCapabilities;
    NekoPic::Platform::RecentFiles recentFiles;
    SettingsManager settings;
    QQmlApplicationEngine engine;
    LanguageManager language(engine);
    engine.rootContext()->setContextProperty(QStringLiteral("editor"), &editor);
    engine.rootContext()->setContextProperty(QStringLiteral("filterPreviews"), &filterPreviews);
    engine.rootContext()->setContextProperty(QStringLiteral("language"), &language);
    engine.rootContext()->setContextProperty(QStringLiteral("renderCapabilities"), &renderCapabilities);
    engine.rootContext()->setContextProperty(QStringLiteral("recentFiles"), &recentFiles);
    engine.rootContext()->setContextProperty(QStringLiteral("settings"), &settings);
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
    bool openSettingsOnStart = false;
    for (int index = 1; index < arguments.size(); ++index) {
        const auto argument = arguments.at(index);
        if (argument == QLatin1String("--screenshot") && index + 1 < arguments.size()) {
            screenshotPath = arguments.at(++index);
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
    if (openSettingsOnStart && window)
        QMetaObject::invokeMethod(window, "openSettings");

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
