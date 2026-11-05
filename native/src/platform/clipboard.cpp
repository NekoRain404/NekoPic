#include "clipboard.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QGuiApplication>

namespace NekoPic::Platform {

bool copyImage(const QImage &image, QString *error)
{
    if (image.isNull()) {
        if (error) *error = QCoreApplication::translate("Clipboard", "There is no image to copy.");
        return false;
    }
    auto *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        if (error) *error = QCoreApplication::translate("Clipboard", "The clipboard is unavailable.");
        return false;
    }
    clipboard->setImage(image);
    return true;
}

} // namespace NekoPic::Platform
