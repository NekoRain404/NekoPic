#include "documentcontroller.h"
#include "filterpreviews.h"
#include "languagemanager.h"
#include "render/rendercapabilities.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>

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
    QQmlApplicationEngine engine;
    LanguageManager language(engine);
    engine.rootContext()->setContextProperty(QStringLiteral("editor"), &editor);
    engine.rootContext()->setContextProperty(QStringLiteral("filterPreviews"), &filterPreviews);
    engine.rootContext()->setContextProperty(QStringLiteral("language"), &language);
    engine.rootContext()->setContextProperty(QStringLiteral("renderCapabilities"), &renderCapabilities);
    engine.addImageProvider(QStringLiteral("document"), new DocumentImageProvider(editor));
    engine.addImageProvider(QStringLiteral("filterpreview"), filterPreviews.createImageProvider().release());
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    renderCapabilities.probe();
    return app.exec();
}
