#pragma once

#include <QImage>
#include <QString>

namespace NekoPic::Platform {

// Copies the rendered image to the system clipboard. Returns false and fills
// error when the platform has no clipboard or the image is empty.
bool copyImage(const QImage &image, QString *error = nullptr);

} // namespace NekoPic::Platform
