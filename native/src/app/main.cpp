#include "documentcontroller.h"
#include "filterpreviews.h"
#include "languagemanager.h"
#include "platform/recentfiles.h"
#include "render/rendercapabilities.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
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
    DocumentController editor;
    FilterPreviews filterPreviews(editor);
    NekoPic::Render::RenderCapabilities renderCapabilities;
    NekoPic::Platform::RecentFiles recentFiles;
    QQmlApplicationEngine engine;
    LanguageManager language(engine);
    engine.rootContext()->setContextProperty(QStringLiteral("editor"), &editor);
    engine.rootContext()->setContextProperty(QStringLiteral("filterPreviews"), &filterPreviews);
    engine.rootContext()->setContextProperty(QStringLiteral("language"), &language);
    engine.rootContext()->setContextProperty(QStringLiteral("renderCapabilities"), &renderCapabilities);
    engine.rootContext()->setContextProperty(QStringLiteral("recentFiles"), &recentFiles);
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
    for (int index = 1; index < arguments.size(); ++index) {
        const auto argument = arguments.at(index);
        if (argument == QLatin1String("--screenshot") && index + 1 < arguments.size()) {
            screenshotPath = arguments.at(++index);
            continue;
        }
        if (argument.startsWith(QLatin1String("--"))) continue;
        editor.openImage(QUrl::fromLocalFile(argument));
    }

    // Development/visual-regression hook: render the window offscreen once the
    // document is idle, then exit. Never used by normal launches.
    if (!screenshotPath.isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
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
