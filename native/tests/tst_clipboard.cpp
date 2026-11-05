#include "platform/clipboard.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QtTest>

using NekoPic::Platform::copyImage;

class ClipboardTest final : public QObject {
    Q_OBJECT
private slots:
    void copiesRenderedImage()
    {
        QImage image(7, 5, QImage::Format_RGBA8888);
        image.fill(QColor(12, 34, 56, 255));
        QString error;
        QVERIFY2(copyImage(image, &error), qPrintable(error));
        const auto copied = QGuiApplication::clipboard()->image();
        if (copied.isNull())
            QSKIP("The offscreen platform exposes no clipboard image");
        QCOMPARE(copied.size(), image.size());
    }

    void rejectsEmptyImage()
    {
        QString error;
        QVERIFY(!copyImage(QImage(), &error));
        QVERIFY(!error.isEmpty());
    }
};

QTEST_MAIN(ClipboardTest)
#include "tst_clipboard.moc"
