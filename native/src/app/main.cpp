#include "documentcontroller.h"
#include "languagemanager.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>

class DocumentImageProvider final : public QQuickImageProvider {
public:
    explicit DocumentImageProvider(const DocumentController &controller)
        : QQuickImageProvider(QQuickImageProvider::Image), controller_(controller) {}
    QImage requestImage(const QString &, QSize *size, const QSize &) override
    {
        auto image = controller_.image();
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
    QQmlApplicationEngine engine;
    LanguageManager language(engine);
    engine.rootContext()->setContextProperty(QStringLiteral("editor"), &editor);
    engine.rootContext()->setContextProperty(QStringLiteral("language"), &language);
    engine.addImageProvider(QStringLiteral("document"), new DocumentImageProvider(editor));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    return app.exec();
}
