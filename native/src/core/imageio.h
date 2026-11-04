#pragma once

#include <QByteArray>
#include <QColor>
#include <QImage>
#include <QList>
#include <QString>

namespace NekoPic::ImageIO {

struct Limits {
    int maxDimension = 32768;
    qint64 maxPixels = 100'000'000;
};

struct LoadResult {
    QImage image;
    QString error;
};

struct SaveOptions {
    // Empty selects PNG or JPEG from the destination suffix.
    QByteArray format;
    QColor jpegBackground = Qt::white;
    int quality = -1;
};

struct SaveResult {
    bool success = false;
    QString error;
};

QList<QByteArray> supportedReadFormats();
LoadResult load(const QString &path, const Limits &limits = {});
SaveResult save(const QString &path, const QImage &image, const SaveOptions &options = {});

} // namespace NekoPic::ImageIO
