#include "app/documentcontroller.h"

#include <QFileInfo>
#include <QImageWriter>
#include <QTemporaryDir>
#include <QtTest>

class ExportFormatsTest final : public QObject {
    Q_OBJECT
private slots:
    void exposesWritableFormats()
    {
        DocumentController controller;
        const auto formats = controller.writableFormats();
        QVERIFY(!formats.isEmpty());
        bool hasPng = false;
        bool hasJpeg = false;
        for (const auto &entry : formats) {
            const auto map = entry.toMap();
            QVERIFY(!map.value(QStringLiteral("id")).toString().isEmpty());
            QVERIFY(!map.value(QStringLiteral("suffix")).toString().isEmpty());
            QVERIFY(!map.value(QStringLiteral("patterns")).toStringList().isEmpty());
            hasPng = hasPng || map.value(QStringLiteral("id")).toString() == QStringLiteral("png");
            hasJpeg = hasJpeg || map.value(QStringLiteral("id")).toString() == QStringLiteral("jpeg");
        }
        QVERIFY(hasPng);
        QVERIFY(hasJpeg);
    }

    void savesWebpThroughController()
    {
        if (!QImageWriter::supportedImageFormats().contains("webp"))
            QSKIP("WebP writer is not available in this build");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(12, 9, QImage::Format_RGBA8888);
        image.fill(QColor(30, 120, 200, 200));
        const auto source = dir.filePath(QStringLiteral("source.png"));
        QVERIFY(image.save(source));

        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(source));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        const auto target = dir.filePath(QStringLiteral("export.webp"));
        controller.saveAs(QUrl::fromLocalFile(target), QStringLiteral("webp"));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
        QVERIFY(QFileInfo::exists(target));
        QCOMPARE(controller.fileName(), QStringLiteral("export.webp"));
    }

    void exportOptionsClampAndPersist()
    {
        DocumentController controller;
        controller.setExportQuality(500);
        QCOMPARE(controller.exportQuality(), 100);
        controller.setExportQuality(-50);
        QCOMPARE(controller.exportQuality(), -1);
        controller.setJpegBackground(QColor(10, 20, 30, 40));
        QCOMPARE(controller.jpegBackground(), QColor(10, 20, 30, 255));
    }

    void savesJpegWithChosenQuality()
    {
        if (!QImageWriter::supportedImageFormats().contains("jpeg"))
            QSKIP("JPEG writer is not available in this build");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(32, 24, QImage::Format_RGBA8888);
        image.fill(QColor(120, 80, 40, 128));
        const auto source = dir.filePath(QStringLiteral("source.png"));
        QVERIFY(image.save(source));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(source));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.setExportQuality(20);
        controller.setJpegBackground(QColor(255, 0, 0));
        const auto target = dir.filePath(QStringLiteral("export.jpg"));
        controller.saveAs(QUrl::fromLocalFile(target), QStringLiteral("jpeg"));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY2(controller.errorMessage().isEmpty(), qPrintable(controller.errorMessage()));
        QVERIFY(QFileInfo::exists(target));
    }

    void rejectsMismatchedExtension()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(4, 4, QImage::Format_RGB32);
        image.fill(Qt::red);
        const auto source = dir.filePath(QStringLiteral("source.png"));
        QVERIFY(image.save(source));
        DocumentController controller;
        controller.openImage(QUrl::fromLocalFile(source));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        controller.saveAs(QUrl::fromLocalFile(dir.filePath(QStringLiteral("out.webp"))),
                          QStringLiteral("png"));
        QTRY_VERIFY_WITH_TIMEOUT(!controller.busy(), 5000);
        QVERIFY(!controller.errorMessage().isEmpty());
    }
};

QTEST_MAIN(ExportFormatsTest)
#include "tst_exportformats.moc"
